[CmdletBinding()]
param(
    [ValidateRange(30,270)]
    [int]$DaysInactive = 90,

    [ValidateSet('All','Windows','iOS','Android','macOS','ChromeOS')]
    [string]$Platform = 'All',

    [string]$OutputPath = (Join-Path $PWD ("intune-stale-devices-{0}.csv" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))),

    [switch]$IncludeUnknownLastSync,
    [switch]$NoExport
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Log {
    param([ValidateSet('INFO','WARN','ERROR')][string]$Level,[string]$Message)
    Write-Host ("[{0}][{1}] {2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'),$Level,$Message)
}

function Assert-Module {
    param([string]$Name)
    if (-not (Get-Module -ListAvailable -Name $Name)) {
        throw "Required module '$Name' is not installed. Install it with: Install-Module $Name -Scope CurrentUser"
    }
}

try {
    Assert-Module 'Microsoft.Graph.Authentication'
    Assert-Module 'Microsoft.Graph.DeviceManagement'

    $context = Get-MgContext
    if (-not $context) {
        Write-Log INFO 'Connecting to Microsoft Graph with read-only Intune device permission.'
        Connect-MgGraph -Scopes 'DeviceManagementManagedDevices.Read.All' -NoWelcome
        $context = Get-MgContext
    }

    if ('DeviceManagementManagedDevices.Read.All' -notin $context.Scopes -and
        'DeviceManagementManagedDevices.ReadWrite.All' -notin $context.Scopes) {
        throw 'The current Microsoft Graph session does not contain DeviceManagementManagedDevices.Read.All (or ReadWrite.All). Reconnect with the required scope.'
    }

    $cutoff = (Get-Date).ToUniversalTime().AddDays(-$DaysInactive)
    Write-Log INFO ("Finding Intune devices with last sync before {0:u}." -f $cutoff)

    $devices = Get-MgDeviceManagementManagedDevice -All -Property @(
        'id','deviceName','operatingSystem','osVersion','complianceState',
        'managementAgent','managedDeviceOwnerType','userPrincipalName',
        'serialNumber','azureADDeviceId','enrolledDateTime','lastSyncDateTime'
    )

    if ($Platform -ne 'All') {
        $devices = $devices | Where-Object { $_.OperatingSystem -eq $Platform }
    }

    $report = foreach ($device in $devices) {
        $lastSync = $device.LastSyncDateTime
        $isUnknown = $null -eq $lastSync
        $isStale = (-not $isUnknown) -and ($lastSync.ToUniversalTime() -lt $cutoff)

        if ($isStale -or ($IncludeUnknownLastSync -and $isUnknown)) {
            $daysSinceSync = if ($isUnknown) { $null } else { [math]::Floor(((Get-Date).ToUniversalTime() - $lastSync.ToUniversalTime()).TotalDays) }
            [pscustomobject]@{
                DeviceName             = $device.DeviceName
                OperatingSystem        = $device.OperatingSystem
                OSVersion              = $device.OSVersion
                ComplianceState        = $device.ComplianceState
                Ownership              = $device.ManagedDeviceOwnerType
                ManagementAgent        = $device.ManagementAgent
                UserPrincipalName      = $device.UserPrincipalName
                SerialNumber           = $device.SerialNumber
                IntuneManagedDeviceId  = $device.Id
                EntraDeviceId          = $device.AzureADDeviceId
                EnrolledDateTime       = $device.EnrolledDateTime
                LastSyncDateTime       = $lastSync
                DaysSinceLastSync      = $daysSinceSync
                Classification         = if ($isUnknown) { 'UnknownLastSync' } else { 'Stale' }
            }
        }
    }

    $report = @($report | Sort-Object @{Expression='DaysSinceLastSync';Descending=$true}, DeviceName)
    Write-Log INFO ("Found {0} candidate device(s)." -f $report.Count)

    if (-not $NoExport) {
        $directory = Split-Path -Parent $OutputPath
        if ($directory -and -not (Test-Path $directory)) {
            New-Item -ItemType Directory -Path $directory -Force | Out-Null
        }
        $report | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8
        Write-Log INFO ("CSV report written to {0}" -f $OutputPath)
    }

    $report
}
catch {
    Write-Log ERROR $_.Exception.Message
    throw
}
