# Exchange Online Mailbox Quota Health Audit

Ermittelt read-only, welche Exchange-Online-Postfaecher ihre Warn-, Sende- oder Sende-/Empfangsgrenzen erreichen. Das Skript kombiniert die tenant- und lizenzspezifischen Quotas aus `Get-EXOMailbox` mit der aktuellen Belegung aus `Get-EXOMailboxStatistics` und erzeugt einen priorisierten Support-Report.

## Zweck und Support-Case

Volle Postfaecher fuehren zu fehlgeschlagenem Versand, abgewiesenen eingehenden Nachrichten und vermeidbaren Eskalationen. Benutzer- und Shared-Mailboxen koennen unterschiedliche Grenzwerte besitzen. Statt eine feste Groesse anzunehmen, bewertet das Skript deshalb jede Mailbox gegen ihre tatsaechlich gemeldeten Quotas.

Typische Einsaetze:

- proaktive Kapazitaetskontrolle im Service Desk
- Analyse bei Versand- oder Zustellproblemen
- Ueberwachung stark genutzter Shared-Mailboxen
- Vorbereitung von Archivierungs-, Lizenz- oder Aufbewahrungsentscheidungen
- regelmaessiger Exchange-Online-Health-Report

## Verhalten und Sicherheitsstandard

- nutzt nur lesende Exchange-Online-Cmdlets
- aendert keine Quotas, Lizenzen, Archive oder Mailbox-Inhalte
- bewertet `IssueWarningQuota`, `ProhibitSendQuota` und `ProhibitSendReceiveQuota`
- priorisiert erreichte harte Grenzen vor Prozentwerten
- gibt gesunde Mailboxen standardmaessig nicht aus
- erzeugt CSV, JSON-Zusammenfassung und Logdatei
- unterstuetzt anonymisierte Offline-CSV-Daten fuer Tests

## Voraussetzungen

### PowerShell-Modul

```powershell
Install-Module ExchangeOnlineManagement -Scope CurrentUser
```

PowerShell 7 wird empfohlen. Die verwendete Syntax ist auch mit Windows PowerShell 5.1 kompatibel.

### Rollen und minimale Berechtigungen

Der Standardbetrieb verwendet eine delegierte Exchange-Online-Anmeldung. Das Konto benoetigt Zugriff auf:

- `Get-EXOMailbox`
- `Get-EXOMailboxStatistics`

Als gering privilegierter Ausgangspunkt ist die Exchange-Online-Rolle **View-Only Recipients** vorgesehen. Microsoft beschreibt diese Rolle fuer das Anzeigen von Empfaengereigenschaften; die effektive Cmdlet-Zuweisung muss im Zieltenant mit `Get-ManagementRole -Cmdlet Get-EXOMailboxStatistics` beziehungsweise den vorhandenen Role Assignments validiert werden. Global Administrator oder Organization Management sind fuer den normalen Audit nicht erforderlich.

Fuer unbeaufsichtigte App-only-Ausfuehrungen gelten zusaetzlich die von Microsoft dokumentierte Anwendungserlaubnis `Exchange.ManageAsApp`, Zertifikatsauthentifizierung sowie eine moeglichst eng begrenzte Exchange-RBAC-Zuweisung. Das Skript speichert keine Zugangsdaten oder Zertifikate.

## Parameter

| Parameter | Standard | Beschreibung |
|---|---|---|
| `WarningPercent` | `75` | Prozentwert fuer `Warning`; muss kleiner als `CriticalPercent` sein. |
| `CriticalPercent` | `90` | Prozentwert fuer `Critical`. |
| `MailboxType` | `UserMailbox`, `SharedMailbox` | Einzubeziehende Mailbox-Typen. |
| `OutputPath` | Zeitgestempelte CSV | Detailreport. |
| `SummaryPath` | Zeitgestempelte JSON-Datei | Ausfuehrungs- und Severity-Zusammenfassung. |
| `LogPath` | Zeitgestempelte Logdatei | Betriebs- und Fehlermeldungen. |
| `InputCsvPath` | leer | Offline-CSV statt Exchange Online. |
| `IncludeHealthy` | aus | Gibt auch Mailboxen ohne Abweichung aus. |
| `NoExport` | aus | Gibt nur PowerShell-Objekte zurueck. |
| `DisconnectOnExit` | aus | Trennt nur eine vom Skript selbst gestartete Sitzung. |

## Bewertung

| Schweregrad | Bedingung |
|---|---|
| `Critical` | Sende-/Empfangsgrenze oder Sendegrenze erreicht; alternativ `CriticalPercent` erreicht. |
| `Error` | Statistiken einer Mailbox konnten nicht geladen werden. |
| `Warning` | IssueWarningQuota oder `WarningPercent` erreicht. |
| `Review` | Keine endliche effektive Quota ermittelbar. |
| `Healthy` | Keine konfigurierte Schwelle erreicht. |

Die harte Exchange-Quota hat Vorrang vor der prozentualen Klassifizierung.

## Beispiele

### Standardaudit fuer Benutzer- und Shared-Mailboxen

```powershell
./Get-ExchangeMailboxQuotaHealthAudit.ps1
```

### Engere Warnschwellen und eigener Ausgabeordner

