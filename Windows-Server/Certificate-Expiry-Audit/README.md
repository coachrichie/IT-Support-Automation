# Windows Server Certificate Expiry Audit

Read-only PowerShell audit for certificates that are expired or approaching expiration in Windows Server Local Computer certificate stores.

## Problem / use case

Expired TLS, RDS, NPS, application and service certificates are a recurring cause of authentication failures and service outages. Microsoft explicitly notes that certificate expiration can cause outages and that Windows generates certificate lifecycle notifications for certificates close to expiration. Microsoft also documents real support cases in which an expired certificate remaining on a server prevents client authentication.

This automation gives service desk and infrastructure teams a simple, schedulable inventory/report that can be reviewed before renewal or change-control work begins. It does **not** renew, delete, replace or modify certificates.

## What the script checks

`Get-WindowsCertificateExpiryAudit.ps1` reads selected `Cert:\LocalMachine` stores and reports certificates whose `NotAfter` date falls inside a configurable warning window.

Default stores:

- `LocalMachine\My`
- `LocalMachine\WebHosting`

Optional stores include `CA`, `Root`, and `Remote Desktop`.

The report includes status, days remaining, subject, issuer, thumbprint, serial number, validity dates, private-key presence, signature algorithm, EKUs and friendly name.

By default, expired certificates are excluded so that the normal report focuses on actionable upcoming renewals. Use `-IncludeExpired` for incident response or hygiene reviews. In `My` and `WebHosting`, certificates without a private key are excluded by default; use `-IncludeWithoutPrivateKey` when a broader inventory is required.

## Requirements and permissions

- Windows PowerShell 5.1 or PowerShell 7+
- Windows Server or Windows client with the PowerShell Certificate provider
- Read access to the Local Computer certificate stores being audited
- Administrator elevation can be required depending on the host/store security configuration
- No additional PowerShell module is required

No Microsoft Graph, Azure or Microsoft 365 permission is required.

## Installation

Copy the script to a controlled administration or monitoring location, for example:

```powershell
C:\Admin\Certificate-Audit\Get-WindowsCertificateExpiryAudit.ps1
```

Review the code before production use and test it on a non-critical server first.

## Usage

Default 30-day audit of `My` and `WebHosting`:

```powershell
.\Get-WindowsCertificateExpiryAudit.ps1
```

Use a 60-day renewal window:

```powershell
.\Get-WindowsCertificateExpiryAudit.ps1 -WarningDays 60
```

Include expired certificates:

```powershell
.\Get-WindowsCertificateExpiryAudit.ps1 -WarningDays 30 -IncludeExpired
```

Audit RDS and Personal stores without writing CSV:

```powershell
.\Get-WindowsCertificateExpiryAudit.ps1 -StoreName 'My','Remote Desktop' -NoExport
```

Create a broad inventory including public certificates without private keys:

```powershell
.\Get-WindowsCertificateExpiryAudit.ps1 -StoreName 'My','WebHosting','CA' -WarningDays 90 -IncludeExpired -IncludeWithoutPrivateKey
```

## Parameters

| Parameter | Default | Purpose |
|---|---:|---|
| `WarningDays` | 30 | Number of days before expiration considered actionable |
| `StoreName` | `My`,`WebHosting` | Local Machine certificate stores to inspect |
| `ComputerName` | local hostname | Label written to the report; the script remains local/read-only |
| `IncludeExpired` | off | Also report already expired certificates |
| `IncludeWithoutPrivateKey` | off | Include certificates without private keys in `My`/`WebHosting` |
| `OutputPath` | timestamped CSV | CSV destination |
| `NoExport` | off | Suppress CSV creation |

## Output and prioritization

`Status` is one of:

- `ExpiringSoon` — expires within the configured warning window
- `Expired` — already expired; only emitted with `-IncludeExpired`

`DaysRemaining` makes the report easy to sort or ingest into monitoring/ITSM tooling. Negative values identify already expired certificates.

## Scheduling

The script is safe to execute repeatedly because it performs only reads and creates a new timestamped report by default. A common operational pattern is to run it daily or weekly through Task Scheduler and ingest the CSV/log output into the organization's monitoring or ticketing workflow.

