# Microsoft 365 License Assignment Error Audit

## Problemstellung

Fehlerhafte direkte oder gruppenbasierte Lizenzzuweisungen können dazu führen, dass Benutzer benötigte Microsoft-365-Dienste nicht erhalten. Typische Ursachen sind fehlende verfügbare Lizenzen, kollidierende Service Plans, fehlende Abhängigkeiten, Proxy-Adressprobleme oder ungültige bzw. fehlende Usage Locations.

Dieses Audit-Skript wertet tenantweit die `licenseAssignmentStates` aller Benutzer aus und erzeugt einen prüfbaren CSV-Report. Es verändert keine Lizenzen, Benutzer, Gruppen oder Usage Locations.

## Nutzen

- tenantweiter Überblick über Lizenzzuweisungsfehler
- Unterscheidung zwischen direkter und gruppenbasierter Zuweisung
- Auflösung der verursachenden Gruppe bei gruppenbasierter Lizenzierung
- Anzeige von SKU, Fehler, ErrorSubcode und letztem Aktualisierungszeitpunkt
- Kennzeichnung fehlender `UsageLocation`
- geeignet für Service Desk, Problem Management, Lizenzmanagement und Change Control

## Voraussetzungen

- PowerShell 7 empfohlen
- Microsoft Graph PowerShell SDK
- mindestens folgende Module:
  - `Microsoft.Graph.Authentication`
  - `Microsoft.Graph.Users`
  - `Microsoft.Graph.Identity.DirectoryManagement`
  - `Microsoft.Graph.Groups`

Beispielinstallation:

```powershell
Install-Module Microsoft.Graph -Scope CurrentUser
```

## Berechtigungen

Das Skript nutzt delegierte Microsoft-Graph-Berechtigungen:

- `User.Read.All`
- `Directory.Read.All`
- `Organization.Read.All`

Microsoft dokumentiert `LicenseAssignment.Read.All` als Least-Privilege-Berechtigung für `subscribedSkus`; das offizielle PowerShell-Beispiel zur tenantweiten Ermittlung von Lizenzierungsfehlern verwendet `User.Read.All`, `Directory.Read.All` und `Organization.Read.All`.

Je nach Tenant-Konfiguration benötigt das angemeldete Konto zusätzlich eine geeignete Entra-Rolle, z. B. Global Reader oder Directory Reader.

## Verwendung

Standardmäßig werden nur fehlerhafte Lizenzzuweisungen ausgegeben:

```powershell
./Get-M365LicenseAssignmentErrorAudit.ps1
```

Eigener Exportpfad:

```powershell
./Get-M365LicenseAssignmentErrorAudit.ps1 -OutputPath C:\Reports\M365-LicenseErrors.csv
```

Auch erfolgreiche Zuweisungszustände anzeigen:

```powershell
./Get-M365LicenseAssignmentErrorAudit.ps1 -IncludeSuccessfulAssignments
```

Nur Ausgabe in der Konsole / Pipeline, kein CSV-Export:

```powershell
./Get-M365LicenseAssignmentErrorAudit.ps1 -NoExport
```

## Reportfelder

Der Report enthält u. a.:

- `DisplayName`
- `UserPrincipalName`
- `UserId`
- `UsageLocation`
- `MissingUsageLocation`
- `SkuId`
- `SkuPartNumber`
- `AssignmentType`
- `AssignedByGroupId`
- `AssignedByGroupName`
- `State`
- `Error`
- `ErrorSubcode`
- `LastUpdatedDateTime`
- `DisabledPlans`

## Funktionsweise

1. Verbindung mit Microsoft Graph
2. Laden aller abonnierten SKUs
3. Laden aller Benutzer inklusive `licenseAssignmentStates`
4. Filtern auf `State = Error`, sofern nicht anders angegeben
5. Auflösung der verursachenden Gruppe bei gruppenbasierter Zuweisung
6. Kennzeichnung fehlender Usage Locations
7. CSV-Export und strukturierte Ausgabe

## Fehlerbehandlung und Logging

Das Skript nutzt `$ErrorActionPreference = 'Stop'`, prüft erforderliche Module, protokolliert Warnungen bei nicht auflösbaren Gruppen und bricht bei unerwarteten Graph-Fehlern kontrolliert ab.

## Sicherheit

Die Lösung ist vollständig read-only:

- keine Lizenz wird zugewiesen oder entfernt
- keine Gruppe wird verändert
- keine Usage Location wird gesetzt
- kein automatisches Reprocessing wird ausgelöst

Damit eignet sich das Skript als Vorstufe für einen später separat genehmigten Remediation-Prozess.

## Bekannte Einschränkungen

- Gruppenbasierte Lizenzierung unterstützt keine verschachtelten Gruppen für die Vererbung von Lizenzen.
- Bei sehr großen Tenants kann das Laden aller Benutzer entsprechend dauern.
- Die Interpretation einzelner `Error`- und `ErrorSubcode`-Werte sollte gegen die aktuelle Microsoft-Dokumentation geprüft werden.
- Das Skript behebt Fehler bewusst nicht automatisch.

## Rollback / Rückbau

Da das Skript ausschließlich liest und Reports erzeugt, ist kein technischer Rollback erforderlich. Zum Rückbau genügt das Entfernen des Skripts und erzeugter CSV-Dateien.

## Quellen

- Microsoft Learn: PowerShell examples for group-based licensing  
  https://learn.microsoft.com/en-us/entra/identity/users/licensing-powershell-graph-examples
- Microsoft Learn: licenseAssignmentState resource type  
  https://learn.microsoft.com/en-us/graph/api/resources/licenseassignmentstate?view=graph-rest-1.0
- Microsoft Learn: Assign or unassign licenses to a group in the Microsoft 365 admin center  
  https://learn.microsoft.com/en-us/entra/identity/users/licensing-groups-assign
- Microsoft Learn: List subscribedSkus  
  https://learn.microsoft.com/en-us/graph/api/subscribedsku-list?view=graph-rest-1.0

Stand der Quellenprüfung: 2026-09-29.
