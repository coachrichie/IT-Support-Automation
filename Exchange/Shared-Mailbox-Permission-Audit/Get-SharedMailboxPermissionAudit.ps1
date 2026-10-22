#requires -Version 7.2
<#
.SYNOPSIS
    Audits delegated permissions on Exchange Online shared mailboxes.

.DESCRIPTION
    Creates a read-only CSV report for FullAccess, SendAs, and SendOnBehalf
    assignments. No Exchange configuration is changed.
#>
[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$OutputDirectory = (Join-Path $PWD 'Reports'),

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$MailboxFilter = '*',

    [Parameter()]
    [switch]$IncludeInherited,

    [Parameter()]
    [switch]$SkipConnect,

    [Parameter()]
    [switch]$DisconnectOnExit,

    [Parameter()]
    [string]$Organization
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

function ConvertTo-PermissionAuditRecord {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$MailboxDisplayName,
        [Parameter(Mandatory)] [string]$PrimarySmtpAddress,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [object[]]$Entries
    )

    $filteredEntries = @($Entries | Where-Object {
        $trustee = [string]$_.Trustee
        -not [string]::IsNullOrWhiteSpace($trustee) -and
        $trustee -notmatch '(?i)(NT AUTHORITY\\SELF|S-1-5-10)$'
    })

    foreach ($group in ($filteredEntries | Group-Object -Property Trustee)) {
        $permissions = @($group.Group.Permission | ForEach-Object { [string]$_ } | Sort-Object -Unique)
        $hasFullAccess = $permissions -contains 'FullAccess'
        $hasSendAs = $permissions -contains 'SendAs'
        $hasSendOnBehalf = $permissions -contains 'SendOnBehalf'
        $hasDeny = @($group.Group | Where-Object { $_.Deny -eq $true }).Count -gt 0
        $hasInherited = @($group.Group | Where-Object { $_.IsInherited -eq $true }).Count -gt 0

        $status = if ($hasDeny) {
            'Review-Deny'
        }
        elseif ($hasFullAccess -and ($hasSendAs -or $hasSendOnBehalf)) {
            'Complete'
        }
        else {
            'Review'
        }

        [pscustomobject]@{
            MailboxDisplayName = $MailboxDisplayName
            PrimarySmtpAddress = $PrimarySmtpAddress
            Trustee           = $group.Name
            HasFullAccess     = $hasFullAccess
            HasSendAs         = $hasSendAs
            HasSendOnBehalf   = $hasSendOnBehalf
            ContainsDeny      = $hasDeny
            ContainsInherited = $hasInherited
            Status            = $status
            Permissions       = ($permissions -join ';')
        }
    }
}

