# Azure Unattached Managed Disk Audit

## Problemstellung

Nach dem Löschen oder Umbauen einer Azure-VM können Managed Disks absichtlich bestehen bleiben. Microsoft dokumentiert, dass nicht angehängte Disks weiterhin Speicherkosten verursachen, bis sie gelöscht werden. Ein regelmäßiger Audit reduziert Kosten, ohne automatisiert Daten zu löschen.

Diese Lösung ist bewusst **read-only**: Sie findet Kandidaten, erzeugt einen CSV-Report und führt **kein `Remove-AzDisk`** aus.

## Funktionsweise

Das Skript liest Managed Disks über `Get-AzDisk`. Eine Disk gilt als unattached, wenn `ManagedBy` leer ist. Wenn `LastOwnershipUpdateTime` verfügbar ist, wird daraus die Dauer seit der letzten Ownership-Änderung berechnet. Standardmäßig werden nur Disks gemeldet, die mindestens 30 Tage unattached sind.

Disks mit Schutz-Tags `DoNotDelete`, `Keep` oder `ASRReplica` werden standardmäßig ausgeschlossen. Das ist insbesondere für Sonderfälle wie Azure Site Recovery sinnvoll: Replikat-Disks können technisch unattached erscheinen und trotzdem benötigt werden.

## Voraussetzungen

- PowerShell 7 empfohlen
- Module `Az.Accounts` und `Az.Compute` (alternativ Gesamtmodul `Az`)
- Azure-Anmeldung über `Connect-AzAccount` oder bereits vorhandener Az-Kontext
- mindestens Leseberechtigung auf die zu prüfenden Subscriptions/Resource Groups, z. B. Azure RBAC `Reader`

Installation:

```powershell
Install-Module Az -Scope CurrentUser
```

## Nutzung

Standardaudit der aktuellen Subscription, mindestens 30 Tage unattached:

```powershell
./Get-AzureUnattachedManagedDiskAudit.ps1
```

Nur eine Resource Group:

```powershell
./Get-AzureUnattachedManagedDiskAudit.ps1 -ResourceGroupName 'rg-production'
```

Mehrere Subscriptions und 60-Tage-Schwelle:

```powershell
./Get-AzureUnattachedManagedDiskAudit.ps1 -SubscriptionId '00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000002' -MinimumUnattachedDays 60
```

Auch Disks ohne `LastOwnershipUpdateTime` als Review-Kandidaten aufnehmen:

```powershell
./Get-AzureUnattachedManagedDiskAudit.ps1 -IncludeUnknownAge
```

Nur Konsolenausgabe:

```powershell
./Get-AzureUnattachedManagedDiskAudit.ps1 -NoExport
```

## Reportfelder

Der CSV-Report enthält u. a. Subscription, Resource Group, Diskname, Region, DiskState, SKU, Größe, `LastOwnershipUpdateTime`, berechnete `UnattachedDays`, OS-Typ, Verschlüsselung, Tags und Resource ID.

## Sichere Defaults und Idempotenz

- keinerlei Delete-/Detach-/Update-Aufrufe
- 30 Tage Mindestalter statt sofortiger Meldung jeder temporär unattached Disk
- unbekanntes Unattached-Alter wird standardmäßig nicht als Kandidat ausgegeben
- bekannte Schutz-Tags werden standardmäßig ausgeschlossen
- wiederholte Ausführung verändert keine Azure-Ressourcen

## Validierung vor einer späteren Bereinigung

Vor jeder manuellen Löschung muss geprüft werden, ob die Disk noch für Backup, Restore, Migration, Azure Site Recovery, Forensik, Test/Dev oder geplante Wiederverwendung benötigt wird. Microsoft empfiehlt ausdrücklich, unattached Disks zuerst zu prüfen und erst anschließend zu löschen.

`ManagedBy = null` ist ein starkes technisches Signal, aber allein keine Freigabe zur Löschung.

## Sicherheitsaspekte

Das Skript benötigt nur lesenden Azure-Zugriff. Für geplante Ausführung sollte ein Managed Identity- oder Service-Principal-Konzept mit Least Privilege verwendet werden. Reports können Ressourcennamen und Infrastruktur-Metadaten enthalten und sollten entsprechend geschützt werden.

## Bekannte Einschränkungen

- Das Skript bewertet Managed Disks, keine historischen unmanaged VHDs. Microsoft hat unmanaged disks am 31. März 2026 vollständig eingestellt.
- `LastOwnershipUpdateTime` kann bei neu erstellten Disks leer sein, bis sich ihr Zustand erstmals ändert.
- Kosten werden nicht berechnet; Preis hängt u. a. von SKU, Größe, Region und Vertragsmodell ab.
- Sonderworkloads können unattached Disks absichtlich verwenden. Azure Site Recovery ist ein dokumentiertes Beispiel.
- Schutz-Tags sind organisatorische Konventionen und müssen ggf. an die eigene Umgebung angepasst werden.

## Rollback / Rückbau

Da keine Azure-Ressource verändert wird, ist kein technischer Rollback notwendig. Zum Rückbau lediglich Skript, Reports und ggf. den geplanten Task bzw. Automation-Job entfernen.

## Quellen

Geprüft am 23.09.2026:

- Microsoft Learn: Find and delete unattached Azure managed and unmanaged disks — https://learn.microsoft.com/en-us/azure/virtual-machines/windows/find-unattached-disks
- Microsoft Learn: Tutorial - Manage Azure disks with Azure PowerShell — https://learn.microsoft.com/en-us/azure/virtual-machines/windows/tutorial-manage-data-disk
- Microsoft Learn: Migrate unmanaged disks to managed disks — https://learn.microsoft.com/azure/virtual-machines/unmanaged-disks-deprecation
- Microsoft Q&A: ASR replication disks can appear in Advisor as unattached — https://learn.microsoft.com/en-us/answers/questions/1181441/should-advisor-recommendations-include-unattached

## Praxisnutzen

Der Report eignet sich als wiederkehrender FinOps-/Operations-Check, als Input für Change Control und als sichere Vorstufe zu einem später separat freizugebenden Cleanup-Prozess.