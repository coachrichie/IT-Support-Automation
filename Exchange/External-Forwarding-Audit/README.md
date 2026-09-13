# Exchange Online External Forwarding Audit

Read-only PowerShell audit for automatic mail forwarding in Exchange Online. The script checks both mailbox-level forwarding and Inbox Rules, including hidden rules, and classifies destinations as internal, trusted external, external, or unresolved.

## Why this matters

Automatic forwarding is useful for legitimate workflows, but it is also a recurring support and security topic. It can cause unexpected delivery behavior, repeated NDRs such as `5.7.520`, and can be abused for data exfiltration after account compromise.

Microsoft documents that outbound spam policies can block automatic external forwarding and that disabling forwarding affects both user Inbox Rules and administrator-configured mailbox forwarding. Microsoft also notes that a restrictive control generally wins when multiple forwarding controls interact.

This audit does **not** change forwarding settings. It only inventories and classifies them.

## What the script checks

`Get-ExternalForwardingAudit.ps1` evaluates:

- mailbox-level `ForwardingSmtpAddress`
- mailbox-level `ForwardingAddress`
- `DeliverToMailboxAndForward` to show whether a local copy is retained
- Inbox Rules using `ForwardTo`
- Inbox Rules using `RedirectTo`
- Inbox Rules using `ForwardAsAttachmentTo`
- hidden Inbox Rules via `Get-InboxRule -IncludeHidden`
- Exchange Online Accepted Domains to distinguish internal from external destinations
- optional trusted external domains
- unresolved forwarding targets that need manual review
- per-mailbox Inbox Rule read failures, so incomplete audits are visible instead of silently ignored

By default, internal-only forwarding is omitted from the report to keep the output focused on external risk. Use `-IncludeInternal` if you want the complete forwarding inventory.

## Prerequisites

- Windows PowerShell 5.1 or PowerShell 7
- Exchange Online PowerShell module (`ExchangeOnlineManagement`)
- an Exchange Online account with RBAC permissions that allow reading:
  - mailboxes
  - Inbox Rules
  - recipients
  - Accepted Domains

A tenant Exchange Administrator can typically perform the audit, but production environments should prefer the least-privilege Exchange RBAC role assignment that permits the required read operations.

Install the module if needed:

```powershell
Install-Module ExchangeOnlineManagement -Scope CurrentUser
```

## Connection options

### Option 1: Let the script connect

```powershell
.\Get-ExternalForwardingAudit.ps1 -ConnectExchangeOnline -UserPrincipalName admin@contoso.com
```

The script disconnects only if it created the Exchange Online session itself.

### Option 2: Use an existing Exchange Online session

```powershell
Connect-ExchangeOnline -UserPrincipalName admin@contoso.com
.\Get-ExternalForwardingAudit.ps1
```

## Usage examples

### Audit all user mailboxes

```powershell
.\Get-ExternalForwardingAudit.ps1 -ConnectExchangeOnline
```

### Include shared mailboxes

```powershell
.\Get-ExternalForwardingAudit.ps1 -ConnectExchangeOnline -IncludeSharedMailboxes
```

### Audit selected mailboxes

```powershell
.\Get-ExternalForwardingAudit.ps1 `
    -ConnectExchangeOnline `
    -Mailbox alice@contoso.com,bob@contoso.com
```

### Mark approved external partner domains separately

```powershell
.\Get-ExternalForwardingAudit.ps1 `
    -ConnectExchangeOnline `
    -TrustedExternalDomain partner.example,archive.example
```

Trusted external targets remain visible but are classified as `TrustedExternal` with a lower default review priority than unknown external targets.

### Include disabled Inbox Rules and internal forwarding

```powershell
.\Get-ExternalForwardingAudit.ps1 `
    -ConnectExchangeOnline `
    -IncludeDisabledRules `
    -IncludeInternal
