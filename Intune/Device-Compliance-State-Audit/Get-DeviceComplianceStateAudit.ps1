[CmdletBinding()]
param(
    [ValidateNotNullOrEmpty()]
    [string]$OutputDirectory = (Join-Path (Get-Location) 'Reports'),
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
    [string]$InputJsonPath,
    [switch]$OnlyFindings
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-Value {
    param([object]$Item, [string]$Name)
    if ($Item -is [System.Collections.IDictionary]) {
        if ($Item.Contains($Name)) { return $Item[$Name] }
        return $null
    }
    $property = $Item.PSObject.Properties[$Name]
    if ($null -ne $property) { return $property.Value }
    return $null
}

function Convert-Device {
    param([object]$Device)
    foreach ($field in @('id', 'deviceName', 'operatingSystem', 'complianceState')) {
        if ($null -eq (Get-Value -Item $Device -Name $field)) {
            throw "Geraetedatensatz ohne Pflichtfeld '$field'."
        }
    }
    $state = [string](Get-Value -Item $Device -Name 'complianceState')
    $finding = switch ($state.ToLowerInvariant()) {
        'compliant' { 'Healthy' }
        'noncompliant' { 'Critical' }
        'ingraceperiod' { 'Warning' }
        'conflict' { 'Review' }
        'error' { 'Review' }
        'unknown' { 'Unknown' }
        'configmanager' { 'Unknown' }
        default { 'Unknown' }
    }
    [pscustomobject][ordered]@{
        DeviceId = [string](Get-Value -Item $Device -Name 'id')
        DeviceName = [string](Get-Value -Item $Device -Name 'deviceName')
        OperatingSystem = [string](Get-Value -Item $Device -Name 'operatingSystem')
        ComplianceState = $state
        Finding = $finding
        CheckedAtUtc = [DateTime]::UtcNow.ToString('o')
    }
}

$devices = [System.Collections.Generic.List[object]]::new()
if ($PSBoundParameters.ContainsKey('InputJsonPath')) {
    $payload = Get-Content -LiteralPath $InputJsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($null -eq $payload) { throw 'Die JSON-Eingabe ist leer.' }
    foreach ($device in @($payload)) { $devices.Add($device) }
} else {
    if (-not (Get-Module -ListAvailable -Name Microsoft.Graph.Authentication)) {
        throw 'Microsoft.Graph.Authentication fehlt. Offline-Test mit InputJsonPath ist ohne Modul moeglich.'
    }
    Import-Module Microsoft.Graph.Authentication -ErrorAction Stop
    if ($null -eq (Get-MgContext)) {
        throw 'Keine Graph-Verbindung. Zuerst Connect-MgGraph -Scopes DeviceManagementManagedDevices.Read.All ausfuehren.'
    }
    $uri = 'https://graph.microsoft.com/v1.0/deviceManagement/managedDevices?$select=id,deviceName,operatingSystem,complianceState'
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $pages = 0
    while ($uri) {
        $parsed = [Uri]$uri
        if ($parsed.Scheme -ne 'https' -or $parsed.Host -ne 'graph.microsoft.com' -or
            $parsed.AbsolutePath -ne '/v1.0/deviceManagement/managedDevices') {
            throw 'Unerwarteter Graph-Fortsetzungslink.'
        }
        if (-not $seen.Add($uri)) { throw 'Zyklischer Graph-Fortsetzungslink.' }
        $pages++
        if ($pages -gt 1000) { throw 'Maximale Seitenzahl erreicht; kein Teilbericht geschrieben.' }
        $page = Invoke-MgGraphRequest -Method GET -Uri $uri -ErrorAction Stop
        $values = Get-Value -Item $page -Name 'value'
        if ($null -eq $values) { throw 'Graph-Antwort ohne value-Liste.' }
        foreach ($device in @($values)) { $devices.Add($device) }
        $uri = [string](Get-Value -Item $page -Name '@odata.nextLink')
    }
}

$rows = [System.Collections.Generic.List[object]]::new()
foreach ($device in $devices) {
    $row = Convert-Device -Device $device
    if (-not $OnlyFindings -or $row.Finding -ne 'Healthy') { $rows.Add($row) }
}
if ($devices.Count -eq 0) { throw 'Keine verwalteten Geraete erhalten; kein Bericht erstellt.' }

if (-not (Test-Path -LiteralPath $OutputDirectory -PathType Container)) {
    New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
}
$stamp = [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ')
$csv = Join-Path $OutputDirectory "DeviceComplianceStateAudit-$stamp.csv"
$json = Join-Path $OutputDirectory "DeviceComplianceStateAudit-$stamp.json"
$log = Join-Path $OutputDirectory "DeviceComplianceStateAudit-$stamp.log"
$ordered = @($rows | Sort-Object Finding, DeviceName)
if ($ordered.Count -gt 0) {
    $ordered | Export-Csv -LiteralPath $csv -NoTypeInformation -Encoding UTF8
} else {
    '"DeviceId","DeviceName","OperatingSystem","ComplianceState","Finding","CheckedAtUtc"' | Set-Content -LiteralPath $csv -Encoding UTF8
}
ConvertTo-Json -InputObject $ordered -Depth 4 | Set-Content -LiteralPath $json -Encoding UTF8
@(
    "CheckedAtUtc=$([DateTime]::UtcNow.ToString('o'))"
    "DevicesRead=$($devices.Count)"
    "RowsWritten=$($ordered.Count)"
    "Findings=$(@($ordered | Where-Object { $_.Finding -ne 'Healthy' }).Count)"
    "Csv=$csv"
    "Json=$json"
) | Set-Content -LiteralPath $log -Encoding UTF8
$ordered
