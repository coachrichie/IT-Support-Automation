# Entra ID Emergency Access Account Audit

Prueft definierte Microsoft-Entra-ID-Notfallzugangskonten (Break Glass) read-only auf zentrale Betriebs- und Sicherheitsanforderungen: Kontostatus, Cloud-only-Eigenschaft, aktive direkte Global-Administrator-Zuweisung, letzte erfolgreiche Anmeldung sowie bekannte Conditional-Access-Ausnahmen.

## Zweck und Support-Case

Notfallzugangskonten sollen einen Tenant auch dann administrierbar halten, wenn normale Identitaets-, MFA-, PIM- oder Conditional-Access-Abhaengigkeiten ausfallen. Eine Fehlkonfiguration bleibt oft unbemerkt, bis der Notfall eintritt. Der Audit liefert deshalb einen reproduzierbaren Review fuer Identity Operations, Second-Level-Support, Systems Engineering und regelmaessige Kontrolltermine.

## Verhalten und Sicherheitsstandard

- nutzt ausschliesslich Microsoft Graph v1.0 und fuehrt keine Tenant-Aenderung aus
- erwartet stabile Entra-Objekt-IDs statt UPN-Suchmustern
- prueft deaktivierte, synchronisierte und nicht auf `onmicrosoft.com` liegende Konten
- prueft aktive direkte Global-Administrator-Zuweisungen
- ermittelt aktivierte Conditional-Access-Richtlinien, die ein Konto oder eine bekannte Notfallgruppe adressieren, ohne es auszuschliessen
- unterscheidet aktivierte und reine Report-only-Richtlinien
- bewertet eine fehlende oder zu alte erfolgreiche Anmeldung als Hinweis auf eine ueberfaellige Funktionspruefung
- erzeugt CSV, JSON-Zusammenfassung und Logdatei
- besitzt einen Offline-JSON-Modus fuer anonymisierte Tests

## Voraussetzungen

### PowerShell und Modul

- PowerShell 7 empfohlen; Windows PowerShell 5.1 wird durch die verwendete Syntax ebenfalls unterstuetzt
- `Microsoft.Graph.Authentication`

```powershell
Install-Module Microsoft.Graph.Authentication -Scope CurrentUser
```

### Minimale Microsoft-Graph-Berechtigungen

Das Skript verwendet nur lesende Berechtigungen:

- `User.Read.All` fuer Benutzerattribute
- `AuditLog.Read.All` fuer `signInActivity`
- `RoleManagement.Read.Directory` fuer aktive Rollen und Rollendefinitionen
- `Policy.Read.All` fuer Conditional-Access-Richtlinien

Bei delegierter Anmeldung muss das Konto zusaetzlich eine unterstuetzte Entra-Rolle besitzen. Fuer den kombinierten Abruf ist in der Praxis mindestens **Global Reader** geeignet. Alternativ koennen getrennte, restriktivere Ausfuehrungskontexte oder eine freigegebene App-/Managed-Identity-Implementierung verwendet werden. Admin-Consent ist fuer die genannten Berechtigungen erforderlich.

`signInActivity` erfordert laut Microsoft Entra ID P1 oder P2. Conditional Access erfordert ebenfalls eine passende Entra-Lizenz.

## Parameter

| Parameter | Standard | Beschreibung |
|---|---|---|
| `EmergencyAccessUserId` | erforderlich | Eine oder mehrere Entra-Benutzerobjekt-IDs (GUID). |
| `EmergencyAccessGroupId` | leer | Bekannte Gruppenobjekt-IDs, ueber die Notfallkonten in Conditional Access ausgeschlossen werden. |
| `ValidationIntervalDays` | `90` | Maximal akzeptiertes Alter der letzten erfolgreichen Anmeldung als technischer Validierungsindikator. |
| `OutputPath` | zeitgestempelte CSV | Detailreport. |
| `SummaryPath` | zeitgestempelte JSON-Datei | Zusammenfassung inklusive Zwei-Konten-Empfehlung. |
| `LogPath` | zeitgestempelte Logdatei | Betriebs- und Fehlermeldungen ohne Tokens. |
| `OfflineInputPath` | leer | Anonymisierte JSON-Daten statt Livezugriff. |
| `IncludeHealthy` | aus | Gibt auch Konten ohne erkannte Abweichung aus. |
| `NoExport` | aus | Gibt nur PowerShell-Objekte zurueck. |
| `DisconnectOnExit` | aus | Trennt nur eine vom Skript selbst gestartete Graph-Sitzung. |

## Bewertung

| Schweregrad | Bedingung |
|---|---|
| `Critical` | Konto deaktiviert, keine aktive direkte Global-Administrator-Zuweisung oder mindestens eine aktivierte CA-Richtlinie ohne bekannte Ausnahme. |
| `High` | Konto ist synchronisiert oder verwendet keine `onmicrosoft.com`-UPN. |
| `Medium` | Keine erfolgreiche Anmeldung innerhalb des Validierungsintervalls. |
| `Healthy` | Keine der konfigurierten Abweichungen erkannt. |

Die JSON-Zusammenfassung weist separat aus, ob mindestens zwei Notfallzugangskonten konfiguriert wurden.

## Beispiele

### Zwei Notfallkonten pruefen

```powershell
./Get-EntraEmergencyAccessAudit.ps1 `
  -EmergencyAccessUserId '11111111-1111-1111-1111-111111111111','22222222-2222-2222-2222-222222222222'
