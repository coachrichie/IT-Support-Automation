[CmdletBinding()]
param(
    [string]$PolicyName,

    [ValidateSet('All','Classic','App')]
    [string]$PolicyType = 'All',

    [string]$OutputPath = (Join-Path -Path $PWD -ChildPath ("purview-retention-distribution-{0}.csv" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))),

    [switch]$IncludeHealthy,

    [switch]$NoExport
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Log {
    param(
        [Parameter(Mandatory)][ValidateSet('INFO','WARN','ERROR')][string]$Level,
        [Parameter(Mandatory)][string]$Message
    )
    Write-Host ("[{0}][{1}] {2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message)
}

function Assert-Command {
    param([Parameter(Mandatory)][string]$Name)
    if (-not (Get-Command -Name $Name -ErrorAction SilentlyContinue)) {
        throw "Required command '$Name' is unavailable. Install/update ExchangeOnlineManagement and connect with Connect-IPPSSession."
    }
}

function Convert-DistributionResults {
    param($Results)
    if ($null -eq $Results) { return '' }
    if ($Results -is [string]) { return $Results }
    return (($Results | ForEach-Object { $_.ToString() }) -join ' | ')
}

function Get-PolicyRows {
    param(
        [Parameter(Mandatory)][ValidateSet('Classic','App')][string]$Type
    )

    $cmd = if ($Type -eq 'Classic') { 'Get-RetentionCompliancePolicy' } else { 'Get-AppRetentionCompliancePolicy' }
    Assert-Command -Name $cmd

    Write-Log INFO "Reading $Type retention policies with distribution detail."
    $items = if ([string]::IsNullOrWhiteSpace($PolicyName)) {
        & $cmd -DistributionDetail
    }
    else {
        @(& $cmd -Identity $PolicyName -DistributionDetail)
    }

    foreach ($policy in $items) {
        $status = [string]$policy.DistributionStatus
        $details = Convert-DistributionResults -Results $policy.DistributionResults

        $severity = switch -Regex ($status) {
            'Error|Failed' { 'Error'; break }
            'Pending'      { 'Pending'; break }
            'Warning'      { 'Warning'; break }
            default        { 'Healthy' }
        }

        if (-not $IncludeHealthy -and $severity -eq 'Healthy') { continue }

        [pscustomobject]@{
            PolicyType          = $Type
            Name                = $policy.Name
            Guid                = $policy.Guid
            Enabled             = $policy.Enabled
            DistributionStatus  = $status
            Severity            = $severity
            DistributionResults = $details
            RestrictiveRetention = if ($policy.PSObject.Properties.Name -contains 'RestrictiveRetention') { $policy.RestrictiveRetention } else { $null }
            CheckedAtUtc        = (Get-Date).ToUniversalTime().ToString('o')
        }
    }
}

try {
    Assert-Command -Name 'Get-RetentionCompliancePolicy'

    $rows = @()
    if ($PolicyType -in @('All','Classic')) {
        $rows += @(Get-PolicyRows -Type Classic)
    }
    if ($PolicyType -in @('All','App')) {
        try {
            $rows += @(Get-PolicyRows -Type App)
        }
        catch {
            if ($PolicyType -eq 'App') { throw }
            Write-Log WARN "App retention policies could not be queried: $($_.Exception.Message)"
        }
    }

    $rows = @($rows | Sort-Object Severity, PolicyType, Name)

    $errorCount = @($rows | Where-Object Severity -eq 'Error').Count
    $pendingCount = @($rows | Where-Object Severity -eq 'Pending').Count
    $warningCount = @($rows | Where-Object Severity -eq 'Warning').Count

    Write-Log INFO "Report rows: $($rows.Count); Errors: $errorCount; Pending: $pendingCount; Warnings: $warningCount."

    if (-not $NoExport) {
        $parent = Split-Path -Parent $OutputPath
        if ($parent -and -not (Test-Path $parent)) {
            New-Item -ItemType Directory -Path $parent -Force | Out-Null
        }
        $rows | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8
        Write-Log INFO "CSV exported to '$OutputPath'."
    }

    $rows
}
catch {
    Write-Log ERROR $_.Exception.Message
    throw
}
