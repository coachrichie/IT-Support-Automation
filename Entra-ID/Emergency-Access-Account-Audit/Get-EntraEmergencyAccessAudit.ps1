[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string[]]$EmergencyAccessUserId,

    [string[]]$EmergencyAccessGroupId = @(),

    [ValidateRange(1, 365)]
    [int]$ValidationIntervalDays = 90,

    [string]$OutputPath = (Join-Path $PWD ("entra-emergency-access-{0}.csv" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))),

    [string]$SummaryPath = (Join-Path $PWD ("entra-emergency-access-summary-{0}.json" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))),

    [string]$LogPath = (Join-Path $PWD ("entra-emergency-access-{0}.log" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))),

    [string]$OfflineInputPath,

    [switch]$IncludeHealthy,

    [switch]$NoExport,

    [switch]$DisconnectOnExit
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:StartedGraphConnection = $false

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

function Assert-GuidList {
    param([Parameter(Mandatory)][string[]]$Value, [Parameter(Mandatory)][string]$Name)

    $duplicates = @($Value | Group-Object | Where-Object Count -gt 1)
    if ($duplicates.Count -gt 0) {
        throw "$Name contains duplicate object ID(s): $($duplicates.Name -join ', ')."
    }
    foreach ($item in $Value) {
        $parsed = [Guid]::Empty
        if (-not [Guid]::TryParse($item, [ref]$parsed)) {
            throw "$Name contains invalid GUID '$item'. Use Microsoft Entra object IDs, not UPNs."
        }
    }
}

function Assert-RequiredModule {
    if (-not (Get-Module -ListAvailable -Name 'Microsoft.Graph.Authentication')) {
        throw "Required module 'Microsoft.Graph.Authentication' is not installed. Install it with: Install-Module Microsoft.Graph.Authentication -Scope CurrentUser"
    }
    Import-Module Microsoft.Graph.Authentication -ErrorAction Stop
}

function Assert-GraphConnection {
    $requiredScopes = @('AuditLog.Read.All', 'Policy.Read.All', 'RoleManagement.Read.Directory', 'User.Read.All')
    $context = Get-MgContext
    if (-not $context) {
        Write-AuditLog -Level INFO -Message 'No Microsoft Graph session found. Starting delegated sign-in.'
        Connect-MgGraph -Scopes $requiredScopes -NoWelcome | Out-Null
        $script:StartedGraphConnection = $true
        $context = Get-MgContext
    }

    $missingScopes = @($requiredScopes | Where-Object { $_ -notin $context.Scopes })
    if ($missingScopes.Count -gt 0) {
        throw "Current Microsoft Graph session is missing scope(s): $($missingScopes -join ', '). Reconnect with the scopes documented in README.md."
    }
    Write-AuditLog -Level INFO -Message "Using Microsoft Graph context for tenant '$($context.TenantId)' and account '$($context.Account)'."
}

function Invoke-GraphCollection {
    param([Parameter(Mandatory)][string]$Uri)

    $items = [System.Collections.Generic.List[object]]::new()
    $nextLink = $Uri
    while ($nextLink) {
        $response = Invoke-MgGraphRequest -Method GET -Uri $nextLink -OutputType PSObject
        foreach ($item in @($response.value)) { $items.Add($item) }
        $nextLinkProperty = $response.PSObject.Properties['@odata.nextLink']
        $nextLink = if ($nextLinkProperty) { [string]$nextLinkProperty.Value } else { $null }
    }
    return @($items)
}

function Get-LiveAuditData {
    Assert-RequiredModule
    Assert-GraphConnection

    $encodedSelect = [Uri]::EscapeDataString('id,displayName,userPrincipalName,accountEnabled,onPremisesSyncEnabled,userType,signInActivity')
    $users = foreach ($userId in $EmergencyAccessUserId) {
        Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/users/$userId`?`$select=$encodedSelect" -OutputType PSObject
    }

    [pscustomobject]@{
        Users = @($users)
        RoleDefinitions = @(Invoke-GraphCollection -Uri 'https://graph.microsoft.com/v1.0/roleManagement/directory/roleDefinitions?$select=id,displayName,isBuiltIn')
        RoleAssignments = @(Invoke-GraphCollection -Uri 'https://graph.microsoft.com/v1.0/roleManagement/directory/roleAssignments?$select=id,principalId,roleDefinitionId,directoryScopeId')
        ConditionalAccessPolicies = @(Invoke-GraphCollection -Uri 'https://graph.microsoft.com/v1.0/identity/conditionalAccess/policies?$select=id,displayName,state,conditions,grantControls')
    }
}

