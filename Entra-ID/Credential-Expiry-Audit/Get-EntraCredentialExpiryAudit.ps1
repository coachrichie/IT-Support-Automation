<#
.SYNOPSIS
    Reports Microsoft Entra application credentials that are expired or approaching expiry.

.DESCRIPTION
    Performs a read-only audit of password credentials (client secrets) and key credentials
    (certificates) on Microsoft Entra app registrations. Service principals can optionally
    be included. Findings are exported to CSV and operational messages are written to a log.

.PARAMETER WarningDays
    Include credentials expiring within this number of days. Default: 30.

.PARAMETER IncludeServicePrincipals
    Also audit enterprise applications/service principals.

.PARAMETER OutputPath
    Destination path for the CSV report.

.PARAMETER LogPath
    Destination path for the log file.

.EXAMPLE
    .\Get-EntraCredentialExpiryAudit.ps1

.EXAMPLE
    .\Get-EntraCredentialExpiryAudit.ps1 -WarningDays 60 -IncludeServicePrincipals
#>
[CmdletBinding()]
param(
    [ValidateRange(0, 3650)]
    [int]$WarningDays = 30,

    [switch]$IncludeServicePrincipals,

    [string]$OutputPath = (Join-Path -Path (Get-Location) -ChildPath ("Entra-Credential-Expiry-Audit-{0:yyyyMMdd-HHmmss}.csv" -f (Get-Date))),

    [string]$LogPath = (Join-Path -Path (Get-Location) -ChildPath ("Entra-Credential-Expiry-Audit-{0:yyyyMMdd-HHmmss}.log" -f (Get-Date)))
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-AuditLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [ValidateSet('INFO', 'WARNING', 'ERROR')]
        [string]$Level = 'INFO'
    )

    $entry = '{0:u} [{1}] {2}' -f (Get-Date), $Level, $Message
    Write-Host $entry
    Add-Content -LiteralPath $LogPath -Value $entry -Encoding UTF8
}

function Initialize-ParentDirectory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $parent = Split-Path -Path $Path -Parent
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        $null = New-Item -Path $parent -ItemType Directory -Force
    }
}

function ConvertTo-Thumbprint {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$CustomKeyIdentifier
    )

    if ($null -eq $CustomKeyIdentifier) {
        return $null
    }

    try {
        [byte[]]$bytes = if ($CustomKeyIdentifier -is [byte[]]) {
            $CustomKeyIdentifier
        }
        elseif ($CustomKeyIdentifier -is [string]) {
            [Convert]::FromBase64String($CustomKeyIdentifier)
        }
        else {
            [byte[]]$CustomKeyIdentifier
        }

        return ([BitConverter]::ToString($bytes)).Replace('-', '')
    }
    catch {
        return $null
    }
}

function Get-CredentialFinding {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$DirectoryObject,

        [Parameter(Mandatory)]
        [ValidateSet('Application', 'ServicePrincipal')]
        [string]$ObjectType,

        [Parameter(Mandatory)]
        [datetime]$NowUtc,

        [Parameter(Mandatory)]
        [datetime]$CutoffUtc
    )

    foreach ($credential in @($DirectoryObject.PasswordCredentials)) {
        if ($null -eq $credential.EndDateTime) {
            continue
        }

        $endUtc = ([datetime]$credential.EndDateTime).ToUniversalTime()
        if ($endUtc -gt $CutoffUtc) {
            continue
        }

        $daysRemaining = [math]::Floor(($endUtc - $NowUtc).TotalDays)
        $status = if ($endUtc -lt $NowUtc) {
            'Expired'
        }
        elseif ($daysRemaining -le 7) {
            'Critical'
        }
        else {
            'Warning'
        }

        [pscustomobject]@{
            ObjectType          = $ObjectType
            DisplayName         = $DirectoryObject.DisplayName
            AppId               = $DirectoryObject.AppId
            ObjectId            = $DirectoryObject.Id
            CredentialType      = 'ClientSecret'
            CredentialName      = $credential.DisplayName
            KeyId               = $credential.KeyId
            StartDateTimeUtc     = if ($credential.StartDateTime) { ([datetime]$credential.StartDateTime).ToUniversalTime().ToString('o') } else { $null }
            EndDateTimeUtc       = $endUtc.ToString('o')
            DaysRemaining        = $daysRemaining
            Status               = $status
            CertificateThumbprint = $null
            SecretHint           = $credential.Hint
        }
    }

    foreach ($credential in @($DirectoryObject.KeyCredentials)) {
        if ($null -eq $credential.EndDateTime) {
            continue
        }

        $endUtc = ([datetime]$credential.EndDateTime).ToUniversalTime()
        if ($endUtc -gt $CutoffUtc) {
            continue
        }

        $daysRemaining = [math]::Floor(($endUtc - $NowUtc).TotalDays)
        $status = if ($endUtc -lt $NowUtc) {
            'Expired'
        }
        elseif ($daysRemaining -le 7) {
            'Critical'
        }
        else {
            'Warning'
        }

        [pscustomobject]@{
            ObjectType          = $ObjectType
            DisplayName         = $DirectoryObject.DisplayName
            AppId               = $DirectoryObject.AppId
            ObjectId            = $DirectoryObject.Id
            CredentialType      = 'Certificate'
            CredentialName      = $credential.DisplayName
            KeyId               = $credential.KeyId
            StartDateTimeUtc     = if ($credential.StartDateTime) { ([datetime]$credential.StartDateTime).ToUniversalTime().ToString('o') } else { $null }
            EndDateTimeUtc       = $endUtc.ToString('o')
            DaysRemaining        = $daysRemaining
            Status               = $status
            CertificateThumbprint = ConvertTo-Thumbprint -CustomKeyIdentifier $credential.CustomKeyIdentifier
            SecretHint           = $null
        }
    }
}

