[CmdletBinding()]
param(
    [ValidateNotNullOrEmpty()]
    [string[]]$ComputerName = @($env:COMPUTERNAME),
    [ValidateRange(1, 99)]
    [int]$WarningFreePercent = 15,
    [ValidateRange(1, 98)]
    [int]$CriticalFreePercent = 5,
    [ValidateNotNullOrEmpty()]
    [string]$OutputDirectory = (Join-Path (Get-Location) 'Reports'),
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
    [string]$InputJsonPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($CriticalFreePercent -ge $WarningFreePercent) {
    throw 'CriticalFreePercent muss kleiner als WarningFreePercent sein.'
}

function New-AuditRow {
    param(
        [string]$Computer,
        [string]$Volume,
        [string]$Label,
        [string]$FileSystem,
        [object]$SizeGiB,
        [object]$FreeGiB,
        [object]$FreePercent,
        [string]$Finding,
        [string]$Detail
    )
    [pscustomobject][ordered]@{
        ComputerName = $Computer
        Volume = $Volume
        VolumeLabel = $Label
        FileSystem = $FileSystem
        SizeGiB = $SizeGiB
        FreeGiB = $FreeGiB
        FreePercent = $FreePercent
        Finding = $Finding
        Detail = $Detail
        CheckedAtUtc = [DateTime]::UtcNow.ToString('o')
    }
}

function Convert-DiskRow {
    param([object]$Disk, [string]$DefaultComputer)
    foreach ($field in @('DeviceID', 'DriveType', 'Size', 'FreeSpace')) {
        if (-not $Disk.PSObject.Properties[$field]) {
            throw "Datensatz ohne Pflichtfeld '$field'."
        }
    }
    $computer = $DefaultComputer
    if ($Disk.PSObject.Properties['ComputerName'] -and $Disk.ComputerName) {
        $computer = [string]$Disk.ComputerName
    }
    if ([int]$Disk.DriveType -ne 3) { return }
    $label = if ($Disk.PSObject.Properties['VolumeName']) { [string]$Disk.VolumeName } else { '' }
    $fileSystem = if ($Disk.PSObject.Properties['FileSystem']) { [string]$Disk.FileSystem } else { '' }
    $volume = [string]$Disk.DeviceID
    try {
        $size = [decimal]$Disk.Size
        $free = [decimal]$Disk.FreeSpace
        if ($size -le 0 -or $free -lt 0 -or $free -gt $size) {
            throw 'Ungueltige Groessenwerte.'
        }
    } catch {
        return New-AuditRow -Computer $computer -Volume $volume -Label $label `
            -FileSystem $fileSystem -Finding 'InvalidData' -Detail 'Size/FreeSpace ungueltig oder nicht lesbar.'
    }
    $factor = [decimal]1073741824
    $percent = [Math]::Round(($free / $size) * 100, 2)
    $finding = 'Healthy'
    if ($percent -le $CriticalFreePercent) { $finding = 'Critical' }
    elseif ($percent -le $WarningFreePercent) { $finding = 'Warning' }
    New-AuditRow -Computer $computer -Volume $volume -Label $label `
        -FileSystem $fileSystem -SizeGiB ([Math]::Round($size / $factor, 2)) `
        -FreeGiB ([Math]::Round($free / $factor, 2)) -FreePercent $percent `
        -Finding $finding -Detail ''
}

$results = [System.Collections.Generic.List[object]]::new()
if ($PSBoundParameters.ContainsKey('InputJsonPath')) {
    $payload = Get-Content -LiteralPath $InputJsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($null -eq $payload) { throw 'Die JSON-Eingabe ist leer.' }
    foreach ($disk in @($payload)) {
        $row = Convert-DiskRow -Disk $disk -DefaultComputer $ComputerName[0]
        if ($null -ne $row) { $results.Add($row) }
    }
} else {
    if ($env:OS -ne 'Windows_NT') { throw 'Live-Abfrage ist nur unter Windows moeglich.' }
    foreach ($computer in $ComputerName) {
        try {
            $parameters = @{ ClassName = 'Win32_LogicalDisk'; Filter = 'DriveType = 3'; ErrorAction = 'Stop' }
            if ($computer -ne $env:COMPUTERNAME -and $computer -ne 'localhost' -and $computer -ne '.') {
                $parameters['ComputerName'] = $computer
            }
            $disks = @(Get-CimInstance @parameters)
            if ($disks.Count -eq 0) {
                $results.Add((New-AuditRow -Computer $computer -Finding 'NoLocalDisks' -Detail 'Keine lokalen logischen Laufwerke gefunden.'))
            }
            foreach ($disk in $disks) {
                $row = Convert-DiskRow -Disk $disk -DefaultComputer $computer
                if ($null -ne $row) { $results.Add($row) }
            }
        } catch {
            $results.Add((New-AuditRow -Computer $computer -Finding 'CollectionError' -Detail $_.Exception.Message))
        }
    }
}

if ($results.Count -eq 0) { throw 'Keine lokalen logischen Laufwerke in der Eingabe; kein Bericht erstellt.' }
if (-not (Test-Path -LiteralPath $OutputDirectory -PathType Container)) {
    New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
}
$stamp = [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ')
$csv = Join-Path $OutputDirectory "DiskFreeSpaceAudit-$stamp.csv"
$json = Join-Path $OutputDirectory "DiskFreeSpaceAudit-$stamp.json"
$log = Join-Path $OutputDirectory "DiskFreeSpaceAudit-$stamp.log"
$ordered = @($results | Sort-Object ComputerName, Volume)
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
