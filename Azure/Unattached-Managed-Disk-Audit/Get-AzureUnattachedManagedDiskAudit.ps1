[CmdletBinding()]
param(
    [ValidateRange(1,3650)]
    [int]$MinimumUnattachedDays = 30,

    [string[]]$SubscriptionId,

    [string]$ResourceGroupName,

    [string[]]$ExcludeTag = @('DoNotDelete','Keep','ASRReplica'),

    [string]$OutputPath = (Join-Path $PWD ("azure-unattached-disks-{0}.csv" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))),

    [switch]$IncludeUnknownAge,

    [switch]$NoExport
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Log {
    param([ValidateSet('INFO','WARN','ERROR')][string]$Level,[string]$Message)
    Write-Host "[$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))][$Level] $Message"
}

function Test-ExcludedTag {
    param($Tags,[string[]]$Names)
    if (-not $Tags) { return $false }
    foreach ($name in $Names) {
        if ($Tags.ContainsKey($name)) { return $true }
    }
    return $false
}

if (-not (Get-Module -ListAvailable -Name Az.Compute)) {
    throw 'Az.Compute is required. Install-Module Az -Scope CurrentUser'
}
if (-not (Get-Module -ListAvailable -Name Az.Accounts)) {
    throw 'Az.Accounts is required. Install-Module Az -Scope CurrentUser'
}

Import-Module Az.Accounts -ErrorAction Stop
Import-Module Az.Compute -ErrorAction Stop

if (-not (Get-AzContext -ErrorAction SilentlyContinue)) {
    Write-Log INFO 'No Azure context found; starting interactive authentication.'
    Connect-AzAccount -ErrorAction Stop | Out-Null
}

$contexts = @()
if ($SubscriptionId) {
    foreach ($id in $SubscriptionId) {
        $contexts += Set-AzContext -SubscriptionId $id -ErrorAction Stop
    }
} else {
    $contexts = @(Get-AzContext)
}

$now = Get-Date
$results = [System.Collections.Generic.List[object]]::new()

foreach ($context in $contexts) {
    Set-AzContext -SubscriptionId $context.Subscription.Id -ErrorAction Stop | Out-Null
    Write-Log INFO "Auditing subscription $($context.Subscription.Name) [$($context.Subscription.Id)]"

    try {
        $disks = if ($ResourceGroupName) {
            @(Get-AzDisk -ResourceGroupName $ResourceGroupName -ErrorAction Stop)
        } else {
            @(Get-AzDisk -ErrorAction Stop)
        }
    } catch {
        Write-Log ERROR "Failed to enumerate disks: $($_.Exception.Message)"
        continue
    }

    foreach ($disk in $disks) {
        if ($null -ne $disk.ManagedBy) { continue }
        if (Test-ExcludedTag -Tags $disk.Tags -Names $ExcludeTag) { continue }

        $ownershipTime = $disk.LastOwnershipUpdateTime
        $ageDays = $null
        if ($ownershipTime) {
            $ageDays = [math]::Floor(($now.ToUniversalTime() - ([datetime]$ownershipTime).ToUniversalTime()).TotalDays)
            if ($ageDays -lt $MinimumUnattachedDays) { continue }
        } elseif (-not $IncludeUnknownAge) {
            continue
        }

        $results.Add([pscustomobject]@{
            SubscriptionName       = $context.Subscription.Name
            SubscriptionId         = $context.Subscription.Id
            ResourceGroup          = $disk.ResourceGroupName
            DiskName               = $disk.Name
            Location               = $disk.Location
            DiskState              = $disk.DiskState
            Sku                    = $disk.Sku.Name
            SizeGB                 = $disk.DiskSizeGB
            ManagedBy              = $disk.ManagedBy
            LastOwnershipUpdateTime= $ownershipTime
            UnattachedDays         = $ageDays
            OsType                 = $disk.OsType
            HyperVGeneration       = $disk.HyperVGeneration
            EncryptionType         = $disk.Encryption.Type
            Tags                   = if ($disk.Tags) { ($disk.Tags.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ';' } else { '' }
            ResourceId             = $disk.Id
        })
    }
}

$ordered = @($results | Sort-Object @{Expression='UnattachedDays';Descending=$true}, SubscriptionName, ResourceGroup, DiskName)
Write-Log INFO "Found $($ordered.Count) candidate unattached managed disk(s)."

if (-not $NoExport) {
    $parent = Split-Path -Parent $OutputPath
    if ($parent -and -not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    $ordered | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8
    Write-Log INFO "Report exported to $OutputPath"
}

$ordered