# Windows Server Pending Reboot Signal Audit

Read-only PowerShell-Audit für lokale Windows-Server-Neustartsignale vor Wartung, Updates und Change-Freigaben. Das Skript liest vier Registry-Indikatoren und erzeugt CSV, JSON und Log. Es löst keinen Neustart aus und verändert keine Registry-Werte.

## Zweck und Support-Case

Ein ausstehender Neustart kann Installationen, Patches und Supportdiagnosen beeinflussen. Der Audit unterscheidet starke Signale aus Component Based Servicing, Windows Update und einem ausstehenden Computernamenwechsel von bloßen geplanten Dateioperationen. `PendingFileRenameOperations` allein wird als `ReviewFileOperations` gemeldet, weil solche Einträge nicht immer einen sofort erforderlichen Neustart bedeuten. Kann ein Signal nicht gelesen werden, bleibt das Ergebnis `Unknown`, sofern kein starkes Signal bereits `Pending` ergibt. `Clear` bedeutet nur, dass diese vier Signale nicht gesetzt waren.

## Voraussetzungen und Module

- Windows PowerShell 5.1 oder PowerShell 7 auf Windows für die Live-Prüfung.
- Integrierter Registry-Provider; keine Zusatzmodule.
- Lokale Ausführung auf dem Zielserver. Für mehrere Server das Skript mit vorhandener, organisatorisch freigegebener Remote-Ausführung je Ziel starten.
- Schreibrecht nur auf den gewählten lokalen Ausgabeordner. Offline-JSON-Tests benötigen keinen Registry-Zugriff.

## Rollen und minimale Berechtigungen

Das Konto benötigt Leserecht auf die genannten HKLM-Schlüssel und Schreibrecht auf den lokalen Ausgabeordner. Eine Administratorrolle ist nicht pauschal erforderlich; tatsächliche Rechte hängen von der lokalen Registry-ACL ab. Keine Rechte zum Ändern der Registry oder Neustarten des Servers nötig. Bei unlesbaren Schlüsseln erscheint `Unknown` statt einer Entwarnung.

## Parameter

| Parameter | Standard | Bedeutung |
|---|---|---|
| `OutputDirectory` | `./Reports` | Ziel für CSV, JSON und Log |
| `InputJsonPath` | keiner | Synthetisches Signalobjekt statt lokaler Registry |

## Beispiele

```powershell
./Get-PendingRebootSignalAudit.ps1 -OutputDirectory './Reports'
./Get-PendingRebootSignalAudit.ps1 -InputJsonPath './sample-signals.json' -OutputDirectory './Reports'
```

Synthetischer Offline-Datensatz:

```json
{"ComputerName":"SERVER01","ComponentServicing":false,"WindowsUpdate":true,"ComputerRename":false,"PendingFileRename":false}
```

Alle vier Signalwerte müssen `true`, `false` oder `null` sein. `null` steht für nicht lesbar/unbekannt. Das Skript gibt genau eine Ergebniszeile pro Lauf zurück.

## Logging, Fehlerbehandlung und Validierung

Ein Lauf schreibt `PendingRebootSignalAudit-*.csv`, `.json` und `.log` mit UTC-Zeitstempel. Das Log enthält nur Zeit, Computername, Status und Dateipfade; Inhalte geplanter Dateioperationen werden nicht gespeichert. Ungültige Offline-Daten und Schreibfehler beenden den Lauf mit Fehler. Zugriffsprobleme bei Registry-Lesevorgängen führen zu unbekannten Signalen und damit zu `Unknown`, falls kein starkes Signal gesetzt ist.

Vor dem produktiven Einsatz die vier Statusfälle mit synthetischen Daten prüfen: starkes Signal → `Pending`; nur Dateioperationen → `ReviewFileOperations`; unbekanntes Signal → `Unknown`; alle falsch → `Clear`. Danach auf einem Testserver mit bekanntem Wartungszustand ausführen und die Signale mit der lokalen Update-/Servicing-Diagnose vergleichen. CSV, JSON und Log auf Vollständigkeit prüfen.

## Sicherheit und Einschränkungen

- Keine Neustarts, keine Registry-Änderungen und keine automatische Freigabe von Updates.
- Die Prüfung ist eine Momentaufnahme. Weitere Produkte oder Installer können Neustarts verlangen, ohne eines dieser vier Signale zu setzen.
- `PendingFileRenameOperations` kann auch harmlose, später ausführbare Operationen enthalten. Rohpfade werden aus Datenschutz- und Sicherheitsgründen nicht protokolliert.
- `Clear` ist keine Garantie, dass jede Anwendung ohne Neustart installiert oder aktualisiert werden kann.
- Die Live-Prüfung ist lokal; eine zentrale Ausführung braucht eine separate, abgesicherte Orchestrierung.

## Rollback und Rückbau

Da keine Systemänderung erfolgt, ist kein Server-Rollback nötig. Lokale Berichte nach den geltenden Aufbewahrungsregeln löschen. Bei falscher Einordnung die Signale und Herstellerhinweise im Change-Verfahren prüfen; keine Registry-Werte blind entfernen.

## Quellen

- [Microsoft: Check for pending reboot](https://learn.microsoft.com/en-us/powershell/dsc/reference/resources/microsoft/windows/rebootpending/examples/check-for-pending-reboot?view=dsc-3.0)
- [Microsoft: Windows Server Update Troubleshooting](https://learn.microsoft.com/en-us/troubleshoot/windows-server/deployment/troubleshoot-windows-server-update-guidance)
- [Microsoft: PendingFileRenameOperations](https://learn.microsoft.com/en-us/windows/win32/vss/registry-backup-and-restore-operations-under-vss)
