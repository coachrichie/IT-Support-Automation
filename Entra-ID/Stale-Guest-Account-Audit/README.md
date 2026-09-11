# Stale Guest Account Audit

Identifies inactive Microsoft Entra ID guest accounts with Microsoft Graph PowerShell and exports a reviewable CSV report. The script is intentionally read-only: it does not disable or delete users.

## Why this is useful

External guest accounts accumulate over time through projects, vendors, support partners, shared Teams, and ad-hoc collaboration. Stale guests increase identity sprawl and can preserve access long after a business relationship has ended.

Microsoft recommends using sign-in activity to identify inactive accounts and notes that many organizations use inactivity windows in the 90–180 day range. For reliable inactivity reporting, `lastSuccessfulSignInDateTime` is preferable to the last sign-in attempt because failed attempts do not prove that an account was successfully used.

## What the script does

- queries Microsoft Entra ID guest users through Microsoft Graph
- retrieves `signInActivity`, including `lastSuccessfulSignInDateTime`
- ignores newly created guest accounts based on a configurable minimum account age
- flags guests whose last successful sign-in is older than the configured inactivity threshold
- optionally includes guests that have never successfully signed in
- exports a UTF-8 CSV report
- performs no remediation or destructive change

## Requirements

### PowerShell modules

```powershell
Install-Module Microsoft.Graph.Authentication -Scope CurrentUser
Install-Module Microsoft.Graph.Users -Scope CurrentUser
```

### Microsoft Graph delegated permissions

- `User.Read.All`
- `AuditLog.Read.All`

Microsoft documents that access to `signInActivity` requires Microsoft Entra ID P1 or P2 and `AuditLog.Read.All`. The least-privileged Entra role documented for activity-log access is Reports Reader.

## Usage

### Standard 90-day audit

```powershell
./Get-StaleEntraGuest.ps1
```

### Include guests that have never successfully signed in

```powershell
./Get-StaleEntraGuest.ps1 -DaysInactive 90 -IncludeNeverSignedIn
```

### Use a 180-day inactivity threshold

```powershell
./Get-StaleEntraGuest.ps1 -DaysInactive 180
```

### Return objects only, without CSV export

```powershell
$staleGuests = ./Get-StaleEntraGuest.ps1 -DaysInactive 120 -NoExport
$staleGuests | Format-Table DisplayName, UserPrincipalName, DaysSinceSuccessfulSignIn, NeverSignedIn
```

### Custom output path

```powershell
./Get-StaleEntraGuest.ps1 -OutputPath 'C:\Reports\stale-guests.csv'
```

## Parameters

| Parameter | Default | Purpose |
|---|---:|---|
| `DaysInactive` | 90 | Minimum number of days since the last successful sign-in. |
| `MinimumAccountAgeDays` | 30 | Prevents newly invited guests from being classified as stale too early. |
| `OutputPath` | Timestamped CSV in current directory | Destination for the CSV report. |
| `IncludeNeverSignedIn` | Off | Includes accounts with no recorded successful sign-in. |
| `NoExport` | Off | Returns objects without writing a CSV file. |

## Output fields

The report contains:

- object ID
- display name
- UPN and mail address
- account enabled state
- external user invitation state
- creation date and account age
- last successful sign-in
- days since successful sign-in
- whether the account has never signed in
- classification

## Safety and operational guidance

This script only reports candidates. Do not automatically disable or delete an account solely because it appears inactive.

Before remediation, validate at least:

1. whether the guest still belongs to an active project or supplier relationship;
2. whether access is inherited through Teams, Microsoft 365 Groups, SharePoint, enterprise applications, or Azure RBAC;
3. whether the account is used rarely but legitimately;
4. whether your organization has a documented external-user lifecycle policy;
5. whether an access review should be used instead of direct account remediation.

A sensible production workflow is:

`Audit -> owner review -> approval -> disable -> observation period -> delete`

## Known limitations

- `lastSuccessfulSignInDateTime` is not backfilled historically. Microsoft states that this property became available on December 1, 2023.
- Sign-in activity can be unavailable for users that have never signed in or for older activity outside the available historical range.
- This script uses delegated authentication by default. For unattended execution, use an approved Microsoft Graph app-only authentication design rather than storing user credentials.
- The script deliberately does not remove guests or memberships.

## Suggested scheduling

Run weekly or monthly from a controlled administrative workstation or automation host, store the CSV in a protected location, and review deltas over time.

## Sources

- Microsoft Learn — Manage inactive user accounts in Microsoft Entra ID: https://learn.microsoft.com/en-us/entra/identity/monitoring-health/howto-manage-inactive-user-accounts
- Microsoft Graph — user resource / `signInActivity`: https://learn.microsoft.com/en-us/graph/api/resources/user?view=graph-rest-1.0
- Microsoft Graph — `signInActivity` resource: https://learn.microsoft.com/en-us/graph/api/resources/signinactivity?view=graph-rest-1.0
- Microsoft Entra PowerShell — `Get-EntraUserInactiveSignIn`: https://learn.microsoft.com/en-us/powershell/module/microsoft.entra.users/get-entrauserinactivesignin?view=entra-powershell