```

### Bekannte Ausschlussgruppe einbeziehen

```powershell
./Get-EntraEmergencyAccessAudit.ps1 `
  -EmergencyAccessUserId '11111111-1111-1111-1111-111111111111','22222222-2222-2222-2222-222222222222' `
  -EmergencyAccessGroupId '33333333-3333-3333-3333-333333333333' `
  -OutputPath 'C:\Reports\emergency-access.csv'
```

### Alle Konten inklusive gesunder Ergebnisse ausgeben

```powershell
./Get-EntraEmergencyAccessAudit.ps1 `
  -EmergencyAccessUserId '11111111-1111-1111-1111-111111111111','22222222-2222-2222-2222-222222222222' `
  -IncludeHealthy -ValidationIntervalDays 90
```

### Offline-Test

```powershell
./Get-EntraEmergencyAccessAudit.ps1 `
  -EmergencyAccessUserId '11111111-1111-1111-1111-111111111111','22222222-2222-2222-2222-222222222222' `
  -EmergencyAccessGroupId '33333333-3333-3333-3333-333333333333' `
  -OfflineInputPath '.\sample-emergency-access.json' -IncludeHealthy
```

Die JSON-Datei muss die Arrays `Users`, `RoleDefinitions`, `RoleAssignments` und `ConditionalAccessPolicies` enthalten. Sie sollte ausschliesslich synthetische oder anonymisierte Werte verwenden.

## Logging, Fehlerbehandlung und Validierung

- `Set-StrictMode` und `$ErrorActionPreference = 'Stop'` verhindern stilles Weiterlaufen.
- GUID-, Datei-, JSON-Schema-, Modul- und Graph-Scope-Pruefungen liefern konkrete Fehler.
- Alle Graph-Sammlungen werden ueber `@odata.nextLink` vollstaendig paginiert.
- Unbekannte Benutzer, fehlende Rollendefinitionen und ungueltige Zeitstempel brechen kontrolliert ab.
- Die Logdatei enthaelt keine Passwoerter, Client Secrets, Tokens oder reale Beispieldaten.
- Der Offline-Modus macht Klassifizierung und Export reproduzierbar.

## Validierung vor produktivem Einsatz

1. Mit synthetischen Offline-Daten testen.
2. In einem Testtenant mit den dokumentierten Read-Berechtigungen ausfuehren.
3. Kontostatus und aktive Rolle im Entra Admin Center gegenpruefen.
4. Conditional-Access-Ergebnisse mit Policy-Ansicht und What-If-Tool vergleichen.
5. Dokumentierten Notfalltest und `LastSuccessfulSignInUtc` gemeinsam bewerten.
6. Erst danach einen geschuetzten, regelmaessigen Auditlauf einrichten.

## Sicherheit und Datenschutz

Die Ausgabe enthaelt hochsensible Identitaets-, Rollen- und Richtlinieninformationen. Sie gehoert in einen verschluesselten, zugriffsbeschraenkten Administrationsspeicher mit definierter Aufbewahrungsfrist. UPNs, Objekt-IDs und Policy-Namen duerfen nicht unkontrolliert weitergegeben werden.

Das Skript speichert keine Anmeldedaten und nimmt keine Remediation vor. Fuer unbeaufsichtigte Ausfuehrungen sind Managed Identity oder zertifikatbasierte App-Authentifizierung vorzuziehen; Client Secrets und Kennwoerter gehoeren nicht in Skript, Task Scheduler oder Quellcode.

## Einschraenkungen

- Der Audit wertet aktive direkte Rollenzuweisungen aus. Gruppenbasierte, eligible oder zeitlich geplante PIM-Zuweisungen werden nicht als permanente aktive Global-Administrator-Zuweisung anerkannt.
- Bei `EmergencyAccessGroupId` wird geprueft, ob eine Richtlinie die angegebene Gruppe ausschliesst. Die tatsaechliche Gruppenmitgliedschaft muss separat validiert werden.
- Die Benutzerscope-Analyse erkennt `All`, direkte Benutzer- und die explizit angegebenen Gruppen-IDs. Verschachtelte dynamische Scope-Logik, Authentifizierungskontext und Workload-Identity-Policies liegen ausserhalb des Audits.
- Eine letzte erfolgreiche Anmeldung ist nur ein technischer Indikator. Sie ersetzt kein dokumentiertes Notfalltestszenario und keinen Post-Mortem-Prozess.
- Der Report prueft nicht die konkrete Passkey-/FIDO2- oder zertifikatbasierte Authentifizierungsmethode.
- Replikationsverzoegerungen und Lizenzgrenzen koennen die Graph-Daten beeinflussen.

## Rollback und Rueckbau

Das Skript ist read-only; Tenant-Aenderungen muessen nicht zurueckgerollt werden. Fuer den Rueckbau:

1. geplante Ausfuehrung entfernen oder deaktivieren;
2. CSV-, JSON- und Logdateien gemaess Aufbewahrungsrichtlinie loeschen;
3. nicht mehr benoetigten Admin-Consent oder App-Berechtigungen entziehen;
4. bei interaktiver Nutzung die Graph-Sitzung mit `Disconnect-MgGraph` trennen.

## Quellen

- Microsoft Entra: Manage emergency access admin accounts — https://learn.microsoft.com/en-us/entra/identity/role-based-access-control/security-emergency-access
- Microsoft Graph: List users / `signInActivity` — https://learn.microsoft.com/en-us/graph/api/user-list?view=graph-rest-1.0
- Microsoft Graph: List Conditional Access policies — https://learn.microsoft.com/en-us/graph/api/conditionalaccessroot-list-policies?view=graph-rest-1.0
- Microsoft Graph: List directory roles — https://learn.microsoft.com/en-us/graph/api/directoryrole-list?view=graph-rest-1.0