function Invoke-SharedMailboxPermissionAudit {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$ReportDirectory,
        [Parameter(Mandatory)] [string]$NameFilter,
        [Parameter(Mandatory)] [bool]$IncludeInheritedEntries,
        [Parameter(Mandatory)] [bool]$ConnectSkipped,
        [Parameter(Mandatory)] [bool]$DisconnectAfterRun,
        [string]$ExchangeOrganization
    )

    if (-not (Test-Path -LiteralPath $ReportDirectory)) {
        New-Item -ItemType Directory -Path $ReportDirectory -Force | Out-Null
    }

    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $logPath = Join-Path $ReportDirectory "SharedMailboxPermissionAudit-$timestamp.log"
    $csvPath = Join-Path $ReportDirectory "SharedMailboxPermissionAudit-$timestamp.csv"
    $connectedByScript = $false

    try {
        if (-not $ConnectSkipped) {
            if (-not (Get-Module -ListAvailable -Name ExchangeOnlineManagement)) {
                throw 'Das Modul ExchangeOnlineManagement ist nicht installiert.'
            }

            Import-Module ExchangeOnlineManagement -ErrorAction Stop
            $connectParameters = @{ ShowBanner = $false; ErrorAction = 'Stop' }
            if (-not [string]::IsNullOrWhiteSpace($ExchangeOrganization)) {
                $connectParameters.Organization = $ExchangeOrganization
            }
            Connect-ExchangeOnline @connectParameters
            $connectedByScript = $true
        }

        foreach ($commandName in 'Get-EXOMailbox', 'Get-EXOMailboxPermission', 'Get-EXORecipientPermission') {
            if (-not (Get-Command -Name $commandName -ErrorAction SilentlyContinue)) {
                throw "Erforderliches Cmdlet ist nicht verfügbar: $commandName"
            }
        }

        Write-AuditLog -Path $logPath -Message 'Lese freigegebene Postfächer und Delegierungen.'
        $mailboxes = @(Get-EXOMailbox -RecipientTypeDetails SharedMailbox -ResultSize Unlimited -Properties GrantSendOnBehalfTo -ErrorAction Stop |
            Where-Object {
                ([string]$_.DisplayName -like $NameFilter) -or
                ([string]$_.PrimarySmtpAddress -like $NameFilter)
            })

        $results = [System.Collections.Generic.List[object]]::new()
        foreach ($mailbox in $mailboxes) {
            $smtpAddress = [string]$mailbox.PrimarySmtpAddress
            if ([string]::IsNullOrWhiteSpace($smtpAddress)) {
                Write-AuditLog -Path $logPath -Level WARN -Message "Überspringe Postfach ohne PrimarySmtpAddress: $($mailbox.DisplayName)"
                continue
            }

            try {
                $entries = [System.Collections.Generic.List[object]]::new()

                foreach ($permission in @(Get-EXOMailboxPermission -Identity $smtpAddress -ResultSize Unlimited -ErrorAction Stop)) {
                    if (($permission.AccessRights -contains 'FullAccess') -and
                        ($IncludeInheritedEntries -or -not [bool]$permission.IsInherited)) {
                        $entries.Add([pscustomobject]@{
                            Trustee = [string]$permission.User
                            Permission = 'FullAccess'
                            Deny = [bool]$permission.Deny
                            IsInherited = [bool]$permission.IsInherited
                        })
                    }
                }

                foreach ($permission in @(Get-EXORecipientPermission -Identity $smtpAddress -ResultSize Unlimited -ErrorAction Stop)) {
                    if ($permission.AccessRights -contains 'SendAs') {
                        $entries.Add([pscustomobject]@{
                            Trustee = [string]$permission.Trustee
                            Permission = 'SendAs'
                            Deny = $false
                            IsInherited = $false
                        })
                    }
                }

                foreach ($delegate in @($mailbox.GrantSendOnBehalfTo)) {
                    $entries.Add([pscustomobject]@{
                        Trustee = [string]$delegate
                        Permission = 'SendOnBehalf'
                        Deny = $false
                        IsInherited = $false
                    })
                }

                $records = @(ConvertTo-PermissionAuditRecord -MailboxDisplayName ([string]$mailbox.DisplayName) -PrimarySmtpAddress $smtpAddress -Entries $entries)
                if ($records.Count -eq 0) {
                    $records = @([pscustomobject]@{
                        MailboxDisplayName = [string]$mailbox.DisplayName
                        PrimarySmtpAddress = $smtpAddress
                        Trustee           = ''
                        HasFullAccess     = $false
                        HasSendAs         = $false
                        HasSendOnBehalf   = $false
                        ContainsDeny      = $false
                        ContainsInherited = $false
                        Status            = 'No-Delegates'
                        Permissions       = ''
                    })
                }
                foreach ($record in $records) { $results.Add($record) }
            }
            catch {
                Write-AuditLog -Path $logPath -Level ERROR -Message "Fehler bei '$smtpAddress': $($_.Exception.Message)"
                $results.Add([pscustomobject]@{
                    MailboxDisplayName = [string]$mailbox.DisplayName
                    PrimarySmtpAddress = $smtpAddress
                    Trustee           = ''
                    HasFullAccess     = $false
                    HasSendAs         = $false
                    HasSendOnBehalf   = $false
                    ContainsDeny      = $false
                    ContainsInherited = $false
                    Status            = 'Collection-Error'
                    Permissions       = ''
                })
            }
        }

        $results | Sort-Object PrimarySmtpAddress, Trustee | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding utf8
        Write-AuditLog -Path $logPath -Message ("Fertig: {0} Postfächer, {1} Reportzeilen, Ausgabe '{2}'." -f $mailboxes.Count, $results.Count, $csvPath)

        [pscustomobject]@{
            MailboxCount = $mailboxes.Count
            RecordCount  = $results.Count
            ReviewCount  = @($results | Where-Object Status -Like 'Review*').Count
            ErrorCount   = @($results | Where-Object Status -eq 'Collection-Error').Count
            CsvPath      = $csvPath
            LogPath      = $logPath
        }
    }
    finally {
        if ($DisconnectAfterRun -and $connectedByScript -and (Get-Command Disconnect-ExchangeOnline -ErrorAction SilentlyContinue)) {
            Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue
        }
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    Invoke-SharedMailboxPermissionAudit `
        -ReportDirectory $OutputDirectory `
        -NameFilter $MailboxFilter `
        -IncludeInheritedEntries $IncludeInherited.IsPresent `
        -ConnectSkipped $SkipConnect.IsPresent `
        -DisconnectAfterRun $DisconnectOnExit.IsPresent `
        -ExchangeOrganization $Organization
}
