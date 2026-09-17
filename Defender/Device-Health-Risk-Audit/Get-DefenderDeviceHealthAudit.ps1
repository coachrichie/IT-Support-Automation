[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$AccessToken,

    [ValidateRange(7, 180)]
    [int]$InactiveDays = 30,

    [ValidateSet('None', 'Informational', 'Low', 'Medium', 'High')]
    [string[]]$RiskScore = @('Medium', 'High'),

    [ValidateSet('None', 'Low', 'Medium', 'High')]
    [string[]]$ExposureLevel = @('Medium', 'High'),

    [string[]]$OsPlatform,

    [string[]]$ExcludeTag,

    [string]$OutputPath = (Join-Path $PWD ("defender-device-health-{0}.csv" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))),

    [switch]$IncludeHealthy,

    [switch]$NoExport
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ApiRoot = 'https://api.security.microsoft.com/api'

function Write-Log {
    param(
        [Parameter(Mandatory)][ValidateSet('INFO','WARN','ERROR')][string]$Level,
        [Parameter(Mandatory)][string]$Message
    )
    Write-Host ("[{0}][{1}] {2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message)
}

function Invoke-DefenderGet {
    param(
        [Parameter(Mandatory)][string]$Uri,
        [Parameter(Mandatory)][string]$Token
    )

    $headers = @{ Authorization = "Bearer $Token" }
    $results = [System.Collections.Generic.List[object]]::new()
    $next = $Uri

    while ($next) {
        try {
            $response = Invoke-RestMethod -Method Get -Uri $next -Headers $headers -ContentType 'application/json'
        }
        catch {
            throw "Defender API request failed for '$next': $($_.Exception.Message)"
        }

        if ($null -ne $response.value) {
            foreach ($item in $response.value) { $results.Add($item) }
        }
        else {
            $results.Add($response)
        }

        $next = $null
        if ($response.PSObject.Properties.Name -contains '@odata.nextLink') {
            $next = $response.'@odata.nextLink'
        }
    }

    return $results
}

function Get-SeverityRank {
    param([AllowNull()][string]$Value)
    switch ($Value) {
        'High'          { 4 }
        'Medium'        { 3 }
        'Low'           { 2 }
        'Informational' { 1 }
        default         { 0 }
    }
}

$cutoff = (Get-Date).ToUniversalTime().AddDays(-$InactiveDays)
Write-Log INFO ("Retrieving Defender for Endpoint machine inventory. Inactivity cutoff: {0:u}" -f $cutoff)

$machines = Invoke-DefenderGet -Uri "$ApiRoot/machines?`$top=10000" -Token $AccessToken
Write-Log INFO ("Retrieved {0} machine records." -f $machines.Count)

$report = foreach ($machine in $machines) {
    $lastSeen = if ($machine.lastSeen) { [datetime]$machine.lastSeen } else { $null }
    $isInactive = ($machine.healthStatus -eq 'Inactive') -or ($lastSeen -and $lastSeen.ToUniversalTime() -lt $cutoff)
    $hasRisk = $RiskScore -contains [string]$machine.riskScore
    $hasExposure = $ExposureLevel -contains [string]$machine.exposureLevel
    $platformMatch = (-not $OsPlatform) -or ($OsPlatform -contains [string]$machine.osPlatform)
    $tags = @($machine.machineTags)
    $excluded = $false
    if ($ExcludeTag) {
        foreach ($tag in $ExcludeTag) {
            if ($tags -contains $tag) { $excluded = $true; break }
        }
    }

    $reasons = [System.Collections.Generic.List[string]]::new()
    if ($isInactive) { $reasons.Add("InactiveOrLastSeen>${InactiveDays}d") }
    if ($hasRisk) { $reasons.Add("Risk=$($machine.riskScore)") }
    if ($hasExposure) { $reasons.Add("Exposure=$($machine.exposureLevel)") }
    if ($machine.healthStatus -in @('ImpairedCommunication','NoSensorData','NoSensorDataImpairedCommunication')) {
        $reasons.Add("Health=$($machine.healthStatus)")
    }

    $needsReview = $isInactive -or $hasRisk -or $hasExposure -or ($machine.healthStatus -notin @('Active','Inactive'))
    if ($platformMatch -and -not $excluded -and ($IncludeHealthy -or $needsReview)) {
        $priority = [Math]::Max((Get-SeverityRank $machine.riskScore), (Get-SeverityRank $machine.exposureLevel))
        if ($machine.healthStatus -in @('ImpairedCommunication','NoSensorData','NoSensorDataImpairedCommunication')) { $priority = [Math]::Max($priority, 3) }
        if ($isInactive -and $priority -lt 2) { $priority = 2 }

        [pscustomobject]@{
            ComputerDnsName  = $machine.computerDnsName
            MachineId        = $machine.id
            AadDeviceId      = $machine.aadDeviceId
            OsPlatform       = $machine.osPlatform
            OsBuild          = $machine.osBuild
            HealthStatus     = $machine.healthStatus
            LastSeenUtc      = if ($lastSeen) { $lastSeen.ToUniversalTime().ToString('o') } else { $null }
            DaysSinceSeen    = if ($lastSeen) { [math]::Floor(((Get-Date).ToUniversalTime() - $lastSeen.ToUniversalTime()).TotalDays) } else { $null }
            RiskScore        = $machine.riskScore
            ExposureLevel    = $machine.exposureLevel
            DeviceValue      = $machine.deviceValue
            OnboardingStatus = $machine.onboardingStatus
            RbacGroupName    = $machine.rbacGroupName
            Tags             = ($tags -join ';')
            Priority         = switch ($priority) { 4 {'Critical'} 3 {'High'} 2 {'Medium'} 1 {'Low'} default {'Info'} }
            ReviewReason     = ($reasons -join '; ')
        }
    }
}

$report = @($report | Sort-Object @{Expression={ switch ($_.Priority) {'Critical'{4};'High'{3};'Medium'{2};'Low'{1};default{0}} }; Descending=$true}, @{Expression='DaysSinceSeen';Descending=$true})
Write-Log INFO ("{0} devices matched the review criteria." -f $report.Count)

if (-not $NoExport) {
    $parent = Split-Path -Parent $OutputPath
    if ($parent -and -not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    $report | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8
    Write-Log INFO "Report exported to $OutputPath"
}

$report