Do not treat the report as proof that a certificate is actually bound to a live service. Certificate stores can contain historical, duplicate or application-managed certificates. Validate service bindings before renewal/removal work.

## Validation

1. Open `certlm.msc` on the same server.
2. Inspect the stores passed to `-StoreName`.
3. Compare certificate thumbprints and `NotAfter` values with the CSV.
4. Run with `-NoExport` during initial testing.
5. For a known certificate, confirm `DaysRemaining` corresponds to its expiration date.

For autoenrolled certificates, separately validate the certificate template renewal settings. Microsoft documents that autoenrollment runs periodically and renewal is normally triggered only after 80% of certificate validity has elapsed and while the certificate is inside its configured renewal period.

## Security considerations

- The script never exports private keys.
- It does not renew, remove, import, bind or alter certificates.
- Thumbprints and certificate subjects can still disclose infrastructure/application information; protect generated CSV reports accordingly.
- Do not automatically delete expired root/intermediate certificates based solely on this report. Microsoft notes that some expired trusted roots remain necessary for backward-compatible signature validation.
- Certificate-chain and revocation health are separate concerns. An unexpired leaf certificate can still fail validation because an intermediate certificate or CRL is expired/unavailable.

## Known limitations

- The script audits the local machine only; use your normal orchestration platform (PowerShell Remoting, Configuration Manager, Azure Arc, RMM, etc.) to execute it fleet-wide.
- It does not discover IIS, HTTP.sys, RDS, NPS, SQL Server or application bindings.
- It does not validate certificate chains, CRLs, OCSP, hostname/SAN matching or private-key ACLs.
- It does not query AD CS issued-certificate databases or certificate templates.
- Some applications maintain certificates outside the Windows certificate store.

## Rollback / removal

No system rollback is required because the script makes no certificate or configuration changes. Remove the script, scheduled task (if you created one), and generated CSV files to decommission the automation.

## Operational rationale

Microsoft's current Windows Server PKI guidance states that every certificate has a validity period and becomes unacceptable/unusable after it ends. Microsoft also recommends planning renewal dates and lifecycle management. Current Microsoft support guidance for certificate autoenrollment states that renewal behavior depends on the validity/renewal periods and the final 20% of certificate lifetime. These make proactive expiry inventory a high-value recurring support control.

## Sources

Sources checked 2026-09-19:

- Microsoft Learn — PKI design considerations using Active Directory Certificate Services in Windows Server: https://learn.microsoft.com/en-us/windows-server/identity/ad-cs/pki-design-considerations
- Microsoft Learn — Approval required for certificate renewals when certificate autoenrollment configured (updated 2026-02-12): https://learn.microsoft.com/en-us/troubleshoot/windows-server/certificates-and-public-key-infrastructure-pki/approval-required-certificate-renewals-autoenrollment
- Microsoft Learn — Securing PKI: Planning Certificate Algorithms and Usages (certificate lifecycle/expiration events): https://learn.microsoft.com/en-us/previous-versions/windows/it-pro/windows-server-2012-r2-and-2012/dn786428(v=ws.11)
- Microsoft Learn — Clients can't authenticate with a server (expired certificate support case): https://learn.microsoft.com/en-us/troubleshoot/windows-server/certificates-and-public-key-infrastructure-pki/clients-cant-authenticate-server
- Microsoft Learn — Required trusted root certificates (updated 2026-02-12): https://learn.microsoft.com/en-us/troubleshoot/windows-server/certificates-and-public-key-infrastructure-pki/trusted-root-certificates-are-required
- Microsoft Learn — Network Policy Server Certificate Revocation List overview: https://learn.microsoft.com/en-us/windows-server/networking/technologies/nps/network-policy-server-certificate-revocation-list-overview

## Future extensions

Good follow-up automations include fleet-wide collection through PowerShell Remoting, IIS/HTTP.sys binding correlation, AD CS template/renewal auditing, and CRL/AIA reachability checks. Those should remain separate modules so that this baseline audit stays predictable and read-only.
