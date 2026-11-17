[CmdletBinding()]
param(
    [string]$ResourceGroupName,
    [ValidateNotNullOrEmpty()]
    [string]$OutputDirectory = (Join-Path (Get-Location) 'Reports'),
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
    [string]$InputJsonPath,
    [switch]$OnlyReview
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-Field {
    param([object]$Object, [string]$Name)
    if ($null -eq $Object) { return $null }
    if ($Object -is [System.Collections.IDictionary]) {
        if ($Object.Contains($Name)) { return $Object[$Name] }
        return $null
    }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -ne $property) { return $property.Value }
    return $null
}

function Convert-PublicIp {
    param([object]$Address)
    foreach ($field in @('Name', 'ResourceGroupName')) {
        if ([string]::IsNullOrWhiteSpace([string](Get-Field -Object $Address -Name $field))) {
            throw "Public-IP-Datensatz ohne Pflichtfeld '$field'."
        }
    }
    $config = Get-Field -Object $Address -Name 'IpConfiguration'
    $configId = [string](Get-Field -Object $config -Name 'Id')
    $sku = Get-Field -Object $Address -Name 'Sku'
    $skuName = [string](Get-Field -Object $sku -Name 'Name')
    $ip = [string](Get-Field -Object $Address -Name 'IpAddress')
    $provisioning = [string](Get-Field -Object $Address -Name 'ProvisioningState')
    $finding = 'Configured'
    if ($provisioning -and $provisioning -ne 'Succeeded') { $finding = 'ReviewProvisioning' }
    elseif (-not $configId) { $finding = 'ReviewAssociation' }
    elseif (-not $ip -or $ip -eq 'Not Assigned') { $finding = 'ReviewAddress' }
    [pscustomobject][ordered]@{
        ResourceGroupName = [string](Get-Field -Object $Address -Name 'ResourceGroupName')
        Name = [string](Get-Field -Object $Address -Name 'Name')
        Location = [string](Get-Field -Object $Address -Name 'Location')
        IpAddress = $ip
        AllocationMethod = [string](Get-Field -Object $Address -Name 'PublicIpAllocationMethod')
        AddressVersion = [string](Get-Field -Object $Address -Name 'PublicIpAddressVersion')
        Sku = $skuName
        ProvisioningState = $provisioning
        IpConfigurationPresent = [bool]$configId
        Finding = $finding
        CheckedAtUtc = [DateTime]::UtcNow.ToString('o')
    }
}

if ($PSBoundParameters.ContainsKey('InputJsonPath')) {
    $payload = Get-Content -LiteralPath $InputJsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($null -eq $payload) { throw 'Die JSON-Eingabe ist leer.' }
    $addresses = @($payload)
} else {
    foreach ($module in @('Az.Accounts', 'Az.Network')) {
        if (-not (Get-Module -ListAvailable -Name $module)) { throw "Modul $module fehlt." }
        Import-Module $module -ErrorAction Stop
    }
    if ($null -eq (Get-AzContext)) { throw 'Kein Azure-Kontext. Zuerst Connect-AzAccount und das richtige Abonnement waehlen.' }
    $parameters = @{ ErrorAction = 'Stop' }
    if ($ResourceGroupName) { $parameters['ResourceGroupName'] = $ResourceGroupName }
    $addresses = @(Get-AzPublicIpAddress @parameters)
}

$rows = [System.Collections.Generic.List[object]]::new()
foreach ($address in $addresses) {
    if ($ResourceGroupName -and [string](Get-Field -Object $address -Name 'ResourceGroupName') -ne $ResourceGroupName) {
        continue
    }
    $row = Convert-PublicIp -Address $address
    if (-not $OnlyReview -or $row.Finding -ne 'Configured') { $rows.Add($row) }
}

if (-not (Test-Path -LiteralPath $OutputDirectory -PathType Container)) {
    New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
}
$stamp = [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ')
$csv = Join-Path $OutputDirectory "PublicIpInventoryAudit-$stamp.csv"
$json = Join-Path $OutputDirectory "PublicIpInventoryAudit-$stamp.json"
$log = Join-Path $OutputDirectory "PublicIpInventoryAudit-$stamp.log"
$ordered = @($rows | Sort-Object ResourceGroupName, Name)
if ($ordered.Count -gt 0) {
    $ordered | Export-Csv -LiteralPath $csv -NoTypeInformation -Encoding UTF8
} else {
    '"ResourceGroupName","Name","Location","IpAddress","AllocationMethod","AddressVersion","Sku","ProvisioningState","IpConfigurationPresent","Finding","CheckedAtUtc"' | Set-Content -LiteralPath $csv -Encoding UTF8
}
ConvertTo-Json -InputObject $ordered -Depth 4 | Set-Content -LiteralPath $json -Encoding UTF8
@(
    "CheckedAtUtc=$([DateTime]::UtcNow.ToString('o'))"
    "ResourcesRead=$($addresses.Count)"
    "RowsWritten=$($ordered.Count)"
    "ReviewRows=$(@($ordered | Where-Object { $_.Finding -ne 'Configured' }).Count)"
    "Csv=$csv"
    "Json=$json"
) | Set-Content -LiteralPath $log -Encoding UTF8
$ordered
