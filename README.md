# IT Support Automation

PowerShell-basierte Automatisierungen für wiederkehrende Aufgaben und Support-Fälle im Microsoft-Umfeld.

## Schwerpunkte

- Windows Server
- Microsoft 365
- Microsoft Entra ID
- Microsoft Intune
- Exchange Online
- Microsoft Purview
- Microsoft Defender
- Microsoft Azure

## Qualitätsstandard

Jede Lösung soll nach Möglichkeit enthalten:

- Problemstellung und konkreten Use Case
- Voraussetzungen, Module, Rollen und Berechtigungen
- robuste, parametrisierte PowerShell-Lösung
- Fehlerbehandlung und Logging
- möglichst idempotentes Verhalten
- sichere Standardwerte
- Installations- und Nutzungsanleitung
- Beispielaufrufe
- Test- und Validierungsschritte
- Sicherheits- und Betriebsaspekte
- bekannte Einschränkungen
- Rollback- bzw. Rückbau-Hinweise
- Quellen und weiterführende Dokumentation

## Struktur

```text
Windows-Server/
M365/
Entra-ID/
Intune/
Exchange/
Purview/
Defender/
Azure/
```

Jede Automatisierung erhält einen eigenen Unterordner mit PowerShell-Skript und README.

## Verfügbare Automatisierungen

### Windows Server

- [Certificate Expiry Audit](Windows-Server/Certificate-Expiry-Audit/) — Findet lokal installierte Server-/Dienstzertifikate, die innerhalb eines konfigurierbaren Zeitfensters ablaufen, und erzeugt einen read-only CSV-Report für proaktive Erneuerung und Change Control.

### Entra ID

- [Stale Guest Account Audit](Entra-ID/Stale-Guest-Account-Audit/) — Findet inaktive Gastkonten anhand von `lastSuccessfulSignInDateTime` und erzeugt einen prüfbaren CSV-Report ohne Konten zu verändern.

### Exchange Online

- [External Forwarding Audit](Exchange/External-Forwarding-Audit/) — Prüft mailbox-level Forwarding sowie sichtbare und verborgene Inbox Rules auf externe automatische Weiterleitungen und erzeugt einen read-only CSV-Auditreport.

### Microsoft Intune

- [Stale Device Audit](Intune/Stale-Device-Audit/) — Findet verwaltete Geräte mit veraltetem `lastSyncDateTime` als read-only Pre-Cleanup-Report.

### Microsoft Purview

- [Retention Policy Distribution Audit](Purview/Retention-Policy-Distribution-Audit/) — Prüft den DistributionStatus und die DistributionResults von Retention Policies und priorisiert Fehler, Pending-Zustände und Warnungen ohne automatische Remediation.

### Microsoft Defender

- [Device Health & Risk Audit](Defender/Device-Health-Risk-Audit/) — Priorisiert inaktive Geräte, Sensor-Kommunikationsprobleme sowie erhöhte Risk- und Exposure-Werte aus der Defender-for-Endpoint-Machine-API, ohne Remediation auszulösen.

## Sicherheit

Alle Skripte sollten vor dem produktiven Einsatz in einer Testumgebung geprüft werden. Destruktive Aktionen werden vermieden oder müssen explizit aktiviert werden.
