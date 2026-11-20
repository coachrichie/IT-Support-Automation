#Requires -Version 5.1
<#
.SYNOPSIS
    Audits the effective local Windows Firewall profile settings.
.DESCRIPTION
    Reads Domain, Private and Public profiles from ActiveStore and writes a new
    CSV, JSON and log report. No firewall setting or rule is changed.
.PARAMETER OutputDirectory
    Parent directory for a unique report directory.
.EXAMPLE
    .\Invoke-FirewallProfileHealthAudit.ps1 -OutputDirectory C:\Reports
#>
[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$OutputDirectory = (Join-Path (Get-Location).Path 'reports')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Get-Command Get-NetFirewallProfile -ErrorAction SilentlyContinue)) {
    throw 'Get-NetFirewallProfile is unavailable. Run on a supported Windows Server with the NetSecurity module.'
}

$now = [DateTimeOffset]::UtcNow
$computerName = [string]$env:COMPUTERNAME
if ([string]::IsNullOrWhiteSpace($computerName)) { $computerName = [Environment]::MachineName }
$profiles = @(Get-NetFirewallProfile -PolicyStore ActiveStore -ErrorAction Stop)
if ($profiles.Count -eq 0) { throw 'ActiveStore returned no firewall profiles; no report was written.' }

$rows = @(foreach ($name in @('Domain', 'Private', 'Public')) {
    $matches = @($profiles | Where-Object { [string]$_.Name -eq $name })
    if ($matches.Count -gt 1) { throw "ActiveStore returned duplicate $name profiles." }
    if ($matches.Count -eq 0) {
        [pscustomobject]@{
            ComputerName = $computerName; Profile = $name; Enabled = ''
            DefaultInboundAction = ''; DefaultOutboundAction = ''; LogBlocked = ''
            LogFileName = ''; LogMaxSizeKilobytes = ''; Assessment = 'UnknownMissingProfile'
            AuditedAtUtc = $now.ToString('o')
        }
        continue
    }

    $profile = $matches[0]
    $enabled = [string]$profile.Enabled
    $inbound = [string]$profile.DefaultInboundAction
    $outbound = [string]$profile.DefaultOutboundAction
    $logBlocked = [string]$profile.LogBlocked
    $assessment = if ($enabled -eq 'False') {
        'ReviewFirewallDisabled'
    } elseif ($enabled -eq 'True' -and $inbound -eq 'Allow') {
        'ReviewDefaultInboundAllow'
    } elseif ($enabled -eq 'True' -and $inbound -eq 'Block' -and $logBlocked -eq 'False') {
        'ReviewBlockedLoggingOff'
    } elseif ($enabled -eq 'True' -and $inbound -eq 'Block' -and $logBlocked -eq 'True') {
        'Configured'
    } else {
        'UnknownReviewRequired'
    }

    [pscustomobject]@{
        ComputerName = $computerName
        Profile = $name
        Enabled = $enabled
        DefaultInboundAction = $inbound
        DefaultOutboundAction = $outbound
        LogBlocked = $logBlocked
        LogFileName = [string]$profile.LogFileName
        LogMaxSizeKilobytes = [string]$profile.LogMaxSizeKilobytes
        Assessment = $assessment
        AuditedAtUtc = $now.ToString('o')
    }
})

$parent = [System.IO.Path]::GetFullPath($OutputDirectory)
$runId = '{0}-{1}' -f $now.ToString('yyyyMMddTHHmmssZ'), ([guid]::NewGuid().ToString('N').Substring(0, 8))
$runDirectory = Join-Path $parent $runId
$null = New-Item -Path $runDirectory -ItemType Directory -ErrorAction Stop
$csvPath = Join-Path $runDirectory 'firewall-profiles.csv'
$jsonPath = Join-Path $runDirectory 'firewall-profiles.json'
$logPath = Join-Path $runDirectory 'audit.log'

try {
    $rows | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding UTF8 -ErrorAction Stop
    [pscustomobject]@{
        ComputerName = $computerName
        AuditedAtUtc = $now.ToString('o')
        PolicyStore = 'ActiveStore'
        Profiles = $rows
    } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $jsonPath -Encoding UTF8 -ErrorAction Stop
    @(
        "TimestampUtc=$($now.ToString('o'))"
        "ComputerName=$computerName"
        'PolicyStore=ActiveStore'
        "ProfileCount=$($profiles.Count)"
        "MissingProfileCount=$(@($rows | Where-Object Assessment -eq 'UnknownMissingProfile').Count)"
        'Result=Success'
    ) | Set-Content -LiteralPath $logPath -Encoding UTF8 -ErrorAction Stop
} catch {
    throw "Audit data was read, but report writing failed in '$runDirectory': $($_.Exception.Message)"
}

Write-Output ([pscustomobject]@{
    ComputerName = $computerName
    RunDirectory = $runDirectory
    CsvPath = $csvPath
    JsonPath = $jsonPath
    LogPath = $logPath
})
