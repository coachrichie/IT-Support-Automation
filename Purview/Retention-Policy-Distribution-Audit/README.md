# Microsoft Purview Retention Policy Distribution Audit

## Problemstellung

Retention Policies sind erst wirksam, nachdem sie an die ausgewählten Microsoft-365-Workloads verteilt wurden. Fehler oder lange Pending-Zustände können deshalb dazu führen, dass eine fachlich korrekt konfigurierte Richtlinie nicht wie erwartet angewendet wird.

Microsoft empfiehlt, vor weiteren Änderungen den DistributionStatus zu prüfen. Bei Fehlern liefert DistributionResults zusätzliche Diagnoseinformationen. Ein Pending-Status sollte zunächst auslaufen, bevor weitere Policy-Änderungen vorgenommen werden.

Dieses Skript automatisiert den wiederkehrenden, read-only Health Check von Purview Retention Policies.

## Funktionen

- prüft klassische Retention Policies mit `Get-RetentionCompliancePolicy -DistributionDetail`
- prüft optional App Retention Policies mit `Get-AppRetentionCompliancePolicy -DistributionDetail`
- klassifiziert Status als `Error`, `Pending`, `Warning` oder `Healthy`
- nimmt `DistributionResults` in den Report auf
- filtert optional auf eine einzelne Policy
- blendet gesunde Policies standardmäßig aus, um Support-Noise zu reduzieren
- exportiert einen CSV-Report
- führt keinerlei Retry, Policy-Änderung oder andere Remediation aus

## Voraussetzungen

- PowerShell 7 oder Windows PowerShell 5.1
- aktuelles Modul `ExchangeOnlineManagement`
- Verbindung zu Security & Compliance PowerShell:

```powershell
Connect-IPPSSession
```

Das verwendete Administratorkonto benötigt die für Retention Management erforderlichen Purview-/Compliance-Berechtigungen. Verwende nach Möglichkeit Least Privilege und ein separates Admin-Konto.

## Installation

```powershell
Install-Module ExchangeOnlineManagement -Scope CurrentUser
Import-Module ExchangeOnlineManagement
Connect-IPPSSession
```

## Nutzung

Nur problematische oder noch ausstehende Policies anzeigen und CSV exportieren:

```powershell
./Get-PurviewRetentionPolicyDistributionAudit.ps1
```

Alle Policies inklusive gesunder Policies:

```powershell
./Get-PurviewRetentionPolicyDistributionAudit.ps1 -IncludeHealthy
```

Nur klassische Retention Policies:

```powershell
./Get-PurviewRetentionPolicyDistributionAudit.ps1 -PolicyType Classic
```

Eine konkrete Policy untersuchen:

```powershell
./Get-PurviewRetentionPolicyDistributionAudit.ps1 -PolicyName 'Corporate Retention'
```

Nur Konsolenausgabe:

```powershell
./Get-PurviewRetentionPolicyDistributionAudit.ps1 -NoExport
```

## Interpretation

`Error` bzw. `Failed` sollte untersucht werden. `DistributionResults` enthält häufig den konkreteren Fehlerkontext. Microsoft dokumentiert unter anderem `PolicySyncTimeout`, `PolicyNotifyError`, `InternalError` und `ActiveDirectorySyncError` als mögliche Fehlerbilder.

`Pending` ist nicht automatisch ein Fehler. Microsoft empfiehlt ausdrücklich, mit weiteren Änderungen zu warten, bis eine Policy nicht mehr Pending ist.

`Warning` kann laut Microsoft je nach Fall ignorierbar sein; der konkrete Inhalt von `DistributionResults` sollte trotzdem geprüft werden.

## Remediation

Das Skript selbst nimmt keine Änderungen vor. Nach manueller Bewertung kann Microsoft bei einem echten Distribution-Fehler einen Retry über einen der folgenden Befehle empfehlen:

```powershell
Set-RetentionCompliancePolicy -Identity '<policy name>' -RetryDistribution
```

Für die neueren App-Retention-Workloads:

```powershell
Set-AppRetentionCompliancePolicy -Identity '<policy name>' -RetryDistribution
```

Diese Befehle sind bewusst **nicht** Bestandteil der Automation, damit ein Audit niemals unbeabsichtigt Compliance-Konfigurationen verändert.

## Sicherheitsaspekte

- read-only Audit
- keine Policy wird aktiviert, deaktiviert oder verändert
- kein automatischer `RetryDistribution`
- keine Preservation Locks werden gesetzt oder verändert
- CSV-Dateien können Policy-Namen und Fehlerdetails enthalten und sollten wie administrative Betriebsdaten geschützt werden
- produktive Remediation sollte Change Control und Vier-Augen-Prinzip berücksichtigen

## Preservation Lock

Eine Policy mit Preservation Lock kann nicht einfach deaktiviert, gelöscht oder weniger restriktiv gemacht werden. Microsoft weist ausdrücklich darauf hin, dass selbst Global Admins diese Einschränkungen nach dem Setzen nicht umgehen können. Das Skript liest `RestrictiveRetention`, sofern die Eigenschaft verfügbar ist, verändert sie aber niemals.

## Bekannte Einschränkungen

- Security & Compliance PowerShell muss bereits authentifiziert sein
- verfügbare App-Retention-Cmdlets hängen von Modul, Tenant und unterstützten Workloads ab
- ein technischer Distribution-Status ersetzt keine fachliche Prüfung, ob Locations und Retention Settings korrekt gewählt wurden
- der Report führt keine automatische Ursachenbehebung durch

## Rollback / Rückbau

Da das Skript ausschließlich liest, gibt es keinen Tenant-seitigen Rollback. Zum Rückbau genügen das Entfernen des Skripts, erzeugter Reports und gegebenenfalls des lokalen ExchangeOnlineManagement-Moduls.

## Quellen

Geprüft am 21.09.2026:

- Microsoft Learn — Identify errors in Microsoft 365 retention and retention label policies: https://learn.microsoft.com/en-us/troubleshoot/microsoft-365/purview/retention/identify-errors-in-retention-and-retention-label-policies
- Microsoft Learn — PowerShell cmdlets for retention policies and retention labels: https://learn.microsoft.com/en-us/purview/retention-cmdlets
- Microsoft Learn — Automatically retain or delete content by using retention policies: https://learn.microsoft.com/en-us/purview/create-retention-policies
- Microsoft Learn — Resolve errors in Microsoft 365 retention and retention label policies: https://learn.microsoft.com/en-us/troubleshoot/microsoft-365/purview/retention/resolve-errors-in-retention-and-retention-label-policies
- Microsoft Learn — Preservation Lock: https://learn.microsoft.com/en-us/purview/retention-preservation-lock
