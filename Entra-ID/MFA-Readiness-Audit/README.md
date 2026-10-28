# Entra ID MFA Readiness Audit

Ermittelt read-only, welche Microsoft-Entra-ID-Konten keine wirksame MFA-Registrierung besitzen, bei welchen Konten eine registrierte Methode durch die aktuelle Richtlinie nicht als MFA-faehig gilt und wo SSPR- oder optional Passwordless-Luecken bestehen.

## Zweck und Support-Case

Eine reine Aussage wie „MFA ist registriert“ reicht fuer den Betrieb nicht aus. Eine registrierte Methode kann durch die aktuelle Authentication Methods Policy unzulaessig sein. Das Skript trennt deshalb `isMfaRegistered` von `isMfaCapable` und priorisiert besonders privilegierte Konten. Typische Einsaetze sind Rollout-Kontrolle, Service-Desk-Eskalationen, Identity-Hardening und die Vorbereitung auf Conditional-Access-Verschaerfungen.

## Verhalten und Sicherheitsstandard

- nutzt ausschliesslich den Microsoft-Graph-v1.0-Registrierungsbericht
- fuehrt keine Aenderungen an Benutzern, Authentifizierungsmethoden oder Richtlinien aus
- schliesst Gaeste und gesunde Konten standardmaessig aus
- markiert Administratorkonten ohne MFA-Faehigkeit als `Critical`
- erkennt den Unterschied zwischen registrierter und aktuell nutzbarer MFA
- erzeugt CSV, JSON-Zusammenfassung und Logdatei
- unterstuetzt einen Offline-CSV-Modus fuer Tests und kontrollierte Auswertungen

## Voraussetzungen

### PowerShell und Module

- PowerShell 7 empfohlen; Windows PowerShell 5.1 wird durch die verwendete Syntax ebenfalls unterstuetzt
- `Microsoft.Graph.Authentication`
- `Microsoft.Graph.Reports`

```powershell
Install-Module Microsoft.Graph.Authentication -Scope CurrentUser
Install-Module Microsoft.Graph.Reports -Scope CurrentUser
```

### Minimale Berechtigungen und Rollen

Fuer delegierte und App-only-Zugriffe dokumentiert Microsoft Graph als geringste API-Berechtigung:

- `AuditLog.Read.All`

Bei delegierter Anmeldung braucht das Konto zusaetzlich eine unterstuetzte Entra-Rolle. Die geringste dokumentierte integrierte Rolle ist:

- **Reports Reader**

Alternativ werden auch Security Reader, Security Administrator oder Global Reader unterstuetzt. Hoehere Rollen sind fuer dieses Skript nicht erforderlich.

Der Registrierungsbericht unterliegt den von Microsoft dokumentierten Lizenzanforderungen fuer Authentication Methods Activity. Diese muessen im Zieltenant vor dem Rollout geprueft werden.

## Parameter

| Parameter | Standard | Beschreibung |
|---|---|---|
| `OutputPath` | Zeitgestempelte CSV im aktuellen Ordner | Detailreport. |
| `SummaryPath` | Zeitgestempelte JSON-Datei | Maschinenlesbare Zusammenfassung und Severity-Zaehler. |
| `LogPath` | Zeitgestempelte Logdatei | Betriebs- und Fehlermeldungen ohne Token oder Zugangsdaten. |
| `InputCsvPath` | leer | Nutzt eine vorbereitete CSV statt Microsoft Graph; geeignet fuer Tests. |
| `MaxReportAgeHours` | `48` | Ab diesem Alter wird ein Datensatz als veraltet markiert. |
| `IncludeGuests` | aus | Bezieht Gastkonten ein. |
| `IncludeHealthy` | aus | Gibt auch Konten ohne erkannte Luecke aus. |
| `RequirePasswordless` | aus | Markiert fehlende Passwordless-Faehigkeit als `Low`. |
| `NoExport` | aus | Gibt nur PowerShell-Objekte zurueck. |
| `DisconnectOnExit` | aus | Trennt nur eine vom Skript selbst gestartete Graph-Sitzung. |

## Bewertung

| Schweregrad | Bedingung |
|---|---|
| `Critical` | Administratorkonto ist nicht MFA-faehig. |
| `High` | Mitglied ohne registrierte und nutzbare MFA. |
| `Medium` | MFA ist registriert, aber nicht nutzbar; SSPR ist aktiviert, aber nicht nutzbar; oder Berichtsdaten sind zu alt. |
| `Low` | Passwordless wurde explizit gefordert, ist aber nicht verfuegbar. |
| `Healthy` | Keine konfigurierte Abweichung erkannt. |

## Beispiele

### Standardaudit

```powershell
./Get-EntraMfaReadinessAudit.ps1
```

### Alle Mitglieder inklusive gesunder Konten ausgeben

```powershell
./Get-EntraMfaReadinessAudit.ps1 -IncludeHealthy -OutputPath 'C:\Reports\mfa-readiness.csv'
```

