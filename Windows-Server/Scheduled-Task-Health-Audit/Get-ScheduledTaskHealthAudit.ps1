#requires -Version 5.1
<#
.SYNOPSIS
    Audits the health of Windows scheduled tasks without changing them.

.DESCRIPTION
    Reads task definitions and run-time information locally or through CIM,
    classifies failures, stale executions, disabled tasks, and scheduler states,
    then exports a CSV report plus a log file.
#>
[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string[]]$ComputerName = @($env:COMPUTERNAME),

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$TaskPathFilter = '*',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$TaskNameFilter = '*',

    [Parameter()]
    [ValidateRange(1, 3650)]
    [int]$StaleAfterDays = 30,

    [Parameter()]
    [switch]$IncludeMicrosoftTasks,

    [Parameter()]
    [switch]$ExcludeDisabled,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$OutputDirectory = (Join-Path $PWD 'Reports')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-AuditLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR')] [string]$Level = 'INFO',
        [Parameter(Mandatory)] [string]$Path
    )

    $line = '{0:u} [{1}] {2}' -f (Get-Date), $Level, $Message
    Add-Content -LiteralPath $Path -Value $line -Encoding utf8
    Write-Verbose $line
}

function ConvertTo-ResultHex {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [long]$Value)

    $unsigned = [uint32]($Value -band 0xffffffffL)
    '0x{0:X8}' -f $unsigned
}

function ConvertTo-ScheduledTaskAuditRecord {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$ComputerName,
        [Parameter(Mandatory)] [object]$Task,
        [Parameter(Mandatory)] [object]$TaskInfo,
        [Parameter(Mandatory)] [datetime]$Now,
        [Parameter(Mandatory)] [ValidateRange(1, 3650)] [int]$StaleAfterDays
    )

    $resultCode = [long]$TaskInfo.LastTaskResult
    $resultHex = ConvertTo-ResultHex -Value $resultCode
    $lastRun = if ($null -eq $TaskInfo.LastRunTime) { $null } else { [datetime]$TaskInfo.LastRunTime }
    $nextRun = if ($null -eq $TaskInfo.NextRunTime) { $null } else { [datetime]$TaskInfo.NextRunTime }
    $neverRan = $null -eq $lastRun -or $lastRun.Year -le 1999
    $ageDays = if ($neverRan) { $null } else { [math]::Round(($Now - $lastRun).TotalDays, 2) }
    $state = [string]$Task.State
    $informationalCodes = @(
        0x00041300, 0x00041301, 0x00041302, 0x00041303, 0x00041304,
        0x00041305, 0x00041306, 0x00041307, 0x00041308, 0x00041325
    )

    $status = if ($state -eq 'Disabled') {
        'Disabled'
    }
    elseif ($state -eq 'Running') {
        'Running'
    }
    elseif ($neverRan) {
        'Never-Run'
    }
    elseif ($resultCode -ne 0 -and $informationalCodes -notcontains $resultCode) {
        'Failed'
    }
    elseif ($ageDays -gt $StaleAfterDays) {
        'Stale-LastRun'
    }
    elseif ($resultCode -ne 0) {
        'Scheduler-State'
    }
    else {
        'Healthy'
    }

    [pscustomobject]@{
        ComputerName   = $ComputerName
        TaskPath       = [string]$Task.TaskPath
        TaskName       = [string]$Task.TaskName
        State          = $state
        Status         = $status
        LastRunTime    = if ($neverRan) { $null } else { $lastRun }
        LastRunAgeDays = $ageDays
        NextRunTime    = $nextRun
        LastTaskResult = $resultCode
        ResultHex      = $resultHex
    }
}