try {
    Initialize-ParentDirectory -Path $OutputPath
    Initialize-ParentDirectory -Path $LogPath
    Write-AuditLog -Message "Starting Microsoft Entra credential expiry audit with a $WarningDays-day warning window."

    $requiredCommands = @('Connect-MgGraph', 'Get-MgContext', 'Get-MgApplication')
    if ($IncludeServicePrincipals) {
        $requiredCommands += 'Get-MgServicePrincipal'
    }

    foreach ($command in $requiredCommands) {
        if (-not (Get-Command -Name $command -ErrorAction SilentlyContinue)) {
            throw "Required Microsoft Graph PowerShell command '$command' was not found. Install the Microsoft.Graph.Applications module."
        }
    }

    $context = Get-MgContext
    $hasRequiredScope = $context -and ($context.Scopes -contains 'Application.Read.All')
    if (-not $hasRequiredScope) {
        Write-AuditLog -Message 'Connecting to Microsoft Graph with the read-only Application.Read.All scope.'
        Connect-MgGraph -Scopes 'Application.Read.All' -NoWelcome
    }

    $nowUtc = (Get-Date).ToUniversalTime()
    $cutoffUtc = $nowUtc.AddDays($WarningDays)
    $findings = [System.Collections.Generic.List[object]]::new()

    Write-AuditLog -Message 'Reading app registrations.'
    $applications = Get-MgApplication -All -Property 'id,appId,displayName,passwordCredentials,keyCredentials'
    foreach ($application in $applications) {
        foreach ($finding in Get-CredentialFinding -DirectoryObject $application -ObjectType Application -NowUtc $nowUtc -CutoffUtc $cutoffUtc) {
            $findings.Add($finding)
        }
    }

    if ($IncludeServicePrincipals) {
        Write-AuditLog -Message 'Reading service principals.'
        $servicePrincipals = Get-MgServicePrincipal -All -Property 'id,appId,displayName,passwordCredentials,keyCredentials'
        foreach ($servicePrincipal in $servicePrincipals) {
            foreach ($finding in Get-CredentialFinding -DirectoryObject $servicePrincipal -ObjectType ServicePrincipal -NowUtc $nowUtc -CutoffUtc $cutoffUtc) {
                $findings.Add($finding)
            }
        }
    }

    $orderedFindings = @($findings | Sort-Object EndDateTimeUtc, DisplayName, ObjectType)
    if ($orderedFindings.Count -gt 0) {
        $orderedFindings | Export-Csv -LiteralPath $OutputPath -NoTypeInformation -Encoding UTF8
        Write-AuditLog -Message "Exported $($orderedFindings.Count) finding(s) to '$OutputPath'."
    }
    else {
        $emptyReport = [pscustomobject]@{
            ObjectType = $null; DisplayName = $null; AppId = $null; ObjectId = $null
            CredentialType = $null; CredentialName = $null; KeyId = $null
            StartDateTimeUtc = $null; EndDateTimeUtc = $null; DaysRemaining = $null
            Status = $null; CertificateThumbprint = $null; SecretHint = $null
        }
        $emptyReport | Export-Csv -LiteralPath $OutputPath -NoTypeInformation -Encoding UTF8
        Write-AuditLog -Message "No expired or expiring credentials were found. An empty report was written to '$OutputPath'."
    }

    $orderedFindings
}
catch {
    $message = "Audit failed: $($_.Exception.Message)"
    try {
        Write-AuditLog -Message $message -Level ERROR
    }
    catch {
        Write-Error $message
    }
    throw
}
