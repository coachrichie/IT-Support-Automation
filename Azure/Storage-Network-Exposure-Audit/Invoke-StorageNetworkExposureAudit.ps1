#Requires -Version 7.2
<#
.SYNOPSIS
    Audits Azure Storage account network configuration in the selected subscription.
.DESCRIPTION
    Reads management-plane properties only. Creates CSV, JSON and log files in a new
    timestamped run directory. It never changes Azure resources or reads account keys.
.PARAMETER OutputDirectory
    Parent directory for a unique audit run directory.
.EXAMPLE
    Connect-AzAccount
    Set-AzContext -Subscription 'example-subscription-name'
    ./Invoke-StorageNetworkExposureAudit.ps1 -OutputDirectory ./reports
#>
[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$OutputDirectory = (Join-Path (Get-Location).Path 'reports')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-SafeValue {
    param([object]$Object, [string]$Name)
    if ($null -eq $Object) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

foreach ($commandName in @('Get-AzContext', 'Get-AzStorageAccount')) {
    if (-not (Get-Command $commandName -ErrorAction SilentlyContinue)) {
        throw "Required command $commandName is unavailable. Install Az.Accounts and Az.Storage."
    }
}

$context = Get-AzContext
if ($null -eq $context -or $null -eq $context.Subscription -or
    [string]::IsNullOrWhiteSpace([string]$context.Subscription.Id)) {
    throw 'No Azure subscription is selected. Run Connect-AzAccount and Set-AzContext first.'
}

$subscriptionId = [string]$context.Subscription.Id
$accounts = @(Get-AzStorageAccount -DefaultProfile $context)
$now = [DateTimeOffset]::UtcNow
$rows = @(foreach ($account in $accounts) {
    $rules = Get-SafeValue $account 'NetworkRuleSet'
    $publicAccess = [string](Get-SafeValue $account 'PublicNetworkAccess')
    $defaultAction = [string](Get-SafeValue $rules 'DefaultAction')
    $bypass = [string](Get-SafeValue $rules 'Bypass')
    $ipRules = @(Get-SafeValue $rules 'IPRules' | Where-Object { $null -ne $_ })
    $virtualNetworkRules = @(Get-SafeValue $rules 'VirtualNetworkRules' | Where-Object { $null -ne $_ })
    $resourceAccessRules = @(Get-SafeValue $rules 'ResourceAccessRules' | Where-Object { $null -ne $_ })

    $assessment = if ($publicAccess -eq 'Disabled') {
        'PublicAccessDisabled'
    } elseif ($publicAccess -eq 'Enabled' -and $defaultAction -eq 'Allow') {
        'ReviewAllNetworks'
    } elseif ($publicAccess -eq 'Enabled' -and $defaultAction -eq 'Deny') {
        'ReviewSelectedNetworks'
    } else {
        'UnknownReviewRequired'
    }

    [pscustomobject]@{
        SubscriptionId        = $subscriptionId
        ResourceGroup         = [string](Get-SafeValue $account 'ResourceGroupName')
        StorageAccount        = [string](Get-SafeValue $account 'StorageAccountName')
        ResourceId            = [string](Get-SafeValue $account 'Id')
        PublicNetworkAccess   = $publicAccess
        DefaultAction         = $defaultAction
        Bypass                = $bypass
        IpRuleCount           = $ipRules.Count
        VirtualNetworkCount   = $virtualNetworkRules.Count
        ResourceAccessCount   = $resourceAccessRules.Count
        Assessment            = $assessment
        AuditedAtUtc          = $now.ToString('o')
    }
})

$parent = [System.IO.Path]::GetFullPath($OutputDirectory)
$runId = '{0}-{1}' -f $now.ToString('yyyyMMddTHHmmssZ'), ([guid]::NewGuid().ToString('N').Substring(0, 8))
$runDirectory = Join-Path $parent $runId
$null = New-Item -ItemType Directory -Path $runDirectory -ErrorAction Stop
$csvPath = Join-Path $runDirectory 'storage-network-exposure.csv'
$jsonPath = Join-Path $runDirectory 'storage-network-exposure.json'
$logPath = Join-Path $runDirectory 'audit.log'

try {
    if ($rows.Count -gt 0) {
        $rows | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding utf8 -ErrorAction Stop
    } else {
        '"SubscriptionId","ResourceGroup","StorageAccount","ResourceId","PublicNetworkAccess","DefaultAction","Bypass","IpRuleCount","VirtualNetworkCount","ResourceAccessCount","Assessment","AuditedAtUtc"' |
            Set-Content -LiteralPath $csvPath -Encoding utf8 -ErrorAction Stop
    }
    $summary = [pscustomobject]@{
        SubscriptionId = $subscriptionId
        AuditedAtUtc = $now.ToString('o')
        AccountCount = $rows.Count
        Accounts = @($rows)
    }
    $summary | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $jsonPath -Encoding utf8 -ErrorAction Stop
    @(
        "TimestampUtc=$($now.ToString('o'))"
        "SubscriptionId=$subscriptionId"
        "AccountCount=$($rows.Count)"
        'Result=Success'
    ) | Set-Content -LiteralPath $logPath -Encoding utf8 -ErrorAction Stop
} catch {
    Write-Error "Audit data was read but output could not be written to '$runDirectory': $($_.Exception.Message)"
    throw
}

Write-Output ([pscustomobject]@{
    SubscriptionId = $subscriptionId
    AccountCount = $rows.Count
    RunDirectory = $runDirectory
    CsvPath = $csvPath
    JsonPath = $jsonPath
    LogPath = $logPath
})
