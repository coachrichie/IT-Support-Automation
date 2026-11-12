# Windows Server Service Health Audit

Lesender PowerShell-Audit für Windows-Dienste auf lokalen und entfernten Servern. Er liefert CSV, JSON und ein knappes Log; er startet, stoppt oder konfiguriert keinen Dienst.

## Zweck und Support-Case

Im First- und Second-Level-Support sollen ausgefallene automatische Dienste und ausdrücklich erwartete, aber fehlende Dienste schnell auffallen. Der Audit wertet `Win32_Service.State` und `StartMode` aus. Eine automatische Startart bei einem anderen Zustand als `Running` wird als `AutomaticNotRunning` markiert. `Disabled`, Übergangszustände und gestoppte manuelle Dienste werden getrennt ausgewiesen. Die Bewertung ersetzt keine fachliche Prüfung: ein Dienst kann absichtlich gestoppt sein.

## Voraussetzungen und Module

- Windows PowerShell 5.1 oder PowerShell 7 auf Windows für Live-Abfragen; `CimCmdlets` als integriertes Modul.
- Für Remoteziele: erreichbares WS-Man/CIM, Namensauflösung und passende Firewallregeln.
- Für Offline-Tests reicht PowerShell mit `ConvertFrom-Json`; es findet keine Serververbindung statt.
- Schreibrecht auf den lokalen Ausgabeordner. Es werden keine Zusatzmodule benötigt.

## Rollen und minimale Berechtigungen

Das ausführende Konto benötigt nur Leserecht auf die Dienstinformationen der Zielsysteme. Remote-CIM erfordert eine für WMI/CIM-Abfragen berechtigte Identität; die konkrete Delegierung hängt von der lokalen Sicherheitskonfiguration ab. Nach Möglichkeit ein dediziertes, eingeschränktes Lesekonto nutzen. Keine Dienststeuerungsrechte und keine Domänenadministration für den Audit vergeben.

## Parameter

| Parameter | Standard | Bedeutung |
|---|---|---|
| `ComputerName` | lokaler Computer | Ein oder mehrere Ziele; bei JSON-Eingabe zur Prüfung erwarteter Namen |
| `ServiceName` | `*` | Dienstnamen oder Wildcards; exakte fehlende Namen werden gemeldet |
| `OutputDirectory` | `./Reports` | Lokaler Ordner für CSV, JSON und Log |
| `InputJsonPath` | keiner | Offline-Eingabe statt Live-Abfrage |

## Beispiele

```powershell
./Get-ServiceHealthAudit.ps1
./Get-ServiceHealthAudit.ps1 -ComputerName 'SERVER01','SERVER02' -ServiceName 'W32Time','WinRM' -OutputDirectory './Reports'
./Get-ServiceHealthAudit.ps1 -InputJsonPath './sample-services.json' -ComputerName 'SERVER01' -ServiceName 'W32Time','WinRM'
```

Eine Offline-JSON-Datei enthält ein Array von Objekten mit `ComputerName`, `Name`, `DisplayName`, `State` und `StartMode`. Beispiel ohne echte Systemdaten:

```json
[{"ComputerName":"SERVER01","Name":"W32Time","DisplayName":"Windows Time","State":"Stopped","StartMode":"Automatic"}]
```

## Logging und Fehlerbehandlung

Jeder Lauf schreibt eindeutig datierte Dateien `ServiceHealthAudit-*.csv`, `.json` und `.log`. Verbindungs- oder Leseprobleme je Ziel erscheinen als `CollectionError` im Bericht. Ungültige Offline-Datensätze und Fehler beim Schreiben beenden den Lauf mit Fehler. Das Log enthält Zeit, Anzahl, Anzahl auffälliger Einträge und Dateipfade. Es werden weder Anmeldedaten noch Tokens geschrieben. Fehlermeldungen von CIM können jedoch Zielnamen und Infrastrukturdetails enthalten; Berichte entsprechend schützen.

## Validierung

1. Zuerst mit einer synthetischen JSON-Datei testen; `Stopped` + `Automatic` muss `AutomaticNotRunning` ergeben.
2. Mit einem bekannten Dienstnamen lokal ausführen und `State` und `StartMode` gegen `Get-CimInstance Win32_Service` vergleichen.
3. Bei Remotezielen Verbindungsfehler und Berechtigungen prüfen, bevor Findings bewertet werden.
4. CSV, JSON und Log auf Vollständigkeit und Schreibrechte prüfen.

## Sicherheit und Einschränkungen

- Keine automatische Remediation, kein `Start-Service`, kein `Set-Service` und keine Änderungen an Remotezielen.
- Die Standardausgabe kann viele Dienste enthalten; für geplante Kontrollen `ServiceName` einschränken.
- `AutomaticNotRunning` ist ein Prüfsignal, keine definitive Störung. Delayed-Auto-Start und temporäre Übergänge können die Einordnung beeinflussen.
- Exakte Namen, die auf einem Ziel nicht sichtbar sind, können auch durch unzureichende Leserechte fehlen.
- Offline-JSON ist eine Testquelle, keine verifizierte Live-Aussage.

## Rollback und Rückbau

Da keine Dienst- oder Serverkonfiguration geändert wird, ist kein technischer Rollback nötig. Lokale Berichte können nach den geltenden Aufbewahrungsregeln gelöscht werden. Fehlerhafte Findings durch korrigierte Ziel- oder Dienstfilter erneut prüfen.

## Quellen

- [Microsoft: Win32_Service class](https://learn.microsoft.com/en-us/windows/win32/cimwin32prov/win32-service)
- [Microsoft: Get-CimInstance](https://learn.microsoft.com/en-us/powershell/module/cimcmdlets/get-ciminstance)
