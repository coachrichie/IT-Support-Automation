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

- [Firewall Profile Health Audit](Windows-Server/Firewall-Profile-Health-Audit/) — Prüft die wirksamen Domain-, Private- und Public-Firewall-Profile lokal read-only auf Deaktivierung, offene Standard-Inbound-Aktion und Logging blockierter Pakete.
- [Pending Reboot Signal Audit](Windows-Server/Pending-Reboot-Signal-Audit/) — Liest lokale Neustartsignale aus Servicing, Windows Update, Computername und geplanten Dateioperationen; trennt Pending, Review, Unknown und Clear ohne Neustart.
- [Disk Free Space Audit](Windows-Server/Disk-Free-Space-Audit/) — Misst lokalen freien Speicherplatz pro Windows-Server-Laufwerk lesend per CIM und priorisiert Warn- und Kritisch-Schwellen in CSV, JSON und Log.
- [Service Health Audit](Windows-Server/Service-Health-Audit/) — Prüft Windows-Dienste lokal oder per CIM auf gestoppte automatische, deaktivierte und fehlende Dienste; erzeugt lesend CSV, JSON und Log.
- [Certificate Expiry Audit](Windows-Server/Certificate-Expiry-Audit/) — Findet lokal installierte Server-/Dienstzertifikate, die innerhalb eines konfigurierbaren Zeitfensters ablaufen, und erzeugt einen read-only CSV-Report für proaktive Erneuerung und Change Control.
- [Scheduled Task Health Audit](Windows-Server/Scheduled-Task-Health-Audit/) — Prüft lokale oder entfernte geplante Aufgaben read-only auf fehlgeschlagene, nie erfolgte oder veraltete Läufe sowie Scheduler-Zustände und erzeugt CSV plus Logdatei.

### Microsoft 365

- [License Assignment Error Audit](M365/License-Assignment-Error-Audit/) — Findet tenantweit fehlerhafte direkte und gruppenbasierte Lizenzzuweisungen, löst SKU- und Gruppeninformationen auf und kennzeichnet u. a. fehlende Usage Locations, ohne Lizenzänderungen auszuführen.

### Entra ID

- [Credential Expiry Audit](Entra-ID/Credential-Expiry-Audit/) — Findet abgelaufene und bald ablaufende Client Secrets sowie Zertifikate von App-Registrierungen und optional Service Principals als read-only CSV-Audit.
- [Emergency Access Account Audit](Entra-ID/Emergency-Access-Account-Audit/) — Prueft definierte Break-Glass-Konten read-only auf Cloud-only-Status, aktive direkte Global-Administrator-Rolle, aktuelle Funktionspruefung und bekannte Conditional-Access-Ausnahmen.
- [MFA Readiness Audit](Entra-ID/MFA-Readiness-Audit/) — Priorisiert Mitglieder und Administratorkonten ohne wirksame MFA-Faehigkeit, erkennt Richtlinienluecken zwischen registrierter und nutzbarer Methode und erzeugt CSV-, JSON- und Log-Ausgaben ohne Remediation.
- [Stale Guest Account Audit](Entra-ID/Stale-Guest-Account-Audit/) — Findet inaktive Gastkonten anhand von `lastSuccessfulSignInDateTime` und erzeugt einen prüfbaren CSV-Report ohne Konten zu verändern.

### Exchange Online

- [External Forwarding Audit](Exchange/External-Forwarding-Audit/) — Prüft mailbox-level Forwarding sowie sichtbare und verborgene Inbox Rules auf externe automatische Weiterleitungen und erzeugt einen read-only CSV-Auditreport.
- [Mailbox Quota Health Audit](Exchange/Mailbox-Quota-Health-Audit/) — Priorisiert Benutzer- und Shared-Mailboxen an Warn-, Sende- oder Sende-/Empfangsgrenzen anhand ihrer tatsaechlichen Exchange-Online-Quotas und erzeugt CSV-, JSON- und Log-Ausgaben ohne Aenderungen.
- [Shared Mailbox Permission Audit](Exchange/Shared-Mailbox-Permission-Audit/) — Konsolidiert FullAccess, SendAs und SendOnBehalf für freigegebene Postfächer und markiert unvollständige oder widersprüchliche Delegierungen als read-only Review-Kandidaten.

### Microsoft Intune

- [Device Compliance State Audit](Intune/Device-Compliance-State-Audit/) — Priorisiert nicht konforme Geräte, Grace-Period-, Konflikt- und Fehlerzustände read-only über Microsoft Graph und exportiert CSV, JSON und Log.
- [Stale Device Audit](Intune/Stale-Device-Audit/) — Findet verwaltete Geräte mit veraltetem `lastSyncDateTime` als read-only Pre-Cleanup-Report.

### Microsoft Purview

- [Retention Policy Distribution Audit](Purview/Retention-Policy-Distribution-Audit/) — Prüft den DistributionStatus und die DistributionResults von Retention Policies und priorisiert Fehler, Pending-Zustände und Warnungen ohne automatische Remediation.

### Microsoft Defender

- [Device Health & Risk Audit](Defender/Device-Health-Risk-Audit/) — Priorisiert inaktive Geräte, Sensor-Kommunikationsprobleme sowie erhöhte Risk- und Exposure-Werte aus der Defender-for-Endpoint-Machine-API, ohne Remediation auszulösen.

### Microsoft Azure

- [Storage Network Exposure Audit](Azure/Storage-Network-Exposure-Audit/) — Inventarisiert die öffentliche Netzwerkfreigabe von Storage Accounts im gewählten Abonnement read-only und priorisiert Konfigurationen mit offenem Standardzugang für eine manuelle Prüfung.
- [Public IP Inventory Audit](Azure/Public-IP-Inventory-Audit/) — Erfasst Public-IP-Konfiguration und Zuordnungshinweise read-only im aktuellen Azure-Abonnement und erzeugt Review-Kandidaten ohne Nutzungs- oder Kostenbehauptung.
- [Unattached Managed Disk Audit](Azure/Unattached-Managed-Disk-Audit/) — Findet seit einem konfigurierbaren Zeitraum nicht angehängte Managed Disks als read-only FinOps-/Cleanup-Kandidaten und berücksichtigt Schutz-Tags sowie unbekanntes Ownership-Alter.

## Sicherheit

Alle Skripte sollten vor dem produktiven Einsatz in einer Testumgebung geprüft werden. Destruktive Aktionen werden vermieden oder müssen explizit aktiviert werden.