function Get-OfflineAuditData {
    if (-not (Test-Path -LiteralPath $OfflineInputPath -PathType Leaf)) {
        throw "Offline input '$OfflineInputPath' does not exist."
    }
    $data = Get-Content -Raw -LiteralPath $OfflineInputPath | ConvertFrom-Json
    foreach ($property in @('Users', 'RoleDefinitions', 'RoleAssignments', 'ConditionalAccessPolicies')) {
        if ($property -notin @($data.PSObject.Properties.Name)) {
            throw "Offline input is missing required property '$property'."
        }
    }
    Write-AuditLog -Level INFO -Message "Loaded anonymized offline input '$OfflineInputPath'."
    return $data
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

function Test-CollectionContainsAny {
    param([object[]]$Collection, [string[]]$Candidate)
    foreach ($value in @($Collection)) {
        if ([string]$value -in $Candidate) { return $true }
    }
    return $false
}

try {
    Write-AuditLog -Level INFO -Message 'Starting Entra ID emergency access account audit in read-only mode.'
    Assert-GuidList -Value $EmergencyAccessUserId -Name 'EmergencyAccessUserId'
    if ($EmergencyAccessGroupId.Count -gt 0) {
        Assert-GuidList -Value $EmergencyAccessGroupId -Name 'EmergencyAccessGroupId'
    }

    $data = if ($OfflineInputPath) { Get-OfflineAuditData } else { Get-LiveAuditData }
    $usersById = @{}
    foreach ($user in @($data.Users)) { $usersById[[string]$user.id] = $user }

    $roleNamesById = @{}
    foreach ($definition in @($data.RoleDefinitions)) { $roleNamesById[[string]$definition.id] = [string]$definition.displayName }

    $globalAdminRoleIds = @($data.RoleDefinitions | Where-Object displayName -eq 'Global Administrator' | ForEach-Object { [string]$_.id })
    if ($globalAdminRoleIds.Count -eq 0) {
        throw "Role definition 'Global Administrator' was not returned. Verify RoleManagement.Read.Directory access."
    }

    $now = [DateTimeOffset]::UtcNow
    $results = foreach ($userId in $EmergencyAccessUserId) {
        if (-not $usersById.ContainsKey($userId)) {
            throw "Emergency access user '$userId' was not returned by Microsoft Graph or the offline input."
        }

        $user = $usersById[$userId]
        $findings = [System.Collections.Generic.List[object]]::new()
        $roleAssignments = @($data.RoleAssignments | Where-Object { [string]$_.principalId -eq $userId })
        $roleNames = @($roleAssignments | ForEach-Object { $roleNamesById[[string]$_.roleDefinitionId] } | Where-Object { $_ } | Sort-Object -Unique)
        $hasGlobalAdmin = @($roleAssignments | Where-Object { [string]$_.roleDefinitionId -in $globalAdminRoleIds }).Count -gt 0

        if (-not [bool]$user.accountEnabled) {
            $findings.Add([pscustomobject]@{ Severity='Critical'; Code='ACCOUNT_DISABLED'; Detail='Emergency access account is disabled.' })
        }
        if (-not $hasGlobalAdmin) {
            $findings.Add([pscustomobject]@{ Severity='Critical'; Code='GLOBAL_ADMIN_NOT_ACTIVE'; Detail='No active direct Global Administrator assignment was found.' })
        }
        if ([bool]$user.onPremisesSyncEnabled -or -not ([string]$user.userPrincipalName).EndsWith('.onmicrosoft.com', [StringComparison]::OrdinalIgnoreCase)) {
            $findings.Add([pscustomobject]@{ Severity='High'; Code='NOT_CLOUD_ONLY'; Detail='Account is synchronized or does not use an onmicrosoft.com UPN.' })
        }

        $blockingPolicies = [System.Collections.Generic.List[string]]::new()
        $reportOnlyPolicies = [System.Collections.Generic.List[string]]::new()
        foreach ($policy in @($data.ConditionalAccessPolicies)) {
            $state = [string]$policy.state
            if ($state -eq 'disabled') { continue }

            $usersCondition = $policy.conditions.users
            if (-not $usersCondition) { continue }
            $included = ('All' -in @($usersCondition.includeUsers)) -or
                ($userId -in @($usersCondition.includeUsers)) -or
                (Test-CollectionContainsAny -Collection @($usersCondition.includeGroups) -Candidate $EmergencyAccessGroupId)
            if (-not $included) { continue }

            $excluded = ($userId -in @($usersCondition.excludeUsers)) -or
                (Test-CollectionContainsAny -Collection @($usersCondition.excludeGroups) -Candidate $EmergencyAccessGroupId)
            if ($excluded) { continue }

            if ($state -eq 'enabledForReportingButNotEnforced') {
                $reportOnlyPolicies.Add([string]$policy.displayName)
            }
            elseif ($state -eq 'enabled') {
                $blockingPolicies.Add([string]$policy.displayName)
            }
        }
        if ($blockingPolicies.Count -gt 0) {
            $findings.Add([pscustomobject]@{ Severity='Critical'; Code='CA_POLICY_NOT_EXCLUDED'; Detail="Targeted by enabled Conditional Access policy/policies: $($blockingPolicies -join ', ')." })
        }

        $lastSuccessful = $null
        if ($user.signInActivity -and $user.signInActivity.lastSuccessfulSignInDateTime) {
            try { $lastSuccessful = [DateTimeOffset]$user.signInActivity.lastSuccessfulSignInDateTime }
            catch { throw "Invalid lastSuccessfulSignInDateTime for '$userId'." }
        }
        $daysSinceValidation = if ($lastSuccessful) { [math]::Floor(($now - $lastSuccessful).TotalDays) } else { $null }
        if (-not $lastSuccessful -or $daysSinceValidation -gt $ValidationIntervalDays) {
            $findings.Add([pscustomobject]@{ Severity='Medium'; Code='VALIDATION_OVERDUE'; Detail="No successful sign-in was found within $ValidationIntervalDays days; verify the documented test record." })
        }

        if ($findings.Count -eq 0) {
            $severity = 'Healthy'
            $findingCodes = 'NONE'
            $findingDetails = 'No configured emergency access gap detected.'
        }
        else {
            $severity = ($findings | Sort-Object { Get-SeverityRank $_.Severity } -Descending | Select-Object -First 1).Severity
            $findingCodes = $findings.Code -join ';'
            $findingDetails = $findings.Detail -join ' '
        }
        if ($severity -eq 'Healthy' -and -not $IncludeHealthy) { continue }

        [pscustomobject]@{
            Severity = $severity
            FindingCodes = $findingCodes
            UserPrincipalName = [string]$user.userPrincipalName
            DisplayName = [string]$user.displayName
            UserId = $userId
            AccountEnabled = [bool]$user.accountEnabled
            OnPremisesSyncEnabled = [bool]$user.onPremisesSyncEnabled
            HasActiveDirectGlobalAdministrator = $hasGlobalAdmin
            ActiveDirectRoles = $roleNames -join ';'
            LastSuccessfulSignInUtc = if ($lastSuccessful) { $lastSuccessful.UtcDateTime.ToString('o') } else { $null }
            DaysSinceSuccessfulSignIn = $daysSinceValidation
            EnabledCaPoliciesWithoutKnownExclusion = $blockingPolicies -join ';'
            ReportOnlyCaPoliciesWithoutKnownExclusion = $reportOnlyPolicies -join ';'
            FindingDetails = $findingDetails
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
            GeneratedAtUtc = $now.ToString('o')
            ConfiguredAccountCount = $EmergencyAccessUserId.Count
            MeetsMinimumTwoAccountRecommendation = ($EmergencyAccessUserId.Count -ge 2)
            ExportedRows = $results.Count
            ValidationIntervalDays = $ValidationIntervalDays
            KnownEmergencyAccessGroupIds = $EmergencyAccessGroupId.Count
            SeverityCounts = $severityCounts
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
