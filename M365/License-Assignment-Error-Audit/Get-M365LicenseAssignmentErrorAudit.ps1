[CmdletBinding()]
param(
    [string]$OutputPath = (Join-Path -Path $PWD -ChildPath ("m365-license-errors-{0}.csv" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))),
    [switch]$IncludeSuccessfulAssignments,
    [switch]$NoExport
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Log {
    param(
        [Parameter(Mandatory)][ValidateSet('INFO','WARN','ERROR')][string]$Level,
        [Parameter(Mandatory)][string]$Message
    )
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Write-Host "[$ts][$Level] $Message"
}

function Assert-Module {
    param([Parameter(Mandatory)][string]$Name)
    if (-not (Get-Module -ListAvailable -Name $Name)) {
        throw "Required module '$Name' is not installed. Install it with: Install-Module $Name -Scope CurrentUser"
    }
}

Assert-Module -Name 'Microsoft.Graph.Authentication'
Assert-Module -Name 'Microsoft.Graph.Users'
Assert-Module -Name 'Microsoft.Graph.Identity.DirectoryManagement'
Assert-Module -Name 'Microsoft.Graph.Groups'

$requiredScopes = @('User.Read.All','Directory.Read.All','Organization.Read.All')

try {
    $ctx = Get-MgContext
    if (-not $ctx -or -not $ctx.Account) {
        Write-Log INFO 'Connecting to Microsoft Graph...'
        Connect-MgGraph -Scopes $requiredScopes -NoWelcome | Out-Null
    }

    Write-Log INFO 'Loading subscribed SKUs...'
    $skuMap = @{}
    foreach ($sku in Get-MgSubscribedSku -All) {
        $skuMap[$sku.SkuId.ToString()] = $sku.SkuPartNumber
    }

    Write-Log INFO 'Loading users and license assignment states...'
    $users = Get-MgUser -All -Property 'id,displayName,userPrincipalName,usageLocation,licenseAssignmentStates'

    $groupNameCache = @{}
    $rows = New-Object System.Collections.Generic.List[object]

    foreach ($user in $users) {
        foreach ($state in @($user.LicenseAssignmentStates)) {
            if (-not $state) { continue }

            $isError = $state.State -eq 'Error'
            if (-not $IncludeSuccessfulAssignments -and -not $isError) { continue }

            $skuId = $state.SkuId.ToString()
            $skuName = if ($skuMap.ContainsKey($skuId)) { $skuMap[$skuId] } else { $skuId }

            $assignmentType = 'Direct'
            $assignedByGroup = $null
            $assignedByGroupName = $null

            if ($state.AssignedByGroup) {
                $assignmentType = 'Group'
                $assignedByGroup = $state.AssignedByGroup

                if (-not $groupNameCache.ContainsKey($assignedByGroup)) {
                    try {
                        $grp = Get-MgGroup -GroupId $assignedByGroup -Property 'id,displayName'
                        $groupNameCache[$assignedByGroup] = $grp.DisplayName
                    }
                    catch {
                        Write-Log WARN "Could not resolve group $assignedByGroup: $($_.Exception.Message)"
                        $groupNameCache[$assignedByGroup] = $null
                    }
                }
                $assignedByGroupName = $groupNameCache[$assignedByGroup]
            }

            $rows.Add([pscustomobject]@{
                DisplayName          = $user.DisplayName
                UserPrincipalName    = $user.UserPrincipalName
                UserId               = $user.Id
                UsageLocation        = $user.UsageLocation
                MissingUsageLocation = [string]::IsNullOrWhiteSpace($user.UsageLocation)
                SkuId                = $skuId
                SkuPartNumber        = $skuName
                AssignmentType       = $assignmentType
                AssignedByGroupId    = $assignedByGroup
                AssignedByGroupName  = $assignedByGroupName
                State                = $state.State
                Error                = $state.Error
                ErrorSubcode         = $state.ErrorSubcode
                LastUpdatedDateTime  = $state.LastUpdatedDateTime
                DisabledPlans        = (@($state.DisabledPlans) -join ';')
            })
        }
    }

    $result = $rows | Sort-Object UserPrincipalName, SkuPartNumber, AssignmentType

    $errorCount = @($result | Where-Object State -eq 'Error').Count
    Write-Log INFO "Audit complete. Rows: $(@($result).Count); errors: $errorCount"

    if (-not $NoExport) {
        $result | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8
        Write-Log INFO "CSV exported to: $OutputPath"
    }

    $result
}
catch {
    Write-Log ERROR $_.Exception.Message
    throw
}