function Invoke-ScheduledTaskHealthAudit {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string[]]$TargetComputer,
        [Parameter(Mandatory)] [string]$PathFilter,
        [Parameter(Mandatory)] [string]$NameFilter,
        [Parameter(Mandatory)] [int]$MaximumAgeDays,
        [Parameter(Mandatory)] [bool]$IncludeMicrosoft,
        [Parameter(Mandatory)] [bool]$SkipDisabled,
        [Parameter(Mandatory)] [string]$ReportDirectory
    )

    foreach ($commandName in 'Get-ScheduledTask', 'Get-ScheduledTaskInfo') {
        if (-not (Get-Command -Name $commandName -ErrorAction SilentlyContinue)) {
            throw "Erforderliches Cmdlet ist nicht verfügbar: $commandName"
        }
    }

    if (-not (Test-Path -LiteralPath $ReportDirectory)) {
        New-Item -ItemType Directory -Path $ReportDirectory -Force | Out-Null
    }

    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $csvPath = Join-Path $ReportDirectory "ScheduledTaskHealthAudit-$timestamp.csv"
    $logPath = Join-Path $ReportDirectory "ScheduledTaskHealthAudit-$timestamp.log"
    $now = Get-Date
    $results = [System.Collections.Generic.List[object]]::new()

    foreach ($computer in $TargetComputer) {
        $session = $null
        try {
            $isLocal = $computer -in @('.', 'localhost', $env:COMPUTERNAME)
            if (-not $isLocal) {
                $session = New-CimSession -ComputerName $computer -ErrorAction Stop
            }

            Write-AuditLog -Path $logPath -Message "Lese geplante Aufgaben auf '$computer'."
            $getParameters = @{ ErrorAction = 'Stop' }
            if ($null -ne $session) { $getParameters.CimSession = $session }

            $tasks = @(Get-ScheduledTask @getParameters | Where-Object {
                ([string]$_.TaskPath -like $PathFilter) -and
                ([string]$_.TaskName -like $NameFilter) -and
                ($IncludeMicrosoft -or [string]$_.TaskPath -notlike '\Microsoft\*') -and
                (-not $SkipDisabled -or [string]$_.State -ne 'Disabled')
            })

            foreach ($task in $tasks) {
                try {
                    $infoParameters = @{ InputObject = $task; ErrorAction = 'Stop' }
                    if ($null -ne $session) { $infoParameters.CimSession = $session }
                    $taskInfo = Get-ScheduledTaskInfo @infoParameters
                    $record = ConvertTo-ScheduledTaskAuditRecord -ComputerName $computer -Task $task -TaskInfo $taskInfo -Now $now -StaleAfterDays $MaximumAgeDays
                    $results.Add($record)
                }
                catch {
                    Write-AuditLog -Path $logPath -Level ERROR -Message "Aufgabe '$($task.TaskPath)$($task.TaskName)' auf '$computer' konnte nicht gelesen werden: $($_.Exception.Message)"
                    $results.Add([pscustomobject]@{
                        ComputerName = $computer; TaskPath = [string]$task.TaskPath; TaskName = [string]$task.TaskName
                        State = [string]$task.State; Status = 'Collection-Error'; LastRunTime = $null
                        LastRunAgeDays = $null; NextRunTime = $null; LastTaskResult = $null; ResultHex = $null
                    })
                }
            }
        }
        catch {
            Write-AuditLog -Path $logPath -Level ERROR -Message "Computer '$computer' konnte nicht geprüft werden: $($_.Exception.Message)"
            $results.Add([pscustomobject]@{
                ComputerName = $computer; TaskPath = ''; TaskName = ''; State = ''; Status = 'Computer-Error'
                LastRunTime = $null; LastRunAgeDays = $null; NextRunTime = $null; LastTaskResult = $null; ResultHex = $null
            })
        }
        finally {
            if ($null -ne $session) { Remove-CimSession -CimSession $session -ErrorAction SilentlyContinue }
        }
    }

    $results | Sort-Object ComputerName, TaskPath, TaskName | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding utf8
    Write-AuditLog -Path $logPath -Message ("Fertig: {0} Zielsysteme, {1} Reportzeilen, Ausgabe '{2}'." -f $TargetComputer.Count, $results.Count, $csvPath)

    [pscustomobject]@{
        ComputerCount = $TargetComputer.Count
        RecordCount   = $results.Count
        FindingCount  = @($results | Where-Object Status -in @('Failed', 'Stale-LastRun', 'Never-Run', 'Collection-Error', 'Computer-Error')).Count
        CsvPath       = $csvPath
        LogPath       = $logPath
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    Invoke-ScheduledTaskHealthAudit `
        -TargetComputer $ComputerName `
        -PathFilter $TaskPathFilter `
        -NameFilter $TaskNameFilter `
        -MaximumAgeDays $StaleAfterDays `
        -IncludeMicrosoft $IncludeMicrosoftTasks.IsPresent `
        -SkipDisabled $ExcludeDisabled.IsPresent `
        -ReportDirectory $OutputDirectory
}
