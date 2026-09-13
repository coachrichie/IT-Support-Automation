#requires -Version 5.1

[CmdletBinding()]
param(
    [string[]]$Mailbox,

    [switch]$IncludeSharedMailboxes,

    [switch]$IncludeDisabledRules,

    [switch]$IncludeInternal,

    [string[]]$TrustedExternalDomain,

    [string]$OutputPath = (Join-Path -Path $PWD -ChildPath ("external-forwarding-audit-{0}.csv" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))),

    [switch]$NoExport,

    [switch]$ConnectExchangeOnline,

    [string]$UserPrincipalName
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Log {
    param(
        [Parameter(Mandatory)]
        [ValidateSet('INFO', 'WARN', 'ERROR')]
        [string]$Level,

        [Parameter(Mandatory)]
        [string]$Message
    )

    $timestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    Write-Host "[$timestamp][$Level] $Message"
}

function Assert-CommandAvailable {
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    if (-not (Get-Command -Name $Name -ErrorAction SilentlyContinue)) {
        throw "Required command '$Name' is not available. Connect to Exchange Online PowerShell or use -ConnectExchangeOnline."
    }
}

function Normalize-Domain {
    param([string]$Domain)

    if ([string]::IsNullOrWhiteSpace($Domain)) {
        return $null
    }

    return $Domain.Trim().TrimStart('@').ToLowerInvariant()
}

function ConvertTo-EmailAddress {
    param(
        [Parameter(Mandatory)]
        [object]$Value
    )

    $text = [string]$Value
    if ([string]::IsNullOrWhiteSpace($text)) {
        return $null
    }

    $match = [regex]::Match($text, '(?i)[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}')
    if ($match.Success) {
        return $match.Value.ToLowerInvariant()
    }

    return $null
}

function Resolve-ForwardingTarget {
    param(
        [Parameter(Mandatory)]
        [object]$Target
    )

    $directAddress = ConvertTo-EmailAddress -Value $Target
    if ($directAddress) {
        return [pscustomobject]@{
            Address    = $directAddress
            Resolution = 'Direct'
            RawTarget  = [string]$Target
        }
    }

    $rawTarget = [string]$Target
    if ([string]::IsNullOrWhiteSpace($rawTarget)) {
        return [pscustomobject]@{
            Address    = $null
            Resolution = 'Empty'
            RawTarget  = $rawTarget
        }
    }

    try {
        $recipient = Get-Recipient -Identity $rawTarget -ErrorAction Stop

        if ($recipient.ExternalEmailAddress) {
            $external = ConvertTo-EmailAddress -Value $recipient.ExternalEmailAddress
            if ($external) {
                return [pscustomobject]@{
                    Address    = $external
                    Resolution = 'RecipientExternalEmailAddress'
                    RawTarget  = $rawTarget
                }
            }
        }

        if ($recipient.PrimarySmtpAddress) {
            return [pscustomobject]@{
                Address    = ([string]$recipient.PrimarySmtpAddress).ToLowerInvariant()
                Resolution = 'RecipientPrimarySmtpAddress'
                RawTarget  = $rawTarget
            }
        }
    }
    catch {
        Write-Log -Level 'WARN' -Message "Could not resolve forwarding target '$rawTarget' with Get-Recipient: $($_.Exception.Message)"
    }

    return [pscustomobject]@{
        Address    = $null
        Resolution = 'Unresolved'
        RawTarget  = $rawTarget
    }
}

function Get-TargetClassification {
    param(
        [string]$Address,
        [string[]]$InternalDomains,
        [string[]]$TrustedDomains
    )

    if ([string]::IsNullOrWhiteSpace($Address) -or $Address -notmatch '@') {
        return [pscustomobject]@{
            Domain         = $null
            Classification = 'Unresolved'
            Risk           = 'Review'
        }
    }

    $domain = Normalize-Domain -Domain (($Address -split '@')[-1])

    if ($InternalDomains -contains $domain) {
        return [pscustomobject]@{
            Domain         = $domain
            Classification = 'Internal'
            Risk           = 'Low'
        }
    }

    if ($TrustedDomains -contains $domain) {
        return [pscustomobject]@{
            Domain         = $domain
            Classification = 'TrustedExternal'
            Risk           = 'Medium'
        }
    }

    return [pscustomobject]@{
        Domain         = $domain
        Classification = 'External'
        Risk           = 'High'
    }
}