```

### Return objects without writing a CSV

```powershell
$findings = .\Get-ExternalForwardingAudit.ps1 -ConnectExchangeOnline -NoExport
$findings | Where-Object Risk -eq 'High'
```

## Parameters

| Parameter | Purpose |
|---|---|
| `-Mailbox` | Limit the audit to one or more mailbox identities. |
| `-IncludeSharedMailboxes` | Include shared mailboxes in addition to user mailboxes. |
| `-IncludeDisabledRules` | Include disabled Inbox Rules. |
| `-IncludeInternal` | Include forwarding targets in accepted internal domains. |
| `-TrustedExternalDomain` | External domains that should be classified separately as approved/trusted. |
| `-OutputPath` | CSV destination. Defaults to a timestamped file in the current directory. |
| `-NoExport` | Return PowerShell objects only and skip CSV creation. |
| `-ConnectExchangeOnline` | Connect to Exchange Online from the script. |
| `-UserPrincipalName` | Optional sign-in UPN used with `Connect-ExchangeOnline`. |

## Output fields

The CSV and returned PowerShell objects include:

- mailbox display name and primary SMTP address
- recipient type
- forwarding mechanism
- Inbox Rule name, priority, and enabled state where applicable
- whether mailbox-level forwarding keeps a local copy
- resolved target address and domain
- classification: `Internal`, `TrustedExternal`, `External`, `Unresolved`, or `AuditError`
- risk: `Low`, `Medium`, `High`, or `Review`
- resolution method and raw target value
- audit status and error message when a mailbox could not be fully inspected

## Operational interpretation

### High

An external destination not listed in `-TrustedExternalDomain`. Review whether the business owner expects it and whether external automatic forwarding is permitted by policy.

### Medium

An external destination explicitly listed as trusted. It is still externally forwarded mail and should remain in periodic review.

### Review

A target could not be resolved to a reliable SMTP address, or Inbox Rules for a mailbox could not be read. These entries should not be treated as clean audit results.

### Low

Internal forwarding. These entries appear only with `-IncludeInternal`.

## Security considerations

- The script is read-only and calls no `Set-*`, `Remove-*`, or destructive cmdlets.
- Do not treat the absence of active external forwarding as proof that tenant policy blocks external forwarding. Configuration inventory and policy enforcement are separate questions.
- A configured external forwarding target may still be blocked by outbound spam policy, Remote Domain settings, or mail flow rules.
- Hidden Inbox Rules are included because they can be relevant during troubleshooting and compromise investigations.
- Store exported CSV files securely; mailbox forwarding targets can reveal sensitive business relationships and account configuration.

## Performance and limitations

- `Get-InboxRule` is queried per mailbox. Large tenants can therefore take significant time to audit.
- The script intentionally avoids parallel Exchange Online sessions to reduce throttling risk and keep behavior predictable.
- Some legacy or unusual forwarding target representations might not expose a directly parseable SMTP address. The script attempts `Get-Recipient` resolution and otherwise marks the target `Unresolved`.
- The script audits mailbox and Inbox Rule forwarding. It does not inventory every tenant-wide mail flow rule, connector, journaling, transport agent, or third-party routing mechanism.
- A forwarding configuration can exist even when policy prevents delivery. This script inventories configuration; it does not run message trace validation.

## Rollback / removal

No rollback is required because the script makes no Exchange Online configuration changes.

If you choose to remediate a finding, validate the business requirement first and follow Microsoft documentation for the specific forwarding mechanism. Avoid bulk removal until the target has been confirmed with the mailbox owner or service owner.

## Suggested validation steps

1. Run against one known test mailbox first.
2. Create a temporary test Inbox Rule forwarding to a controlled external address and confirm the script detects it.
3. Test mailbox-level forwarding in a lab or test mailbox and verify `KeepCopy` reflects `DeliverToMailboxAndForward`.
4. Add the controlled external domain to `-TrustedExternalDomain` and verify the classification changes to `TrustedExternal`.
5. Use `-IncludeDisabledRules` and verify disabled test rules are returned.
6. Remove the test forwarding configuration after validation.
7. In production, compare suspicious results with Exchange Admin Center settings, outbound anti-spam policy, Remote Domains, and message trace as needed.

## Microsoft documentation and supporting sources

The implementation is based primarily on current Microsoft documentation:

- Microsoft Defender for Office 365 — Control automatic external email forwarding and troubleshoot `5.7.520` (updated 18 August 2026):  
  https://learn.microsoft.com/en-us/defender-office-365/outbound-spam-policies-external-email-forwarding
- Microsoft Learn — Connect to Exchange Online PowerShell:  
  https://learn.microsoft.com/en-us/powershell/exchange/connect-to-exchange-online-powershell?view=exchange-ps
- Microsoft Learn — `Get-InboxRule` (`-IncludeHidden` is available for inspecting hidden rules):  
  https://learn.microsoft.com/en-us/powershell/module/exchangepowershell/get-inboxrule?view=exchange-ps
- Microsoft Learn — Exchange Online PowerShell cmdlet property sets. The `Delivery` property set for `Get-EXOMailbox` includes `DeliverToMailboxAndForward`, `ForwardingAddress`, and `ForwardingSmtpAddress`:  
  https://learn.microsoft.com/en-us/powershell/exchange/cmdlet-property-sets?view=exchange-ps
- Microsoft Learn — `Set-Mailbox` forwarding examples and forwarding-related properties:  
  https://learn.microsoft.com/en-us/powershell/module/exchange/set-mailbox?view=exchange-ps
- Microsoft Exchange troubleshooting — Inbox Rule diagnostics, including interaction with mailbox forwarding (last updated 25 June 2025):  
  https://learn.microsoft.com/en-us/troubleshoot/exchange/outlook-issues/resolve-inbox-rule-issues

## Practical support relevance

Recent Microsoft support/Q&A cases continue to show administrators troubleshooting external forwarding and NDR `5.7.520`, including situations where forwarding is not obvious in the Outlook UI. Those cases reinforce the value of checking both mailbox-level settings and server-side Inbox Rules instead of relying on a single admin portal view.
