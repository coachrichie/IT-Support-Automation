# Scheduled Task Health Audit

Read-only PowerShell-Audit für geplante Aufgaben auf Windows Servern. Das Skript liest Definitionen und Laufzeitinformationen, bewertet typische Support-Signale und erzeugt CSV plus Logdatei. Es startet, stoppt, aktiviert, deaktiviert oder verändert keine Aufgabe.

## Zweck und Support-Case

Geplante Aufgaben übernehmen häufig Backups, Exporte, Inventarisierung, Bereinigung oder Schnittstellenläufe. Ein Dienst kann dabei formal vorhanden sein, obwohl der letzte Lauf fehlschlug oder seit Wochen nicht mehr stattfand. Der Audit schafft eine konsolidierte Sicht auf:

- fehlgeschlagene letzte Läufe,
- Aufgaben ohne bisherigen Lauf,
- veraltete letzte Ausführungen,
- deaktivierte oder laufende Aufgaben,
- Task-Scheduler-Informationszustände,
- einzelne Lese- oder Verbindungsfehler.

## Voraussetzungen

- Windows PowerShell 5.1 oder PowerShell 7 mit Windows-Kompatibilität
- Windows-Modul `ScheduledTasks`
- für entfernte Systeme: erreichbares CIM/WS-Man, passende Firewallregeln und Namensauflösung
- Schreibrecht nur auf den gewählten lokalen Ausgabeordner

## Rollen und minimale Berechtigungen

Das Skript verwendet ausschließlich `Get-ScheduledTask` und `Get-ScheduledTaskInfo`. Das ausführende Konto benötigt Leserechte auf die relevanten Aufgaben. Für geschützte Aufgaben oder Remotezugriffe können erhöhte Rechte bzw. eine passende lokale Delegierung nötig sein. Verwenden Sie kein Domänen-Administratorkonto, wenn ein dediziertes Lesekonto oder eine begrenzte Just-Enough-Administration ausreicht.

## Parameter

| Parameter | Standard | Bedeutung |
|---|---|---|
| `ComputerName` | lokaler Computer | Ein oder mehrere Zielsysteme |
| `TaskPathFilter` | `*` | Wildcard-Filter für den Aufgabenpfad |
| `TaskNameFilter` | `*` | Wildcard-Filter für den Aufgabennamen |
| `StaleAfterDays` | `30` | Alter des letzten Laufs, ab dem `Stale-LastRun` gesetzt wird |
| `IncludeMicrosoftTasks` | aus | Bezieht Aufgaben unter `\Microsoft\` ein |
| `ExcludeDisabled` | aus | Blendet deaktivierte Aufgaben aus |
| `OutputDirectory` | `./Reports` | Ziel für CSV und Logdatei |

## Beispiele

Lokaler Audit mit sicheren Standardwerten:

```powershell
./Get-ScheduledTaskHealthAudit.ps1
```

Mehrere Server und nur den Betriebsordner prüfen:

```powershell
./Get-ScheduledTaskHealthAudit.ps1 `
  -ComputerName 'SERVER01','SERVER02' `
  -TaskPathFilter '\Operations\*' `
  -StaleAfterDays 14 `
  -OutputDirectory 'C:\Reports\TaskAudit'
