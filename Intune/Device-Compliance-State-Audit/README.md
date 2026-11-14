# Intune Device Compliance State Audit

Read-only PowerShell-Audit für den Compliance-Status verwalteter Microsoft-Intune-Geräte über Microsoft Graph v1.0. Das Skript klassifiziert Zustände, folgt Graph-Seitenlinks und erzeugt CSV, JSON und Log. Es ändert keine Geräte, Richtlinien oder Zugriffsentscheidungen.

## Zweck und Support-Case

Ein Gerät kann in Intune verwaltet sein und dennoch `noncompliant`, `inGracePeriod`, `conflict` oder `error` melden. Der Audit gibt First-/Second-Level-Support und Administration eine priorisierte Liste zur fachlichen Prüfung. `noncompliant` wird als `Critical`, `inGracePeriod` als `Warning`, `conflict` und `error` als `Review` eingestuft. `unknown` und `configManager` bleiben ausdrücklich `Unknown`; `compliant` ist `Healthy`. Die Einordnung ist ein Support-Signal und keine Aussage über den tatsächlichen Conditional-Access-Zugriff.

## Voraussetzungen und Module

- PowerShell 7 oder Windows PowerShell 5.1 und das Modul `Microsoft.Graph.Authentication` für Live-Abfragen.
- Aktive Intune-Lizenz, Microsoft-Graph-Verbindung und Zugriff auf `https://graph.microsoft.com`.
- Für Offline-Tests reicht PowerShell mit `ConvertFrom-Json`; weder Tenant noch Graph-Modul werden benötigt.
- Schreibrecht nur auf den lokalen Ausgabeordner.

## Rollen und minimale Berechtigungen

Für delegierte Graph-Abfragen ist **`DeviceManagementManagedDevices.Read.All`** die geringste dokumentierte Berechtigung für die Liste verwalteter Geräte. Zusätzlich muss das Konto in Intune eine passende, möglichst eng begrenzte Leseberechtigung für verwaltete Geräte haben; die genaue Rollenzuweisung hängt von Scope-Tags und der Organisation ab. App-only-Zugriff benötigt dieselbe Application Permission und Admin Consent. Das Skript fordert selbst keine Anmeldung an und speichert keine Tokens. ReadWrite-Berechtigungen sind nicht erforderlich.

## Parameter

| Parameter | Standard | Bedeutung |
|---|---|---|
| `OutputDirectory` | `./Reports` | Lokaler Ausgabeordner für CSV, JSON und Log |
| `InputJsonPath` | keiner | Synthetische JSON-Daten statt Graph-Abfrage |
| `OnlyFindings` | aus | Nur Zeilen außer `Healthy` exportieren; `Unknown` bleibt enthalten |

## Beispiele

```powershell
Connect-MgGraph -Scopes 'DeviceManagementManagedDevices.Read.All'
./Get-DeviceComplianceStateAudit.ps1 -OutputDirectory './Reports'
./Get-DeviceComplianceStateAudit.ps1 -OnlyFindings -OutputDirectory './Reports'
./Get-DeviceComplianceStateAudit.ps1 -InputJsonPath './sample-devices.json' -OutputDirectory './Reports'
```

Synthetische Offline-Eingabe, ohne echte Geräte- oder Kundendaten:

```json
[{"id":"device-001","deviceName":"TEST-DEVICE-01","operatingSystem":"Windows","complianceState":"inGracePeriod"}]
```

## Logging, Fehlerbehandlung und Validierung

Ein Lauf schreibt `DeviceComplianceStateAudit-*.csv`, `.json` und `.log` mit UTC-Zeitstempel. Das Log enthält nur Zähler und Dateipfade, keine Tokens. Es werden keine Teilberichte geschrieben, wenn Graph-Paging, Berechtigung, Antwortformat oder JSON-Daten fehlschlagen. Leere Eingaben führen zu einem Fehler; bei `OnlyFindings` und ausschließlich gesunden Geräten entsteht eine CSV mit Kopfzeile und ein leeres JSON-Array. Die Ergebnisdateien enthalten Gerätenamen und IDs und sind entsprechend geschützt aufzubewahren.

Zur Validierung zuerst eine synthetische Datei mit allen sieben dokumentierten Zuständen prüfen: `compliant`, `noncompliant`, `inGracePeriod`, `conflict`, `error`, `unknown`, `configManager`. Danach in einer Testumgebung einige Ergebnisse mit Intune vergleichen. Anzahl im Log und CSV/JSON auf Vollständigkeit prüfen. Graph-Fehler und Berechtigungen vor einer betrieblichen Bewertung klären.

## Sicherheit und Einschränkungen

- Ausschließlich `GET /deviceManagement/managedDevices` auf Microsoft Graph v1.0; keine Remediation.
- Der Audit bewertet den Gerätezustand, nicht einzelne Compliance-Regeln oder Ursachen. Für Ursachenanalyse sind weitere Intune-Berichte nötig.
- Daten können zeitverzögert sein; die Ausgabe ist eine Momentaufnahme. `unknown` und `configManager` werden nicht als `compliant` interpretiert.
- Graph-Paginierung ist auf 1000 Seiten begrenzt; bei Überschreitung bricht der Lauf ohne Teilbericht ab.
- Offline-JSON prüft Logik, nicht Live-Berechtigungen oder Tenant-Zustand.

## Rollback und Rückbau

Da der Audit keine Tenant-Änderungen vornimmt, ist kein Rollback erforderlich. Lokale Berichte nach den geltenden Aufbewahrungsregeln löschen. Eine eigens für den Test eingerichtete Graph-Berechtigung kann anschließend wieder entzogen werden.

## Quellen

- [Microsoft: List managedDevices](https://learn.microsoft.com/en-us/graph/api/intune-devices-manageddevice-list?view=graph-rest-1.0)
- [Microsoft: complianceState](https://learn.microsoft.com/en-us/graph/api/resources/intune-devices-compliancestate?view=graph-rest-1.0)
- [Microsoft: Invoke-MgGraphRequest](https://learn.microsoft.com/en-us/powershell/module/microsoft.graph.authentication/invoke-mggraphrequest)
