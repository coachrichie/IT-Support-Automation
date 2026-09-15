# Intune Stale Device Audit

Read-only PowerShell audit for identifying Microsoft Intune managed-device records that have not checked in for a configurable period.

## Why this matters

Stale Intune records are a recurring lifecycle and support problem: replaced, lost, retired, or otherwise inactive endpoints can remain visible and distort inventory and compliance reporting. Microsoft Intune provides Device cleanup rules that automatically **hide** devices after a configured inactivity period. As of September 2026, Microsoft documents a supported cleanup window of **30–270 days**. Cleanup rules don't wipe or retire devices and don't remove the corresponding Microsoft Entra ID object.

This script complements the built-in cleanup feature by producing a reviewable CSV before an administrator changes cleanup policy or performs any lifecycle action. It is deliberately read-only.

A particularly timely reason to keep a scriptable workflow is that Microsoft's Intune Device Offboarding Agent was removed on **June 1, 2026**; Microsoft directs organizations back to established device lifecycle and remediation options.

## What the script does

- Retrieves managed devices from Microsoft Intune through Microsoft Graph.
- Uses `lastSyncDateTime` to calculate inactivity.
- Defaults to 90 days and enforces the documented 30–270 day cleanup range.
- Optionally filters by platform.
- Optionally includes records where the last sync time is unavailable.
- Exports a CSV suitable for service-desk review, CMDB reconciliation, or change-control evidence.
- Performs no retire, wipe, delete, cleanup-rule, or Entra device operation.

## Requirements

- PowerShell 7 recommended.
- An active Microsoft Intune tenant/license.
- Microsoft Graph PowerShell modules:
  - `Microsoft.Graph.Authentication`
  - `Microsoft.Graph.DeviceManagement`
- Delegated Microsoft Graph permission `DeviceManagementManagedDevices.Read.All` (admin consent required). `DeviceManagementManagedDevices.ReadWrite.All` also satisfies the read operation but isn't required by this script.

Install modules:

```powershell
Install-Module Microsoft.Graph.Authentication -Scope CurrentUser
Install-Module Microsoft.Graph.DeviceManagement -Scope CurrentUser
```

## Usage

Default 90-day audit:

```powershell
./Get-StaleIntuneDevice.ps1
```

Audit Windows devices inactive for 120 days:

```powershell
./Get-StaleIntuneDevice.ps1 -DaysInactive 120 -Platform Windows
```

Include records without a known last sync:

```powershell
./Get-StaleIntuneDevice.ps1 -IncludeUnknownLastSync
```

Return objects without writing a CSV:

```powershell
$stale = ./Get-StaleIntuneDevice.ps1 -DaysInactive 90 -NoExport
$stale | Format-Table DeviceName,OperatingSystem,ComplianceState,DaysSinceLastSync
```

## Output fields

The report includes device name, OS/version, compliance state, ownership, management agent, primary UPN, serial number, Intune managed-device ID, Entra device ID, enrollment time, last sync, days since last sync, and classification.

## Operational workflow

1. Run the audit and review the CSV with endpoint/service-desk owners.
2. Compare candidates with asset inventory, Autopilot/ADE/ABM records, and current user/device ownership where applicable.
3. Decide whether built-in Intune Device cleanup rules should hide stale records automatically.
4. Treat actual Retire, Delete, Wipe, Autopilot removal, and Entra ID deletion as separate approved lifecycle changes.

This distinction matters: Microsoft documents that cleanup rules only hide stale Intune records. A device can reappear if it checks in before its management certificate expires. Cleanup doesn't remove the Entra device object.

## Security and safe defaults

The script requests only `DeviceManagementManagedDevices.Read.All` and contains no mutation cmdlets. It does not automatically reconnect an existing Graph session with broader/different permissions; instead, it stops if the current session lacks the required Intune device scope. This avoids silently changing the operator's authentication context.

CSV output contains operational identifiers such as usernames, serial numbers, and device IDs. Store reports according to your organization's access-control and retention policy.

## Validation

Before operational use:

1. Run with `-NoExport` in a test/admin workstation session.
2. Compare a sample of returned devices with **Intune admin center > Devices > All devices**.
3. Confirm `LastSyncDateTime` and platform filtering for several known devices.
4. If evaluating a cleanup rule, compare the script output with Intune's **Preview affected devices** function using the same inactivity threshold.

## Known limitations

- `lastSyncDateTime` indicates Intune check-in activity; it isn't proof that a physical asset is unused or disposed.
- A stale Intune record can have a separate Microsoft Entra ID lifecycle state.
- Platform names returned by Graph can evolve; validate platform filtering in your tenant.
- This script doesn't reconcile Windows Autopilot, Apple Business Manager/ADE, Configuration Manager, or asset-management databases.
- Large environments depend on Microsoft Graph paging and service availability; `Get-MgDeviceManagementManagedDevice -All` handles Graph paging through the SDK.

## Rollback / removal

The script is read-only, so no tenant rollback is necessary. Delete the generated CSV if it is no longer required. To remove the delegated Graph session, run:

```powershell
Disconnect-MgGraph
```

## Sources

Microsoft documentation verified September 15, 2026:

- Device cleanup rules: https://learn.microsoft.com/en-us/intune/governance/configure-cleanup-rules
- Configure Microsoft Graph API access for Intune: https://learn.microsoft.com/en-us/intune/developer/configure-graph-api-access
- Microsoft Graph permissions reference: https://learn.microsoft.com/en-us/graph/permissions-reference
- List managedDevices: https://learn.microsoft.com/en-us/graph/api/intune-devices-manageddevice-list?view=graph-rest-1.0
- Device Offboarding Agent retirement: https://learn.microsoft.com/en-us/intune/copilot/agents/manage-device-offboarding-agent

## Design note

The script intentionally stops at **audit and evidence generation**. Built-in cleanup rules are safer for routine portal hygiene than an unattended script that deletes managed-device records, while explicit device offboarding should remain an approved lifecycle action because Delete/Retire/Wipe have platform-specific effects.
