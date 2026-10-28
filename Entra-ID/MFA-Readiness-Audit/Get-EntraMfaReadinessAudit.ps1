[CmdletBinding()]
param(
    [string]$OutputPath = (Join-Path $PWD ("entra-mfa-readiness-{0}.csv" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))),

    [string]$SummaryPath = (Join-Path $PWD ("entra-mfa-readiness-summary-{0}.json" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))),

    [string]$LogPath = (Join-Path $PWD ("entra-mfa-readiness-{0}.log" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))),

    [string]$InputCsvPath,

    [ValidateRange(1, 168)]
    [int]$MaxReportAgeHours = 48,

    [switch]$IncludeGuests,

    [switch]$IncludeHealthy,

    [switch]$RequirePasswordless,

    [switch]$NoExport,

    [switch]$DisconnectOnExit
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:StartedGraphConnection = $false

function Write-AuditLog {
    param(
        [Parameter(Mandatory)]
        [ValidateSet('INFO', 'WARN', 'ERROR')]
        [string]$Level,

        [Parameter(Mandatory)]
        [string]$Message
    )

    $line = '[{0}][{1}] {2}' -f (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'), $Level, $Message
    $directory = Split-Path -Parent $LogPath
    if ($directory -and -not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
    Add-Content -LiteralPath $LogPath -Value $line -Encoding utf8
    Write-Verbose $line
}

function ConvertTo-StrictBoolean {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [object]$Value,

        [Parameter(Mandatory)]
        [string]$FieldName
    )

    if ($Value -is [bool]) { return $Value }
    $parsed = $false
    if ([bool]::TryParse([string]$Value, [ref]$parsed)) { return $parsed }
    throw "Field '$FieldName' contains invalid Boolean value '$Value'."
}

function Assert-RequiredModule {
    param([Parameter(Mandatory)][string]$Name)

    if (-not (Get-Module -ListAvailable -Name $Name)) {
        throw "Required module '$Name' is not installed. Install it with: Install-Module $Name -Scope CurrentUser"
    }
    Import-Module $Name -ErrorAction Stop
}

function Assert-GraphConnection {
    $requiredScope = 'AuditLog.Read.All'
    $context = Get-MgContext
    if (-not $context) {
        Write-AuditLog -Level INFO -Message 'No Microsoft Graph session found. Starting delegated sign-in.'
        Connect-MgGraph -Scopes $requiredScope -NoWelcome | Out-Null
        $script:StartedGraphConnection = $true
        $context = Get-MgContext
    }

    if ($requiredScope -notin $context.Scopes) {
        throw "Current Microsoft Graph session is missing delegated scope '$requiredScope'. Reconnect using: Connect-MgGraph -Scopes '$requiredScope'"
    }

    Write-AuditLog -Level INFO -Message "Using Microsoft Graph context for tenant '$($context.TenantId)' and account '$($context.Account)'."
}

function Get-RegistrationData {
    if ($InputCsvPath) {
        if (-not (Test-Path -LiteralPath $InputCsvPath -PathType Leaf)) {
            throw "Input CSV '$InputCsvPath' does not exist."
        }

        $rows = @(Import-Csv -LiteralPath $InputCsvPath)
        if ($rows.Count -eq 0) { return @() }

        $requiredColumns = @(
            'Id', 'UserPrincipalName', 'UserDisplayName', 'UserType', 'IsAdmin',
            'IsMfaRegistered', 'IsMfaCapable', 'IsSsprEnabled', 'IsSsprRegistered',
            'IsSsprCapable', 'IsPasswordlessCapable', 'MethodsRegistered', 'LastUpdatedDateTime'
        )
        $availableColumns = @($rows[0].PSObject.Properties.Name)
        $missing = @($requiredColumns | Where-Object { $_ -notin $availableColumns })
        if ($missing.Count -gt 0) {
            throw "Input CSV is missing required column(s): $($missing -join ', ')."
        }

        Write-AuditLog -Level INFO -Message "Loaded $($rows.Count) record(s) from offline CSV '$InputCsvPath'."
        return $rows
    }

    Assert-RequiredModule -Name 'Microsoft.Graph.Authentication'
    Assert-RequiredModule -Name 'Microsoft.Graph.Reports'
    Assert-GraphConnection
    $rows = @(Get-MgReportAuthenticationMethodUserRegistrationDetail -All)
    Write-AuditLog -Level INFO -Message "Retrieved $($rows.Count) registration record(s) from Microsoft Graph v1.0."
    return $rows
}

function Get-SeverityRank {
    param([Parameter(Mandatory)][string]$Severity)
    switch ($Severity) {
        'Critical' { 5 }
        'High'     { 4 }
        'Medium'   { 3 }
        'Low'      { 2 }
        'Healthy'  { 1 }
        default    { 0 }
    }
}

try {
    Write-AuditLog -Level INFO -Message 'Starting Entra ID MFA readiness audit in read-only mode.'
    $records = @(Get-RegistrationData)
    $now = [DateTimeOffset]::UtcNow

    $results = foreach ($record in $records) {
        $userType = [string]$record.UserType
        if (-not $IncludeGuests -and $userType -eq 'guest') { continue }

        $isAdmin = ConvertTo-StrictBoolean -Value $record.IsAdmin -FieldName 'IsAdmin'
        $isMfaRegistered = ConvertTo-StrictBoolean -Value $record.IsMfaRegistered -FieldName 'IsMfaRegistered'
        $isMfaCapable = ConvertTo-StrictBoolean -Value $record.IsMfaCapable -FieldName 'IsMfaCapable'
        $isSsprEnabled = ConvertTo-StrictBoolean -Value $record.IsSsprEnabled -FieldName 'IsSsprEnabled'
        $isSsprRegistered = ConvertTo-StrictBoolean -Value $record.IsSsprRegistered -FieldName 'IsSsprRegistered'
        $isSsprCapable = ConvertTo-StrictBoolean -Value $record.IsSsprCapable -FieldName 'IsSsprCapable'
        $isPasswordlessCapable = ConvertTo-StrictBoolean -Value $record.IsPasswordlessCapable -FieldName 'IsPasswordlessCapable'

        $findings = [System.Collections.Generic.List[object]]::new()
        if (-not $isMfaCapable) {
            if ($isAdmin) {
                $findings.Add([pscustomobject]@{ Severity='Critical'; Code='ADMIN_MFA_NOT_CAPABLE'; Detail='Privileged account is not MFA capable.' })
            }
            elseif ($isMfaRegistered) {
                $findings.Add([pscustomobject]@{ Severity='Medium'; Code='MFA_REGISTERED_NOT_CAPABLE'; Detail='MFA is registered but no currently allowed strong method is usable.' })
            }
            else {
                $findings.Add([pscustomobject]@{ Severity='High'; Code='USER_MFA_NOT_CAPABLE'; Detail='Member account is not MFA capable.' })
            }
        }

        if ($isSsprEnabled -and -not $isSsprCapable) {
            $findings.Add([pscustomobject]@{ Severity='Medium'; Code='SSPR_ENABLED_NOT_CAPABLE'; Detail='SSPR is enabled but the user is not SSPR capable.' })
        }

        if ($RequirePasswordless -and -not $isPasswordlessCapable) {
            $findings.Add([pscustomobject]@{ Severity='Low'; Code='PASSWORDLESS_NOT_CAPABLE'; Detail='Passwordless capability is required but not available.' })
        }

        $reportTimestamp = $null
        if ($record.LastUpdatedDateTime) {
            try { $reportTimestamp = [DateTimeOffset]$record.LastUpdatedDateTime }
            catch { throw "Invalid LastUpdatedDateTime for '$($record.UserPrincipalName)': '$($record.LastUpdatedDateTime)'." }
        }
        if (-not $reportTimestamp -or (($now - $reportTimestamp).TotalHours -gt $MaxReportAgeHours)) {
            $findings.Add([pscustomobject]@{ Severity='Medium'; Code='REPORT_DATA_STALE'; Detail="Registration report data is missing or older than $MaxReportAgeHours hours." })
        }

        if ($findings.Count -eq 0) {
            $severity = 'Healthy'
            $findingCodes = 'NONE'
            $findingDetails = 'No configured readiness gap detected.'
        }
        else {
            $severity = ($findings | Sort-Object { Get-SeverityRank $_.Severity } -Descending | Select-Object -First 1).Severity
            $findingCodes = ($findings.Code -join ';')
            $findingDetails = ($findings.Detail -join ' ')
        }

        if ($severity -eq 'Healthy' -and -not $IncludeHealthy) { continue }

        $methods = if ($record.MethodsRegistered -is [array]) {
            $record.MethodsRegistered -join ';'
        }
        else {
            [string]$record.MethodsRegistered
        }

        [pscustomobject]@{
            Severity                 = $severity
            FindingCodes             = $findingCodes
            UserPrincipalName        = [string]$record.UserPrincipalName
            UserDisplayName          = [string]$record.UserDisplayName
            UserId                   = [string]$record.Id
            UserType                 = $userType
            IsAdmin                  = $isAdmin
            IsMfaRegistered          = $isMfaRegistered
            IsMfaCapable             = $isMfaCapable
            IsSsprEnabled            = $isSsprEnabled
            IsSsprRegistered         = $isSsprRegistered
            IsSsprCapable            = $isSsprCapable
            IsPasswordlessCapable    = $isPasswordlessCapable
            MethodsRegistered        = $methods
            ReportLastUpdatedUtc      = if ($reportTimestamp) { $reportTimestamp.UtcDateTime.ToString('o') } else { $null }
            FindingDetails            = $findingDetails
        }
    }

    $results = @($results | Sort-Object @{Expression={ Get-SeverityRank $_.Severity };Descending=$true}, UserPrincipalName)
    $severityCounts = [ordered]@{}
    foreach ($name in @('Critical', 'High', 'Medium', 'Low', 'Healthy')) {
        $severityCounts[$name] = @($results | Where-Object Severity -eq $name).Count
    }

    if (-not $NoExport) {
        foreach ($path in @($OutputPath, $SummaryPath)) {
            $directory = Split-Path -Parent $path
            if ($directory -and -not (Test-Path -LiteralPath $directory)) {
                New-Item -ItemType Directory -Path $directory -Force | Out-Null
            }
        }

        $results | Export-Csv -LiteralPath $OutputPath -NoTypeInformation -Encoding utf8
        [ordered]@{
            GeneratedAtUtc    = $now.ToString('o')
            SourceRecordCount = $records.Count
            ExportedFindings  = $results.Count
            IncludeGuests     = [bool]$IncludeGuests
            IncludeHealthy    = [bool]$IncludeHealthy
            RequirePasswordless = [bool]$RequirePasswordless
            SeverityCounts    = $severityCounts
        } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $SummaryPath -Encoding utf8

        Write-AuditLog -Level INFO -Message "Exported $($results.Count) row(s) to '$OutputPath' and summary to '$SummaryPath'."
    }
    else {
        Write-AuditLog -Level INFO -Message "Audit completed with $($results.Count) returned row(s); export disabled."
    }

    $results
}
catch {
    Write-AuditLog -Level ERROR -Message $_.Exception.Message
    throw
}
finally {
    if ($DisconnectOnExit -and $script:StartedGraphConnection) {
        Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
    }
}

