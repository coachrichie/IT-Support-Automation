[CmdletBinding()]
param(
    [ValidateNotNullOrEmpty()]
    [string]$OutputDirectory = (Join-Path (Get-Location) 'Reports'),
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
    [string]$InputJsonPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-RegistryKey {
    param([string]$Path)
    try {
        $null = Get-Item -LiteralPath $Path -ErrorAction Stop
        return $true
    } catch [System.Management.Automation.ItemNotFoundException] {
        return $false
    } catch {
        return $null
    }
}

function Get-RegistryValue {
    param([string]$Path, [string]$Name)
    try {
        $key = Get-Item -LiteralPath $Path -ErrorAction Stop
        return $key.GetValue($Name, $null)
    } catch {
        return $null
    }
}

function Get-LiveSignals {
    $cbs = Test-RegistryKey -Path 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending'
    $wu = Test-RegistryKey -Path 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
    $fileOps = $null
    $session = 'Registry::HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Session Manager'
    try {
        $key = Get-Item -LiteralPath $session -ErrorAction Stop
        $value = $key.GetValue('PendingFileRenameOperations', $null)
        $fileOps = $null -ne $value -and @($value).Count -gt 0
    } catch {
        $fileOps = $null
    }
    $active = Get-RegistryValue -Path 'Registry::HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\ComputerName\ActiveComputerName' -Name 'ComputerName'
    $configured = Get-RegistryValue -Path 'Registry::HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\ComputerName\ComputerName' -Name 'ComputerName'
    $rename = $null
    if ($null -ne $active -and $null -ne $configured) {
        $rename = -not [string]::Equals([string]$active, [string]$configured, [System.StringComparison]::OrdinalIgnoreCase)
    }
    [pscustomobject]@{
        ComputerName = $env:COMPUTERNAME
        ComponentServicing = $cbs
        WindowsUpdate = $wu
        PendingFileRename = $fileOps
        ComputerRename = $rename
    }
}

function Assert-Signals {
    param([object]$Signals)
    foreach ($field in @('ComponentServicing', 'WindowsUpdate', 'PendingFileRename', 'ComputerRename')) {
        $property = $Signals.PSObject.Properties[$field]
        if ($null -eq $property) { throw "Eingabe ohne Pflichtfeld '$field'." }
        if ($null -ne $property.Value -and $property.Value -isnot [bool]) {
            throw "'$field' muss true, false oder null sein."
        }
    }
}

function Convert-Signals {
    param([object]$Signals)
    Assert-Signals -Signals $Signals
    $strong = @($Signals.ComponentServicing, $Signals.WindowsUpdate, $Signals.ComputerRename)
    $status = 'Clear'
    if ($strong -contains $true) { $status = 'Pending' }
    elseif ($strong -contains $null -or $null -eq $Signals.PendingFileRename) { $status = 'Unknown' }
    elseif ($Signals.PendingFileRename) { $status = 'ReviewFileOperations' }
    [pscustomobject][ordered]@{
        ComputerName = if ($Signals.PSObject.Properties['ComputerName'] -and $Signals.ComputerName) { [string]$Signals.ComputerName } else { $env:COMPUTERNAME }
        ComponentServicing = $Signals.ComponentServicing
        WindowsUpdate = $Signals.WindowsUpdate
        ComputerRename = $Signals.ComputerRename
        PendingFileRename = $Signals.PendingFileRename
        Status = $status
        CheckedAtUtc = [DateTime]::UtcNow.ToString('o')
    }
}

if ($PSBoundParameters.ContainsKey('InputJsonPath')) {
    $signals = Get-Content -LiteralPath $InputJsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($null -eq $signals -or @($signals).Count -ne 1) {
        throw 'Die Offline-Eingabe muss genau ein Signalobjekt enthalten.'
    }
    $signals = @($signals)[0]
} else {
    if ($env:OS -ne 'Windows_NT') { throw 'Live-Pruefung ist nur unter Windows moeglich.' }
    $signals = Get-LiveSignals
}
$result = Convert-Signals -Signals $signals

if (-not (Test-Path -LiteralPath $OutputDirectory -PathType Container)) {
    New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
}
$stamp = [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ')
$csv = Join-Path $OutputDirectory "PendingRebootSignalAudit-$stamp.csv"
$json = Join-Path $OutputDirectory "PendingRebootSignalAudit-$stamp.json"
$log = Join-Path $OutputDirectory "PendingRebootSignalAudit-$stamp.log"
$result | Export-Csv -LiteralPath $csv -NoTypeInformation -Encoding UTF8
ConvertTo-Json -InputObject $result -Depth 3 | Set-Content -LiteralPath $json -Encoding UTF8
@(
    "CheckedAtUtc=$($result.CheckedAtUtc)"
    "ComputerName=$($result.ComputerName)"
    "Status=$($result.Status)"
    "Csv=$csv"
    "Json=$json"
) | Set-Content -LiteralPath $log -Encoding UTF8
$result