function New-AuditFinding {
    param(
        [Parameter(Mandatory)]
        [object]$MailboxObject,

        [Parameter(Mandatory)]
        [string]$Mechanism,

        [object]$Target,

        [string]$RuleName,

        [Nullable[int]]$RulePriority,

        [Nullable[bool]]$RuleEnabled,

        [Nullable[bool]]$KeepCopy,

        [Parameter(Mandatory)]
        [string[]]$InternalDomains,

        [Parameter(Mandatory)]
        [string[]]$TrustedDomains,

        [string]$Status = 'Detected',

        [string]$ErrorMessage
    )

    if ($Status -eq 'AuditError') {
        return [pscustomobject]@{
            MailboxDisplayName        = [string]$MailboxObject.DisplayName
            MailboxPrimarySmtpAddress = [string]$MailboxObject.PrimarySmtpAddress
            RecipientTypeDetails      = [string]$MailboxObject.RecipientTypeDetails
            Mechanism                 = $Mechanism
            RuleName                  = $RuleName
            RulePriority              = $RulePriority
            RuleEnabled               = $RuleEnabled
            KeepCopy                  = $KeepCopy
            Target                    = $null
            TargetDomain              = $null
            Classification            = 'AuditError'
            Risk                      = 'Review'
            Resolution                = $null
            RawTarget                 = $null
            Status                    = $Status
            ErrorMessage              = $ErrorMessage
        }
    }

    $resolved = Resolve-ForwardingTarget -Target $Target
    $classification = Get-TargetClassification -Address $resolved.Address -InternalDomains $InternalDomains -TrustedDomains $TrustedDomains

    return [pscustomobject]@{
        MailboxDisplayName        = [string]$MailboxObject.DisplayName
        MailboxPrimarySmtpAddress = [string]$MailboxObject.PrimarySmtpAddress
        RecipientTypeDetails      = [string]$MailboxObject.RecipientTypeDetails
        Mechanism                 = $Mechanism
        RuleName                  = $RuleName
        RulePriority              = $RulePriority
        RuleEnabled               = $RuleEnabled
        KeepCopy                  = $KeepCopy
        Target                    = $resolved.Address
        TargetDomain              = $classification.Domain
        Classification            = $classification.Classification
        Risk                      = $classification.Risk
        Resolution                = $resolved.Resolution
        RawTarget                 = $resolved.RawTarget
        Status                    = $Status
        ErrorMessage              = $ErrorMessage
    }
}

$createdConnection = $false
$findings = [System.Collections.Generic.List[object]]::new()

