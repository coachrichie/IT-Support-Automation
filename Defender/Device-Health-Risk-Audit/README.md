# Microsoft Defender for Endpoint – Device Health & Risk Audit

## Problemstellung

Defender for Endpoint sammelt Geräte-, Sensor-, Risiko- und Exposure-Daten über den gesamten Endpoint-Lifecycle. In der Praxis entstehen wiederkehrende Service-Desk- und Security-Aufgaben: Geräte melden sich nicht mehr, Sensoren haben Kommunikationsprobleme, Geräte bleiben mit erhöhtem Risiko oder Exposure im Bestand, oder ausgemusterte Geräte müssen von tatsächlich gestörten Geräten unterschieden werden.

Microsoft dokumentiert, dass offboarded Geräte nach sieben Tagen ohne Telemetrie als `Inactive` erscheinen. Geräte, die 30 Tage nicht aktiv waren, fließen nicht mehr in den Exposure Score ein. Historische Geräteprofile können dennoch bis zu 180 Tage sichtbar bleiben. Dadurch ist ein regelmäßiger Audit sinnvoll, statt allein die Sichtbarkeit im Portal als Hinweis auf ein aktuelles Problem zu interpretieren.

Dieses Skript erzeugt einen **read-only Review-Report** und nimmt keinerlei Remediation, Isolation oder Offboarding vor.

## Nutzen

- findet Geräte mit `Inactive`, `ImpairedCommunication`, `NoSensorData` oder unbekanntem Sensorzustand
- erkennt Geräte, deren `lastSeen` älter als ein frei definierbarer Grenzwert ist
- priorisiert Medium/High Risk und Exposure
- unterstützt OS-Filter und Ausschluss-Tags für bekannte Ausnahmen oder decommissioned Geräte
- erzeugt einen CSV-Report für Service Desk, Security Operations, Change Management oder CMDB-Abgleich
- keine Änderungen an Defender, Endpoints oder Microsoft Entra ID

## Dateien

- `Get-DefenderDeviceHealthAudit.ps1` – Audit-Skript
- `README.md` – Dokumentation

## Voraussetzungen

- PowerShell 7 empfohlen; Windows PowerShell 5.1 sollte für die verwendeten Standard-Cmdlets ebenfalls funktionieren
- Microsoft Defender for Endpoint Plan 1/2 oder Defender for Business entsprechend der verwendeten API
- OAuth2 Access Token für die Ressource `https://api.security.microsoft.com`
- für Application Context mindestens `Machine.Read.All`
- für Delegated Context mindestens `Machine.Read`; der Benutzer benötigt zusätzlich mindestens die Defender-Rollenberechtigung **View Data** und sieht nur Geräte, auf die er über Device Groups Zugriff hat

Für geplante Automatisierung empfiehlt Microsoft Application Context für Hintergrunddienste. Token und Client Secrets gehören nicht in das Repository oder in Klartext-Logs. Verwende für produktive Automatisierung bevorzugt Zertifikate, Managed Identity bzw. einen geeigneten Secret Store, soweit die gewählte Authentifizierungsarchitektur dies unterstützt.

## Funktionsweise

Das Skript ruft die Defender-for-Endpoint-API auf:

```text
GET https://api.security.microsoft.com/api/machines?$top=10000
```

Die List-Machines-API unterstützt OData und liefert u. a. `lastSeen`, `healthStatus`, `riskScore`, `exposureLevel`, `onboardingStatus`, `machineTags`, `aadDeviceId` und RBAC-Gruppeninformationen. Microsoft dokumentiert eine maximale Page Size von 10.000 sowie Rate Limits von 100 Requests/Minute und 1.500 Requests/Stunde.

Ein Gerät landet standardmäßig im Report, wenn mindestens eines zutrifft:

1. `healthStatus` ist `Inactive` oder `lastSeen` liegt mehr als 30 Tage zurück.
2. `riskScore` ist `Medium` oder `High`.
3. `exposureLevel` ist `Medium` oder `High`.
4. Der Sensorzustand ist nicht `Active`/`Inactive`, z. B. `ImpairedCommunication` oder `NoSensorData`.

Die Priorität wird aus Risiko, Exposure und Sensorzustand abgeleitet. Das ist eine betriebliche Triage-Hilfe und ersetzt keine Microsoft-Risikobewertung.

## Nutzung

### Standardaudit

```powershell
$token = '<OAuth access token for api.security.microsoft.com>'
./Get-DefenderDeviceHealthAudit.ps1 -AccessToken $token
```

### Strengerer Inaktivitätsgrenzwert

```powershell
./Get-DefenderDeviceHealthAudit.ps1 -AccessToken $token -InactiveDays 14
```

### Nur Windows-Endpunkte

```powershell
./Get-DefenderDeviceHealthAudit.ps1 -AccessToken $token -OsPlatform Windows10,Windows11,WindowsServer2019
```

### Decommissioned Geräte ausblenden

```powershell
./Get-DefenderDeviceHealthAudit.ps1 -AccessToken $token -ExcludeTag decommissioned
```

