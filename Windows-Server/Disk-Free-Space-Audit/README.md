# Windows Server Disk Free Space Audit

Read-only PowerShell-Audit für freien Speicherplatz lokaler logischer Laufwerke auf Windows Servern. Das Skript liest `Win32_LogicalDisk`, priorisiert knappe Kapazität und schreibt CSV, JSON und Log. Es bereinigt und verändert keine Laufwerke.

## Zweck und Support-Case

Im First-/Second-Level-Support fallen volle System- oder Datenlaufwerke oft erst durch fehlgeschlagene Updates, Backups oder Anwendungen auf. Der Audit erfasst pro Server Größe, freien Speicher in GiB und freien Anteil. Standardmäßig gilt **Warning bei höchstens 15 %** und **Critical bei höchstens 5 %** freiem Speicher. Die Schwellen sind anpassbar und müssen zum Workload passen.

## Voraussetzungen und Module

- Windows PowerShell 5.1 oder PowerShell 7 auf Windows für Live-Abfragen.
- Integriertes Modul `CimCmdlets`; keine Zusatzmodule.
- Für Remoteziele: erreichbares CIM/WS-Man, Namensauflösung und passende Firewallregeln.
- Schreibrecht auf den lokalen Ausgabeordner. Offline-JSON-Tests brauchen keine Serververbindung.

## Rollen und minimale Berechtigungen

Das ausführende Konto benötigt Lesezugriff auf `Win32_LogicalDisk` im Namensraum `root/cimv2`. Bei Remoteabfragen sind passende WMI/CIM-Berechtigungen erforderlich. Die konkrete Delegierung hängt von der lokalen Sicherheitskonfiguration ab. Ein eingeschränktes Lesekonto ist vorzuziehen; Domänenadministration und Schreibrechte auf Zielvolumes sind für diesen Audit nicht nötig.

## Parameter

| Parameter | Standard | Bedeutung |
|---|---|---|
| `ComputerName` | lokaler Computer | Ein oder mehrere Zielserver; bei Offline-JSON ohne Computernamen wird der erste Name verwendet |
| `WarningFreePercent` | `15` | Warnung bei freiem Anteil kleiner/gleich diesem Wert |
| `CriticalFreePercent` | `5` | Kritisch bei freiem Anteil kleiner/gleich diesem Wert; muss kleiner als Warnschwelle sein |
| `OutputDirectory` | `./Reports` | Lokaler Ausgabeordner für CSV, JSON und Log |
| `InputJsonPath` | keiner | Testdaten statt Live-CIM-Abfrage |

## Beispiele

```powershell
./Get-DiskFreeSpaceAudit.ps1
./Get-DiskFreeSpaceAudit.ps1 -ComputerName 'SERVER01','SERVER02' -WarningFreePercent 20 -CriticalFreePercent 8 -OutputDirectory './Reports'
./Get-DiskFreeSpaceAudit.ps1 -InputJsonPath './sample-disks.json' -ComputerName 'SERVER01'
```

Synthetische Offline-Datei:

```json
[{"ComputerName":"SERVER01","DeviceID":"C:","DriveType":3,"VolumeName":"System","FileSystem":"NTFS","Size":107374182400,"FreeSpace":4294967296}]
```

## Logging, Fehlerbehandlung und Validierung

Jeder Lauf schreibt `DiskFreeSpaceAudit-*.csv`, `.json` und `.log` mit UTC-Zeitstempel. Verbindungsfehler einzelner Server erscheinen als `CollectionError`; ungültige Größen als `InvalidData`. Bei fehlenden Laufwerken erscheint `NoLocalDisks`. Ungültige Schwellen, leere Offline-Daten und Schreibfehler beenden den Lauf mit Fehler. Das Log enthält Zeit, Anzahl, auffällige Zeilen und Dateipfade. CIM-Fehlermeldungen können Zielnamen enthalten; Berichte geschützt ablegen.

Zur Validierung zuerst die synthetische JSON-Datei nutzen: 4 GiB von 100 GiB frei muss `Critical` ergeben. Danach lokale Werte mit `Get-CimInstance Win32_LogicalDisk -Filter 'DriveType = 3'` vergleichen. CSV, JSON und Log auf Vollständigkeit prüfen. Remotezugriff separat mit einem bekannten Testserver prüfen.

## Sicherheit und Einschränkungen

- Keine Löschung, Komprimierung, Bereinigung oder Änderung an Volumes.
- `Win32_LogicalDisk` mit `DriveType = 3` erfasst lokale logische Laufwerke mit Laufwerksbuchstaben. Mountpunkte ohne eigenen Buchstaben, Cluster Shared Volumes und Storage-Pool-Kapazität brauchen separate Prüfungen.
- Die Prozentgrenzen allein berücksichtigen keine Wachstumsrate oder Mindestreserve in GiB. Große Volumes und Anwendungen mit festen Mindestanforderungen benötigen ergänzende Betriebsregeln.
- Offline-JSON ist eine Testquelle und keine verifizierte Live-Messung.

## Rollback und Rückbau

Da das Skript nur liest, ist kein Server-Rollback nötig. Lokale Berichte nach den geltenden Aufbewahrungsregeln entfernen. Fehlalarme durch angepasste Schwellen oder zusätzliche Workload-Prüfungen klären und erneut ausführen.

## Quellen

- [Microsoft: Win32_LogicalDisk](https://learn.microsoft.com/en-us/windows/win32/cimwin32prov/win32-logicaldisk)
- [Microsoft: Get-CimInstance](https://learn.microsoft.com/en-us/powershell/module/cimcmdlets/get-ciminstance)