try {
    if ($ConnectExchangeOnline) {
        if (-not (Get-Module -ListAvailable -Name ExchangeOnlineManagement)) {
            throw "ExchangeOnlineManagement is not installed. Install it with: Install-Module ExchangeOnlineManagement -Scope CurrentUser"
        }

        Import-Module ExchangeOnlineManagement -ErrorAction Stop

        $connectParams = @{ ShowBanner = $false }
        if ($UserPrincipalName) {
            $connectParams.UserPrincipalName = $UserPrincipalName
        }

        Write-Log -Level 'INFO' -Message 'Connecting to Exchange Online...'
        Connect-ExchangeOnline @connectParams
        $createdConnection = $true
    }

    @('Get-EXOMailbox', 'Get-InboxRule', 'Get-Recipient', 'Get-AcceptedDomain') | ForEach-Object {
        Assert-CommandAvailable -Name $_
    }

    $internalDomains = @(Get-AcceptedDomain | ForEach-Object {
        Normalize-Domain -Domain ([string]$_.DomainName)
    } | Where-Object { $_ } | Sort-Object -Unique)

    if ($internalDomains.Count -eq 0) {
        throw 'No accepted domains were returned. The audit cannot safely classify forwarding targets.'
    }

    $trustedDomains = @($TrustedExternalDomain | ForEach-Object {
        Normalize-Domain -Domain $_
    } | Where-Object { $_ } | Sort-Object -Unique)

    Write-Log -Level 'INFO' -Message ("Loaded {0} accepted domain(s) and {1} trusted external domain(s)." -f $internalDomains.Count, $trustedDomains.Count)

    if ($Mailbox -and $Mailbox.Count -gt 0) {
        $mailboxes = foreach ($identity in $Mailbox) {
            try {
                Get-EXOMailbox -Identity $identity -PropertySets @('Minimum', 'Delivery') -ErrorAction Stop
            }
            catch {
                Write-Log -Level 'ERROR' -Message "Mailbox '$identity' could not be read: $($_.Exception.Message)"
            }
        }
    }
    else {
        $mailboxes = Get-EXOMailbox -ResultSize Unlimited -PropertySets @('Minimum', 'Delivery')
    }

    if (-not $IncludeSharedMailboxes) {
        $mailboxes = @($mailboxes | Where-Object { $_.RecipientTypeDetails -eq 'UserMailbox' })
    }
    else {
        $mailboxes = @($mailboxes | Where-Object { $_.RecipientTypeDetails -in @('UserMailbox', 'SharedMailbox') })
    }

    Write-Log -Level 'INFO' -Message ("Auditing {0} mailbox(es)." -f $mailboxes.Count)

    foreach ($mailboxObject in $mailboxes) {
        $mailboxSmtp = [string]$mailboxObject.PrimarySmtpAddress
        Write-Log -Level 'INFO' -Message "Checking $mailboxSmtp"

        if ($mailboxObject.ForwardingSmtpAddress) {
            $finding = New-AuditFinding -MailboxObject $mailboxObject -Mechanism 'MailboxForwardingSmtpAddress' -Target $mailboxObject.ForwardingSmtpAddress -RuleEnabled $true -KeepCopy ([bool]$mailboxObject.DeliverToMailboxAndForward) -InternalDomains $internalDomains -TrustedDomains $trustedDomains
            if ($IncludeInternal -or $finding.Classification -ne 'Internal') {
                $findings.Add($finding)
            }
        }

        if ($mailboxObject.ForwardingAddress) {
            $finding = New-AuditFinding -MailboxObject $mailboxObject -Mechanism 'MailboxForwardingAddress' -Target $mailboxObject.ForwardingAddress -RuleEnabled $true -KeepCopy ([bool]$mailboxObject.DeliverToMailboxAndForward) -InternalDomains $internalDomains -TrustedDomains $trustedDomains
            if ($IncludeInternal -or $finding.Classification -ne 'Internal') {
                $findings.Add($finding)
            }
        }

        try {
            $rules = @(Get-InboxRule -Mailbox $mailboxSmtp -IncludeHidden -ErrorAction Stop)

            foreach ($rule in $rules) {
                if (-not $IncludeDisabledRules -and -not [bool]$rule.Enabled) {
                    continue
                }

                $actions = @(
                    @{ Property = 'ForwardTo'; Mechanism = 'InboxRuleForwardTo' },
                    @{ Property = 'RedirectTo'; Mechanism = 'InboxRuleRedirectTo' },
                    @{ Property = 'ForwardAsAttachmentTo'; Mechanism = 'InboxRuleForwardAsAttachmentTo' }
                )

                foreach ($action in $actions) {
                    $targets = @($rule.($action.Property))
                    foreach ($target in $targets) {
                        if ($null -eq $target -or [string]::IsNullOrWhiteSpace([string]$target)) {
                            continue
                        }

                        $finding = New-AuditFinding -MailboxObject $mailboxObject -Mechanism $action.Mechanism -Target $target -RuleName ([string]$rule.Name) -RulePriority ([int]$rule.Priority) -RuleEnabled ([bool]$rule.Enabled) -InternalDomains $internalDomains -TrustedDomains $trustedDomains
                        if ($IncludeInternal -or $finding.Classification -ne 'Internal') {
                            $findings.Add($finding)
                        }
                    }
                }
            }
        }
        catch {
            Write-Log -Level 'ERROR' -Message "Inbox rules for '$mailboxSmtp' could not be read: $($_.Exception.Message)"
            $findings.Add((New-AuditFinding -MailboxObject $mailboxObject -Mechanism 'InboxRuleAudit' -InternalDomains $internalDomains -TrustedDomains $trustedDomains -Status 'AuditError' -ErrorMessage $_.Exception.Message))
        }
    }

    $result = @($findings | Sort-Object MailboxPrimarySmtpAddress, Mechanism, RulePriority, Target)

    $externalCount = @($result | Where-Object { $_.Classification -eq 'External' }).Count
    $trustedCount = @($result | Where-Object { $_.Classification -eq 'TrustedExternal' }).Count
    $unresolvedCount = @($result | Where-Object { $_.Classification -in @('Unresolved', 'AuditError') }).Count

    Write-Log -Level 'INFO' -Message ("Audit complete. External: {0}; Trusted external: {1}; Review required: {2}." -f $externalCount, $trustedCount, $unresolvedCount)

    if (-not $NoExport) {
        $outputDirectory = Split-Path -Parent $OutputPath
        if ($outputDirectory -and -not (Test-Path -LiteralPath $outputDirectory)) {
            New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
        }

        $result | Export-Csv -LiteralPath $OutputPath -NoTypeInformation -Encoding UTF8
        Write-Log -Level 'INFO' -Message "CSV report written to: $OutputPath"
    }

    $result
}
finally {
    if ($createdConnection -and (Get-Command -Name Disconnect-ExchangeOnline -ErrorAction SilentlyContinue)) {
        Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue
    }
}