```powershell
./Get-ExchangeMailboxQuotaHealthAudit.ps1 `
    -WarningPercent 70 `
    -CriticalPercent 85 `
    -OutputPath 'C:\Reports\exchange-quota-health.csv' `
    -SummaryPath 'C:\Reports\exchange-quota-health-summary.json'
```

### Raum- und Geraetepostfaecher einbeziehen

```powershell
./Get-ExchangeMailboxQuotaHealthAudit.ps1 `
    -MailboxType UserMailbox,SharedMailbox,RoomMailbox,EquipmentMailbox
```

### Alle Mailboxen als PowerShell-Objekte zurueckgeben

```powershell
$quotaState = ./Get-ExchangeMailboxQuotaHealthAudit.ps1 -IncludeHealthy -NoExport
$quotaState | Format-Table Severity,PrimarySmtpAddress,TotalItemSizeGB,UsedPercentOfEffectiveLimit
```

### Offline-Test mit anonymisierten Daten

```powershell
./Get-ExchangeMailboxQuotaHealthAudit.ps1 -InputCsvPath '.\mailboxes.csv' -IncludeHealthy
```

Die CSV muss die Spalten `Identity`, `DisplayName`, `PrimarySmtpAddress`, `RecipientTypeDetails`, `TotalItemSizeBytes`, `ItemCount`, `IssueWarningQuotaBytes`, `ProhibitSendQuotaBytes` und `ProhibitSendReceiveQuotaBytes` enthalten. Groessenwerte sind Bytes oder `Unlimited`.

## Logging, Fehlerbehandlung und Validierung

- `Set-StrictMode` und `$ErrorActionPreference = 'Stop'` verhindern stilles Weiterlaufen bei unerwarteten Fehlern.
- Modul, Verbindung, Eingabedatei, CSV-Schema, Bytewerte und Schwellenreihenfolge werden validiert.
- Ein Fehler bei einer einzelnen Statistikabfrage beendet nicht den gesamten Tenant-Report; die Mailbox erscheint mit `STATISTICS_UNAVAILABLE`.
- Die Logdatei enthaelt Zeitstempel, Datenquelle, Anzahl und Exportpfade, aber keine Tokens oder Zugangsdaten.
- Die JSON-Datei enthaelt Quellanzahl, Schwellwerte, Mailbox-Typen und Severity-Zaehler.

## Validierung vor produktivem Einsatz

1. Offline-Test mit anonymisierten Daten ausfuehren.
2. In einem Testtenant mit einer gering privilegierten Exchange-Rolle starten.
3. Stichproben gegen Exchange Admin Center und `Get-EXOMailboxStatistics` vergleichen.
4. Benutzer- und Shared-Mailboxen mit unterschiedlichen Lizenzen testen.
5. Pruefen, ob Reportpfade geschuetzt und Aufbewahrungsfristen definiert sind.

## Sicherheit und Datenschutz

Der Report enthaelt Anzeigenamen, SMTP-Adressen und Kapazitaetsdaten. Speichere ihn nur an geschuetzten administrativen Orten, beschraenke den Zugriff nach Least Privilege und loesche alte Reports gemaess Aufbewahrungsrichtlinie. Fuer Automation sind Managed Identity beziehungsweise zertifikatbasierte App-Authentifizierung und eng begrenzte RBAC-Zuweisungen zu bevorzugen; keine Passwoerter, Client Secrets oder Tokens im Skript speichern.

Vor jeder Remediation muessen Ursache, Lizenz, Archivstatus, Retention/Hold, fachliche Ownership und moegliche Auswirkungen auf Mailflow und Compliance geprueft werden.

## Einschraenkungen

- Das Skript analysiert primaere Mailboxbelegung; Archivbelegung wird nicht separat ausgewertet.
- Recoverable Items, Retention Holds und Ordnerverteilung werden nicht diagnostiziert.
- Eine hohe Belegung erklaert nicht automatisch die Ursache des Wachstums.
- Exchange-Quotas koennen von Lizenz, Mailbox-Typ und individueller Konfiguration abhaengen.
- Einzelabfragen der Statistiken koennen in sehr grossen Tenants lange dauern und Throttling unterliegen.
- App-only-Berechtigungen und RBAC unterscheiden sich vom interaktiven Standardbetrieb und muessen separat validiert werden.

## Rollback und Rueckbau

Das Skript ist read-only; Tenant-Aenderungen muessen nicht zurueckgerollt werden. Fuer den Rueckbau:

1. geplante Ausfuehrung entfernen oder deaktivieren;
2. CSV-, JSON- und Logdateien gemaess Richtlinie loeschen;
3. nicht mehr benoetigte Exchange-Rollenzuweisungen oder App-Berechtigungen entziehen;
4. aktive Sitzung mit `Disconnect-ExchangeOnline -Confirm:$false` trennen.

## Quellen

- Microsoft Learn — Get-EXOMailbox: https://learn.microsoft.com/powershell/module/exchangepowershell/get-exomailbox
- Microsoft Learn — Get-EXOMailboxStatistics: https://learn.microsoft.com/powershell/module/exchangepowershell/get-exomailboxstatistics
- Microsoft Learn — Exchange Online permissions: https://learn.microsoft.com/exchange/permissions-exo/permissions-exo
- Microsoft Learn — Exchange Online mailbox quotas: https://learn.microsoft.com/troubleshoot/exchange/user-and-shared-mailboxes/increase-or-customize-mailbox-size