### Passwordless-Bereitschaft mitbewerten

```powershell
./Get-EntraMfaReadinessAudit.ps1 -RequirePasswordless -MaxReportAgeHours 24
```

### Gaeste in einen getrennten Review aufnehmen

```powershell
./Get-EntraMfaReadinessAudit.ps1 -IncludeGuests -OutputPath 'C:\Reports\mfa-readiness-with-guests.csv'
```

### Offline-Test mit anonymisierten Daten

```powershell
./Get-EntraMfaReadinessAudit.ps1 -InputCsvPath '.\sample-registration-details.csv' -IncludeHealthy
```

Die Eingabe-CSV muss die Spalten `Id`, `UserPrincipalName`, `UserDisplayName`, `UserType`, `IsAdmin`, `IsMfaRegistered`, `IsMfaCapable`, `IsSsprEnabled`, `IsSsprRegistered`, `IsSsprCapable`, `IsPasswordlessCapable`, `MethodsRegistered` und `LastUpdatedDateTime` enthalten.

## Logging, Fehlerbehandlung und Validierung

- `Set-StrictMode` und `$ErrorActionPreference = 'Stop'` verhindern stilles Weiterlaufen bei unerwarteten Fehlern.
- Modul-, Graph-Scope-, Datei-, Schema-, Boolean- und Zeitstempelpruefungen brechen mit einer konkreten Fehlermeldung ab.
- Die Logdatei enthaelt Start, Datenquelle, Anzahl und Exportpfade; Tokens werden weder gelesen noch protokolliert.
- Der Offline-Modus macht Klassifizierung und Exporte ohne Tenant-Zugriff reproduzierbar.
- Die JSON-Datei enthaelt Quellanzahl, exportierte Zeilen, verwendete Schalter und Severity-Zaehler.

## Validierung vor produktivem Einsatz

1. Skript zunaechst mit anonymisierten CSV-Daten testen.
2. In einem Testtenant mit Reports-Reader-Rolle und nur `AuditLog.Read.All` ausfuehren.
3. Stichproben gegen **Entra admin center > Protection > Authentication methods > User registration details** vergleichen.
4. Berichtsalter und tenantweite Lizenzierung pruefen.
5. CSV nur in einem geschuetzten administrativen Speicherort ablegen, da UPNs und Sicherheitsstatus enthalten sind.

## Sicherheit und Datenschutz

Die Ergebnisse enthalten personenbezogene Identitaets- und Sicherheitsmerkmale. Wende Datenminimierung, rollenbasierten Zugriff, angemessene Aufbewahrungsfristen und geschuetzte Uebertragung an. Nutze fuer unbeaufsichtigte Ausfuehrungen eine freigegebene Managed Identity oder zertifikatbasierte App-Authentifizierung; speichere keine Kennwoerter, Client Secrets oder Tokens im Skript.

Eine automatische Remediation ist bewusst nicht enthalten. Vor Nutzerkommunikation oder Richtlinienaenderungen muessen Servicekonten, Break-Glass-Konten, technische Einschraenkungen und genehmigte Ausnahmen geprueft werden.

## Einschraenkungen

- Der Bericht zeigt Registrierungs- und Faehigkeitsstatus, nicht ob MFA bei jedem konkreten Sign-in tatsaechlich erzwungen wurde.
- Conditional Access, Authentication Strengths und einzelne Sign-in-Logs werden nicht ausgewertet.
- Der Microsoft-Bericht funktioniert laut API-Dokumentation nicht fuer deaktivierte Benutzer.
- `isAdmin` stammt aus dem Bericht und ersetzt keine separate, zeitpunktgenaue Rollenmitgliedschaftsanalyse.
- Cloud- und Lizenzverfuegbarkeit koennen je Tenant und nationaler Cloud variieren.

## Rollback und Rueckbau

Das Skript ist read-only; ein technischer Rollback von Tenant-Aenderungen ist nicht erforderlich. Fuer den Rueckbau:

1. geplante Ausfuehrung entfernen oder deaktivieren;
2. erzeugte CSV-, JSON- und Logdateien gemaess Aufbewahrungsrichtlinie loeschen;
3. nicht mehr benoetigte App-Berechtigungen oder Admin-Consent entziehen;
4. bei interaktiver Nutzung die Graph-Sitzung mit `Disconnect-MgGraph` trennen.

## Quellen

- Microsoft Graph: List userRegistrationDetails — https://learn.microsoft.com/graph/api/authenticationmethodsroot-list-userregistrationdetails
- Microsoft Graph: userRegistrationDetails resource — https://learn.microsoft.com/graph/api/resources/userregistrationdetails?view=graph-rest-1.0
- Microsoft Graph PowerShell: Get-MgReportAuthenticationMethodUserRegistrationDetail — https://learn.microsoft.com/powershell/module/microsoft.graph.reports/get-mgreportauthenticationmethoduserregistrationdetail