Microsoft empfiehlt ausdrücklich, Geräte vor Offboarding/Uninstallation zu taggen, wenn später zwischen bewusst ausgemusterten und lediglich nicht erreichbaren Geräten unterschieden werden soll.

### Alle Geräte für einen vollständigen Inventarreport

```powershell
./Get-DefenderDeviceHealthAudit.ps1 -AccessToken $token -IncludeHealthy
```

### Nur Konsole, keine CSV

```powershell
./Get-DefenderDeviceHealthAudit.ps1 -AccessToken $token -NoExport
```

## Reportfelder

Der CSV-Report enthält unter anderem:

- ComputerDnsName
- Defender MachineId
- Microsoft Entra AadDeviceId
- OS und Build
- HealthStatus
- LastSeenUtc / DaysSinceSeen
- RiskScore
- ExposureLevel
- DeviceValue
- OnboardingStatus
- RBAC Device Group
- Tags
- berechnete Priority
- ReviewReason

## Fehlerbehandlung und Logging

- API-Fehler werden mit URI und Fehlermeldung als terminating error ausgegeben.
- `Set-StrictMode` und `$ErrorActionPreference = 'Stop'` verhindern möglichst stilles Weiterlaufen bei unerwarteten Zuständen.
- Pagination über `@odata.nextLink` wird verarbeitet, falls die API sie liefert.
- Token oder Secrets werden nicht geloggt.

## Idempotenz und sichere Defaults

Das Skript ist vollständig read-only. Wiederholte Ausführung verändert weder Geräte noch Defender-Konfiguration. Standardmäßig werden nur Review-Kandidaten exportiert. Keine Isolation, Unisolation, Offboarding-, Tagging- oder Löschaktion wird ausgelöst.

## Validierung

Vor produktiver Nutzung:

1. Mit einem Konto/App mit ausschließlich Leserechten testen.
2. Stichproben aus dem CSV mit **Microsoft Defender portal → Assets → Devices** vergleichen.
3. `lastSeen`, `healthStatus`, Risk und Exposure für einige Geräte kontrollieren.
4. Ausschluss-Tags mit einem Testgerät validieren.
5. Erst danach als geplanten Report ausführen.

## Sicherheitsaspekte

Ein Access Token ist ein Secret. Nicht in Skripte, Git, Tickets oder Logs schreiben. Für unattended Jobs sollte die Tokenbeschaffung außerhalb dieses Skripts über eine kontrollierte OAuth2-/Identity-Lösung erfolgen.

Ein `Inactive`-Status allein bedeutet nicht automatisch, dass ein Gerät gelöscht oder kompromittiert ist. Microsoft nennt als mögliche Ursachen u. a. Offboarding, Neuinstallation, Umbenennung, Nichtbenutzung oder fehlende Telemetrie. Deshalb erzeugt dieses Skript ausschließlich eine Review-Liste.

## Bekannte Einschränkungen

- Die API liefert Geräte nur innerhalb der konfigurierten Defender-Retention und des RBAC-Sichtbereichs.
- Nicht-onboarded Geräte können durch Device Discovery länger sichtbar bleiben.
- Die Prioritätslogik ist bewusst einfach und organisationsspezifische SLA-/CMDB-Daten sind nicht enthalten.
- Das Skript führt keinen Abgleich mit Intune oder Entra ID durch. Ein solcher Cross-Service-Abgleich sollte als separater Case mit eigenen Berechtigungen umgesetzt werden.
- Die API hat dokumentierte Rate Limits; dieses Skript verwendet für den Inventory-Call `$top=10000`, um unnötige Requests zu vermeiden.

## Rollback / Rückbau

Da keine Änderungen vorgenommen werden, gibt es keinen technischen Rollback. Zum Rückbau:

1. geplanten Job entfernen,
2. erzeugte CSV-Dateien gemäß eigener Retention löschen,
3. falls eigens für diesen Report erstellt, App-Berechtigung bzw. App-Registrierung kontrolliert entfernen.

## Quellen

Geprüft am **17. September 2026**:

- Microsoft Learn – List machines API: https://learn.microsoft.com/en-us/defender-endpoint/api/get-machines
- Microsoft Learn – Machine resource type: https://learn.microsoft.com/en-us/defender-endpoint/api/machine
- Microsoft Learn – Access the Microsoft Defender for Endpoint APIs: https://learn.microsoft.com/en-us/defender-endpoint/api/apis-intro
- Microsoft Learn – Offboard devices: https://learn.microsoft.com/en-us/defender-endpoint/offboard-machines
- Microsoft Learn – Defender for Endpoint data storage and privacy / retention logic: https://learn.microsoft.com/en-us/defender-vulnerability-management/retention-logic-mdvm

## Praxisempfehlung

Für einen produktiven Betrieb eignet sich der Report als täglicher oder wöchentlicher Kontrollpunkt. Besonders wertvoll ist die Kombination aus `lastSeen`, Sensorzustand und Risk/Exposure: Ein bewusst ausgemustertes Gerät kann per Tag ausgeschlossen werden, während ein aktives oder kürzlich gesehenes Gerät mit `ImpairedCommunication`, `NoSensorData` oder hohem Exposure priorisiert zur Prüfung gelangt.