```

Microsoft-Aufgaben ausdrücklich einbeziehen:

```powershell
./Get-ScheduledTaskHealthAudit.ps1 -IncludeMicrosoftTasks -ExcludeDisabled
```

## Statuswerte

- `Healthy`: letzter Ergebniscode `0` und Lauf nicht veraltet
- `Failed`: nicht erfolgreicher Ergebniscode, der kein dokumentierter Scheduler-Informationszustand ist
- `Stale-LastRun`: letzter Lauf liegt hinter der konfigurierten Schwelle
- `Never-Run`: kein plausibler letzter Lauf vorhanden
- `Running`: Aufgabe läuft aktuell
- `Disabled`: Aufgabe ist deaktiviert
- `Scheduler-State`: dokumentierter Task-Scheduler-Informationscode, zum Beispiel „queued“
- `Collection-Error`: einzelne Aufgabe konnte nicht gelesen werden
- `Computer-Error`: Zielsystem oder CIM-Sitzung konnte nicht gelesen werden

`LastTaskResult` wird zusätzlich als achtstelliger Hexwert ausgegeben. Ein auffälliger Code ist ein Diagnosehinweis; er ersetzt nicht die Aufgaben-Historie, das Anwendungslog oder die Prüfung des aufgerufenen Programms.

## Logging und Fehlerbehandlung

Jeder Lauf erzeugt eine UTF-8-Logdatei. Fehler bei einer Aufgabe werden als `Collection-Error` protokolliert, ohne die restlichen Aufgaben des Servers zu überspringen. Ein nicht erreichbarer Server wird als `Computer-Error` im Report erfasst; anschließend verarbeitet das Skript weitere Zielsysteme. Temporäre CIM-Sitzungen werden im `finally`-Block entfernt.

## Validierung

1. Zuerst mit einem einzelnen Testserver und engem Pfadfilter ausführen.
2. `Computer-Error` und `Collection-Error` vor der fachlichen Bewertung klären.
3. `Failed`-Zeilen mit der Aufgaben-Historie und dem Log der gestarteten Anwendung vergleichen.
4. Schwelle für `StaleAfterDays` gegen den tatsächlichen Zeitplan der Aufgabe prüfen.
5. Stichproben in der Aufgabenplanung gegen `Last Run Time`, `Next Run Time` und `Last Run Result` abgleichen.

## Sicherheit

- Standardmäßig read-only; keine Cmdlets mit `Set`, `Start`, `Stop`, `Enable`, `Disable`, `Register` oder `Unregister`.
- Keine eingebetteten Kennwörter, Tokens, Kunden-, Domänen- oder Serverdaten.
- Microsoft-Aufgaben sind standardmäßig ausgeschlossen, um Rauschen und unnötige Detailoffenlegung zu reduzieren.
- Reports enthalten interne Server-, Pfad- und Aufgabennamen und müssen entsprechend geschützt, aufbewahrt und gelöscht werden.
- Remotezugriff sollte verschlüsselt, segmentiert und auf die benötigten Zielsysteme begrenzt sein.

## Einschränkungen

- Ein Ergebniscode `0` beweist nicht, dass das fachliche Ergebnis korrekt ist.
- Unterschiedliche Aufgaben verwenden eigene Exitcodes; diese müssen mit der jeweiligen Anwendung dokumentiert werden.
- Ereignisbasierte oder selten laufende Aufgaben können bewusst als `Never-Run` oder `Stale-LastRun` erscheinen.
- Aufgabenhistorie und Eventlogs werden nicht ausgelesen.
- Clustered Scheduled Tasks sind nicht Bestandteil dieses Audits.
- Erreichbarkeit und Leserechte können je Aufgabenordner variieren.

## Rollback / Rückbau

Da keine Aufgaben verändert werden, ist kein technischer Rollback erforderlich. Zum Rückbau werden ausschließlich die erzeugten CSV- und Logdateien gemäß interner Aufbewahrungsrichtlinie gelöscht. Eine spätere Remediation muss separat freigegeben, dokumentiert und getestet werden.

## Quellen

- [Get-ScheduledTask](https://learn.microsoft.com/en-us/powershell/module/scheduledtasks/get-scheduledtask?view=windowsserver2022-ps)
- [Get-ScheduledTaskInfo](https://learn.microsoft.com/en-us/powershell/module/scheduledtasks/get-scheduledtaskinfo?view=windowsserver2019-ps)
- [ScheduledTasks module](https://learn.microsoft.com/en-us/powershell/module/scheduledtasks/?view=windowsserver2025-ps)
- [Task Scheduler error and success constants](https://learn.microsoft.com/en-us/windows/win32/taskschd/task-scheduler-error-and-success-constants)
- [Troubleshoot scheduled tasks not running](https://learn.microsoft.com/en-us/troubleshoot/windows-server/system-management-components/troubleshoot-scheduled-tasks-not-running)
