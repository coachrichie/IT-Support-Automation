[CmdletBinding()]
param(
    [ValidateRange(1, 99)]
    [int]$WarningPercent = 75,

    [ValidateRange(2, 100)]
    [int]$CriticalPercent = 90,

    [ValidateSet('UserMailbox', 'SharedMailbox', 'RoomMailbox', 'EquipmentMailbox')]
    [string[]]$MailboxType = @('UserMailbox', 'SharedMailbox'),

    [string]$OutputPath = (Join-Path $PWD ("exchange-mailbox-quota-health-{0}.csv" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))),

    [string]$SummaryPath = (Join-Path $PWD ("exchange-mailbox-quota-health-summary-{0}.json" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))),

    [string]$LogPath = (Join-Path $PWD ("exchange-mailbox-quota-health-{0}.log" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))),

    [string]$InputCsvPath,

    [switch]$IncludeHealthy,

    [switch]$NoExport,

    [switch]$DisconnectOnExit
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:StartedExchangeConnection = $false

function Write-AuditLog {
    param(
        [Parameter(Mandatory)][ValidateSet('INFO', 'WARN', 'ERROR')][string]$Level,
        [Parameter(Mandatory)][string]$Message
    )

    $line = '[{0}][{1}] {2}' -f (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'), $Level, $Message
    $directory = Split-Path -Parent $LogPath
    if ($directory -and -not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
    Add-Content -LiteralPath $LogPath -Value $line -Encoding utf8
    Write-Verbose $line
}

function ConvertTo-ByteCount {
    param(
        [AllowNull()][object]$Value,
        [Parameter(Mandatory)][string]$FieldName
    )

    if ($null -eq $Value) { return $null }
    if ($Value -is [byte] -or $Value -is [int16] -or $Value -is [int32] -or $Value -is [int64] -or
        $Value -is [uint16] -or $Value -is [uint32] -or $Value -is [uint64]) {
        return [int64]$Value
    }

    $text = ([string]$Value).Trim()
    if ([string]::IsNullOrWhiteSpace($text) -or $text -eq 'Unlimited') { return $null }

    $directBytes = 0L
    if ([int64]::TryParse($text, [System.Globalization.NumberStyles]::Integer,
            [System.Globalization.CultureInfo]::InvariantCulture, [ref]$directBytes)) {
        return $directBytes
    }

    $toBytesMethod = $Value.PSObject.Methods['ToBytes']
    if ($toBytesMethod) {
        return [int64]$Value.ToBytes()
    }

    $valueProperty = $Value.PSObject.Properties['Value']
    if ($valueProperty -and $null -ne $valueProperty.Value -and -not [object]::ReferenceEquals($Value, $valueProperty.Value)) {
        return ConvertTo-ByteCount -Value $valueProperty.Value -FieldName $FieldName
    }

    if ($text -match '\(([\d\s,\.]+)\s*[Bb]ytes?\)') {
        $digits = $matches[1] -replace '[^0-9]', ''
        $parsedBytes = 0L
        if ([int64]::TryParse($digits, [ref]$parsedBytes)) { return $parsedBytes }
    }

    if ($text -match '^\s*([\d.,]+)\s*(B|KB|MB|GB|TB)') {
        $numberText = $matches[1]
        $unit = $matches[2].ToUpperInvariant()
        $number = 0.0
        $styles = [System.Globalization.NumberStyles]::Float -bor [System.Globalization.NumberStyles]::AllowThousands
        $parsed = [double]::TryParse($numberText, $styles, [System.Globalization.CultureInfo]::CurrentCulture, [ref]$number)
        if (-not $parsed) {
            $parsed = [double]::TryParse($numberText, $styles, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$number)
        }
        if ($parsed) {
            $multiplier = switch ($unit) {
                'B'  { 1 }
                'KB' { 1KB }
                'MB' { 1MB }
                'GB' { 1GB }
                'TB' { 1TB }
            }
            return [int64][math]::Round($number * $multiplier)
        }
    }

    throw "Field '$FieldName' contains unsupported size value '$text'."
}

function Assert-ExchangeModuleAndConnection {
    if (-not (Get-Module -ListAvailable -Name 'ExchangeOnlineManagement')) {
        throw "Required module 'ExchangeOnlineManagement' is not installed. Install it with: Install-Module ExchangeOnlineManagement -Scope CurrentUser"
    }
    Import-Module ExchangeOnlineManagement -ErrorAction Stop

    $hasConnection = $false
    if (Get-Command Get-ConnectionInformation -ErrorAction SilentlyContinue) {
        $hasConnection = @(
            Get-ConnectionInformation -ErrorAction SilentlyContinue |
                Where-Object { $_.State -eq 'Connected' }
        ).Count -gt 0
    }

    if (-not $hasConnection) {
        Write-AuditLog -Level INFO -Message 'No active Exchange Online session detected. Starting interactive sign-in.'
        Connect-ExchangeOnline -ShowBanner:$false
        $script:StartedExchangeConnection = $true
    }
}

function Get-OfflineMailboxData {
    if (-not (Test-Path -LiteralPath $InputCsvPath -PathType Leaf)) {
        throw "Input CSV '$InputCsvPath' does not exist."
    }
    $rows = @(Import-Csv -LiteralPath $InputCsvPath)
    if ($rows.Count -eq 0) { return @() }

    $requiredColumns = @(
        'Identity', 'DisplayName', 'PrimarySmtpAddress', 'RecipientTypeDetails',
        'TotalItemSizeBytes', 'ItemCount', 'IssueWarningQuotaBytes',
        'ProhibitSendQuotaBytes', 'ProhibitSendReceiveQuotaBytes'
    )
    $availableColumns = @($rows[0].PSObject.Properties.Name)
    $missing = @($requiredColumns | Where-Object { $_ -notin $availableColumns })
    if ($missing.Count -gt 0) {
        throw "Input CSV is missing required column(s): $($missing -join ', ')."
    }

    Write-AuditLog -Level INFO -Message "Loaded $($rows.Count) mailbox record(s) from offline CSV '$InputCsvPath'."
    return $rows
}

function Get-LiveMailboxData {
    Assert-ExchangeModuleAndConnection
    $mailboxes = @(
        Get-EXOMailbox -ResultSize Unlimited -RecipientTypeDetails $MailboxType -PropertySets Quota -Properties ExchangeGuid,DisplayName,PrimarySmtpAddress
    )
    Write-AuditLog -Level INFO -Message "Retrieved $($mailboxes.Count) mailbox object(s) from Exchange Online."

    foreach ($mailbox in $mailboxes) {
        try {
            $statistics = Get-EXOMailboxStatistics -ExchangeGuid $mailbox.ExchangeGuid -Properties TotalItemSize,ItemCount -ErrorAction Stop
            [pscustomobject]@{
                Identity                      = [string]$mailbox.Identity
                DisplayName                   = [string]$mailbox.DisplayName
                PrimarySmtpAddress            = [string]$mailbox.PrimarySmtpAddress
                RecipientTypeDetails          = [string]$mailbox.RecipientTypeDetails
                TotalItemSizeBytes            = ConvertTo-ByteCount -Value $statistics.TotalItemSize -FieldName 'TotalItemSize'
                ItemCount                     = [int64]$statistics.ItemCount
                IssueWarningQuotaBytes        = ConvertTo-ByteCount -Value $mailbox.IssueWarningQuota -FieldName 'IssueWarningQuota'
                ProhibitSendQuotaBytes        = ConvertTo-ByteCount -Value $mailbox.ProhibitSendQuota -FieldName 'ProhibitSendQuota'
                ProhibitSendReceiveQuotaBytes = ConvertTo-ByteCount -Value $mailbox.ProhibitSendReceiveQuota -FieldName 'ProhibitSendReceiveQuota'
                DataError                     = $null
            }
        }
        catch {
            Write-AuditLog -Level WARN -Message "Could not retrieve statistics for '$($mailbox.PrimarySmtpAddress)': $($_.Exception.Message)"
            [pscustomobject]@{
                Identity                      = [string]$mailbox.Identity
                DisplayName                   = [string]$mailbox.DisplayName
                PrimarySmtpAddress            = [string]$mailbox.PrimarySmtpAddress
                RecipientTypeDetails          = [string]$mailbox.RecipientTypeDetails
                TotalItemSizeBytes            = $null
                ItemCount                     = $null
                IssueWarningQuotaBytes        = $null
                ProhibitSendQuotaBytes        = $null
                ProhibitSendReceiveQuotaBytes = $null
                DataError                     = $_.Exception.Message
            }
        }
    }
}

function Get-SeverityRank {
    param([Parameter(Mandatory)][string]$Severity)
    switch ($Severity) {
        'Critical' { 5 }
        'Error'    { 4 }
        'Warning'  { 3 }
        'Review'   { 2 }
        'Healthy'  { 1 }
        default    { 0 }
    }
}

try {
    if ($WarningPercent -ge $CriticalPercent) {
        throw 'WarningPercent must be lower than CriticalPercent.'
    }

    Write-AuditLog -Level INFO -Message 'Starting Exchange Online mailbox quota health audit in read-only mode.'
    $sourceRows = if ($InputCsvPath) { @(Get-OfflineMailboxData) } else { @(Get-LiveMailboxData) }

    $results = foreach ($row in $sourceRows) {
        $dataError = if ($row.PSObject.Properties['DataError']) { [string]$row.DataError } else { $null }
        $usedBytes = ConvertTo-ByteCount -Value $row.TotalItemSizeBytes -FieldName 'TotalItemSizeBytes'
        $warningBytes = ConvertTo-ByteCount -Value $row.IssueWarningQuotaBytes -FieldName 'IssueWarningQuotaBytes'
        $sendBytes = ConvertTo-ByteCount -Value $row.ProhibitSendQuotaBytes -FieldName 'ProhibitSendQuotaBytes'
        $sendReceiveBytes = ConvertTo-ByteCount -Value $row.ProhibitSendReceiveQuotaBytes -FieldName 'ProhibitSendReceiveQuotaBytes'

        $effectiveLimit = if ($sendReceiveBytes) { $sendReceiveBytes } else { $sendBytes }
        $usedPercent = if ($usedBytes -ne $null -and $effectiveLimit -and $effectiveLimit -gt 0) {
            [math]::Round(($usedBytes / $effectiveLimit) * 100, 2)
        }
        else { $null }

        if ($dataError) {
            $severity = 'Error'
            $findingCode = 'STATISTICS_UNAVAILABLE'
            $findingDetails = "Mailbox statistics could not be retrieved: $dataError"
        }
        elseif ($usedBytes -ne $null -and $sendReceiveBytes -and $usedBytes -ge $sendReceiveBytes) {
            $severity = 'Critical'
            $findingCode = 'MAILBOX_SEND_RECEIVE_BLOCKED'
            $findingDetails = 'Mailbox has reached or exceeded the prohibit-send-receive quota.'
        }
        elseif ($usedBytes -ne $null -and $sendBytes -and $usedBytes -ge $sendBytes) {
            $severity = 'Critical'
            $findingCode = 'MAILBOX_SEND_BLOCKED'
            $findingDetails = 'Mailbox has reached or exceeded the prohibit-send quota.'
        }
        elseif ($usedPercent -ne $null -and $usedPercent -ge $CriticalPercent) {
            $severity = 'Critical'
            $findingCode = 'CRITICAL_CAPACITY'
            $findingDetails = "Mailbox uses at least $CriticalPercent percent of its effective limit."
        }
        elseif (($usedBytes -ne $null -and $warningBytes -and $usedBytes -ge $warningBytes) -or
                ($usedPercent -ne $null -and $usedPercent -ge $WarningPercent)) {
            $severity = 'Warning'
            $findingCode = 'WARNING_CAPACITY'
            $findingDetails = "Mailbox has reached its warning quota or at least $WarningPercent percent of its effective limit."
        }
        elseif (-not $effectiveLimit) {
            $severity = 'Review'
            $findingCode = 'QUOTA_UNAVAILABLE_OR_UNLIMITED'
            $findingDetails = 'No finite effective quota could be determined; review mailbox and license configuration.'
        }
        else {
            $severity = 'Healthy'
            $findingCode = 'NONE'
            $findingDetails = 'No configured quota threshold was reached.'
        }

        if ($severity -eq 'Healthy' -and -not $IncludeHealthy) { continue }

        [pscustomobject]@{
            Severity                      = $severity
            FindingCode                   = $findingCode
            Identity                      = [string]$row.Identity
            DisplayName                   = [string]$row.DisplayName
            PrimarySmtpAddress             = [string]$row.PrimarySmtpAddress
            RecipientTypeDetails           = [string]$row.RecipientTypeDetails
            TotalItemSizeGB                = if ($usedBytes -ne $null) { [math]::Round($usedBytes / 1GB, 2) } else { $null }
            ItemCount                      = if ($row.ItemCount -ne '') { [int64]$row.ItemCount } else { $null }
            UsedPercentOfEffectiveLimit    = $usedPercent
            IssueWarningQuotaGB            = if ($warningBytes) { [math]::Round($warningBytes / 1GB, 2) } else { $null }
            ProhibitSendQuotaGB            = if ($sendBytes) { [math]::Round($sendBytes / 1GB, 2) } else { $null }
            ProhibitSendReceiveQuotaGB     = if ($sendReceiveBytes) { [math]::Round($sendReceiveBytes / 1GB, 2) } else { $null }
            FindingDetails                 = $findingDetails
        }
    }

    $sortProperties = @(
        @{ Expression = { Get-SeverityRank $_.Severity }; Descending = $true },
        @{ Expression = 'UsedPercentOfEffectiveLimit'; Descending = $true },
        @{ Expression = 'PrimarySmtpAddress'; Descending = $false }
    )
    $results = @($results | Sort-Object -Property $sortProperties)
    $counts = [ordered]@{}
    foreach ($name in @('Critical', 'Error', 'Warning', 'Review', 'Healthy')) {
        $counts[$name] = @($results | Where-Object Severity -eq $name).Count
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
            GeneratedAtUtc    = [DateTimeOffset]::UtcNow.ToString('o')
            SourceRecordCount = $sourceRows.Count
            ExportedFindings  = $results.Count
            WarningPercent    = $WarningPercent
            CriticalPercent   = $CriticalPercent
            MailboxTypes      = $MailboxType
            SeverityCounts    = $counts
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
    if ($DisconnectOnExit -and $script:StartedExchangeConnection) {
        Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue
    }
}
