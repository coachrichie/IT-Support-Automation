[CmdletBinding()]
param(
    [ValidateNotNullOrEmpty()]
    [string[]]$ComputerName = @($env:COMPUTERNAME),
    [ValidateNotNullOrEmpty()]
    [string[]]$ServiceName = @('*'),
    [ValidateNotNullOrEmpty()]
    [string]$OutputDirectory = (Join-Path (Get-Location) 'Reports'),
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
    [string]$InputJsonPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function New-Result {
    param(
        [string]$Computer,
        [string]$Name,
        [string]$DisplayName,
        [string]$State,
        [string]$StartMode,
        [string]$Finding,
        [string]$Detail
    )
    [pscustomobject][ordered]@{
        ComputerName = $Computer
        ServiceName = $Name
        DisplayName = $DisplayName
        State = $State
        StartMode = $StartMode
        Finding = $Finding
        Detail = $Detail
        CheckedAtUtc = [DateTime]::UtcNow.ToString('o')
    }
}

function Get-Finding {
    param([string]$State, [string]$StartMode)
    if ($State -match 'Pending$') { return 'Transition' }
    if ($StartMode -eq 'Automatic' -and $State -ne 'Running') { return 'AutomaticNotRunning' }
    if ($StartMode -eq 'Disabled') { return 'Disabled' }
    if ($State -eq 'Running') { return 'Healthy' }
    return 'NotRunning'
}

function Convert-ToResult {
    param([object]$Service, [string]$DefaultComputer)
    foreach ($key in @('Name', 'DisplayName', 'State', 'StartMode')) {
        if (-not $Service.PSObject.Properties[$key]) {
            throw "Eingabedatensatz ohne Pflichtfeld '$key'."
        }
    }
    $computer = $DefaultComputer
    if ($Service.PSObject.Properties['ComputerName'] -and $Service.ComputerName) {
        $computer = [string]$Service.ComputerName
    }
    $state = [string]$Service.State
    $mode = [string]$Service.StartMode
    New-Result -Computer $computer -Name ([string]$Service.Name) `
        -DisplayName ([string]$Service.DisplayName) -State $state `
        -StartMode $mode -Finding (Get-Finding -State $state -StartMode $mode) -Detail ''
}

$results = [System.Collections.Generic.List[object]]::new()
$records = @()
if ($PSBoundParameters.ContainsKey('InputJsonPath')) {
    $payload = Get-Content -LiteralPath $InputJsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($null -eq $payload) { throw 'Die JSON-Eingabe ist leer.' }
    $records = @($payload)
} else {
    if ($env:OS -ne 'Windows_NT') { throw 'Live-Abfrage ist nur unter Windows moeglich.' }
    foreach ($computer in $ComputerName) {
        $session = $null
        try {
            if ($computer -eq $env:COMPUTERNAME -or $computer -eq 'localhost' -or $computer -eq '.') {
                $services = @(Get-CimInstance -ClassName Win32_Service -ErrorAction Stop)
            } else {
                $session = New-CimSession -ComputerName $computer -ErrorAction Stop
                $services = @(Get-CimInstance -CimSession $session -ClassName Win32_Service -ErrorAction Stop)
            }
            foreach ($service in $services) {
                $service | Add-Member -NotePropertyName ComputerName -NotePropertyValue $computer -Force
                $records += $service
            }
        } catch {
            $results.Add((New-Result -Computer $computer -Finding 'CollectionError' -Detail $_.Exception.Message))
        } finally {
            if ($null -ne $session) { Remove-CimSession -CimSession $session -ErrorAction SilentlyContinue }
        }
    }
}

foreach ($record in $records) {
    $match = $false
    foreach ($pattern in $ServiceName) {
        if ([string]$record.Name -like $pattern) { $match = $true; break }
    }
    if ($match) {
        $results.Add((Convert-ToResult -Service $record -DefaultComputer $env:COMPUTERNAME))
    }
}

foreach ($computer in $ComputerName) {
    if (@($results | Where-Object { $_.ComputerName -eq $computer -and $_.Finding -eq 'CollectionError' }).Count -gt 0) {
        continue
    }
    foreach ($name in $ServiceName) {
        if ($name -match '[*?\[]') { continue }
        if (-not @($results | Where-Object { $_.ComputerName -eq $computer -and $_.ServiceName -eq $name }).Count) {
            $results.Add((New-Result -Computer $computer -Name $name -Finding 'Missing' -Detail 'Dienstname nicht gefunden oder nicht lesbar.'))
        }
    }
}

if ($results.Count -eq 0) {
    throw 'Keine Dienste passen zu den Filtern; kein Bericht erstellt.'
}

if (-not (Test-Path -LiteralPath $OutputDirectory -PathType Container)) {
    New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
}
$stamp = [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ')
$csv = Join-Path $OutputDirectory "ServiceHealthAudit-$stamp.csv"
$json = Join-Path $OutputDirectory "ServiceHealthAudit-$stamp.json"
$log = Join-Path $OutputDirectory "ServiceHealthAudit-$stamp.log"
$ordered = @($results | Sort-Object ComputerName, ServiceName)
$ordered | Export-Csv -LiteralPath $csv -NoTypeInformation -Encoding UTF8
ConvertTo-Json -InputObject $ordered -Depth 4 | Set-Content -LiteralPath $json -Encoding UTF8
@(
    "CheckedAtUtc=$([DateTime]::UtcNow.ToString('o'))"
    "Records=$($ordered.Count)"
    "Findings=$(@($ordered | Where-Object { $_.Finding -ne 'Healthy' }).Count)"
    "Csv=$csv"
    "Json=$json"
) | Set-Content -LiteralPath $log -Encoding UTF8
$ordered
