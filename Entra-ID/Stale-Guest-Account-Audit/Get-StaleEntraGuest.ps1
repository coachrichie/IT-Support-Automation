[CmdletBinding()]
param(
    [ValidateRange(30, 730)]
    [int]$DaysInactive = 90,

    [ValidateRange(1, 365)]
    [int]$MinimumAccountAgeDays = 30,

    [string]$OutputPath = (Join-Path -Path $PWD -ChildPath ("stale-guests-{0}.csv" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))),

    [switch]$IncludeNeverSignedIn,

    [switch]$NoExport
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

function Assert-RequiredModule {
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    if (-not (Get-Module -ListAvailable -Name $Name)) {
        throw "Required module '$Name' is not installed. Install it with: Install-Module $Name -Scope CurrentUser"
    }

    Import-Module $Name -ErrorAction Stop
}

function Assert-GraphConnection {
    $requiredScopes = @('User.Read.All', 'AuditLog.Read.All')
    $context = Get-MgContext

    if (-not $context) {
        Write-Log -Level INFO -Message 'No Microsoft Graph session found. Starting interactive sign-in.'
        Connect-MgGraph -Scopes $requiredScopes -NoWelcome | Out-Null
        $context = Get-MgContext
    }

    $missingScopes = $requiredScopes | Where-Object { $_ -notin $context.Scopes }
    if ($missingScopes) {
        throw "Current Microsoft Graph session is missing required delegated scope(s): $($missingScopes -join ', '). Reconnect using: Connect-MgGraph -Scopes 'User.Read.All','AuditLog.Read.All'"
    }

    Write-Log -Level INFO -Message "Connected to tenant '$($context.TenantId)' as '$($context.Account)'."
}

try {
    Assert-RequiredModule -Name 'Microsoft.Graph.Authentication'
    Assert-RequiredModule -Name 'Microsoft.Graph.Users'
    Assert-GraphConnection

    $now = [DateTimeOffset]::UtcNow
    $inactiveCutoff = $now.AddDays(-$DaysInactive)
    $accountAgeCutoff = $now.AddDays(-$MinimumAccountAgeDays)

    Write-Log -Level INFO -Message "Auditing guest accounts inactive for at least $DaysInactive days and older than $MinimumAccountAgeDays days."

    $properties = @(
        'id',
        'displayName',
        'userPrincipalName',
        'mail',
        'userType',
        'accountEnabled',
        'createdDateTime',
        'externalUserState',
        'externalUserStateChangeDateTime',
        'signInActivity'
    )

    $getUserParams = @{
        All              = $true
        Filter           = "userType eq 'Guest'"
        Property         = $properties
        ConsistencyLevel = 'eventual'
    }

    $guests = @(Get-MgUser @getUserParams)

    Write-Log -Level INFO -Message "Retrieved $($guests.Count) guest account(s)."

    $results = foreach ($guest in $guests) {
        if (-not $guest.CreatedDateTime) {
            Write-Log -Level WARN -Message "Skipping '$($guest.UserPrincipalName)' because CreatedDateTime is unavailable."
            continue
        }

        $created = [DateTimeOffset]$guest.CreatedDateTime
        if ($created -gt $accountAgeCutoff) {
            continue
        }

        $lastSuccessful = $null
        if ($guest.SignInActivity -and $guest.SignInActivity.LastSuccessfulSignInDateTime) {
            $lastSuccessful = [DateTimeOffset]$guest.SignInActivity.LastSuccessfulSignInDateTime
        }

        $neverSignedIn = -not $lastSuccessful
        if ($neverSignedIn -and -not $IncludeNeverSignedIn) {
            continue
        }

        if ($lastSuccessful -and $lastSuccessful -gt $inactiveCutoff) {
            continue
        }

        $daysSinceSuccessfulSignIn = if ($lastSuccessful) {
            [math]::Floor(($now - $lastSuccessful).TotalDays)
        }
        else {
            $null
        }

        $accountAgeDays = [math]::Floor(($now - $created).TotalDays)

        [pscustomobject]@{
            Id                              = $guest.Id
            DisplayName                     = $guest.DisplayName
            UserPrincipalName               = $guest.UserPrincipalName
            Mail                            = $guest.Mail
            AccountEnabled                  = $guest.AccountEnabled
            ExternalUserState               = $guest.ExternalUserState
            ExternalUserStateChangeDateTime = $guest.ExternalUserStateChangeDateTime
            CreatedDateTimeUtc              = $created.UtcDateTime
            AccountAgeDays                  = $accountAgeDays
            LastSuccessfulSignInUtc         = if ($lastSuccessful) { $lastSuccessful.UtcDateTime } else { $null }
            DaysSinceSuccessfulSignIn       = $daysSinceSuccessfulSignIn
            NeverSignedIn                   = $neverSignedIn
            Classification                  = if ($neverSignedIn) { 'Never signed in' } else { "Inactive >= $DaysInactive days" }
        }
    }

    $sortProperties = @(
        @{ Expression = 'NeverSignedIn'; Descending = $true },
        @{ Expression = 'DaysSinceSuccessfulSignIn'; Descending = $true },
        @{ Expression = 'AccountAgeDays'; Descending = $true }
    )

    $results = @($results | Sort-Object -Property $sortProperties)

    if (-not $NoExport) {
        $outputDirectory = Split-Path -Parent $OutputPath
        if ($outputDirectory -and -not (Test-Path $outputDirectory)) {
            New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
        }

        $results | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8
        Write-Log -Level INFO -Message "Exported $($results.Count) result(s) to '$OutputPath'."
    }
    else {
        Write-Log -Level INFO -Message "Audit completed with $($results.Count) result(s); CSV export disabled."
    }

    $results
}
catch {
    Write-Log -Level ERROR -Message $_.Exception.Message
    throw
}
