# Azure Storage Network Exposure Audit

## Zweck und Support-Fall

Dieses Skript inventarisiert die Netzwerkfreigabe von Azure Storage Accounts im aktuell ausgewählten Abonnement. Es hilft dem Second-Level-Support und Systems Engineering, Accounts mit öffentlichem Endpunkt und `DefaultAction=Allow` für eine manuelle Prüfung zu priorisieren. Es liest ausschließlich Konfigurationen; es ändert weder Firewallregeln noch Daten.

Die Klassifikation ist ein **Review-Signal**, keine Aussage, dass Daten anonym erreichbar sind. Netzwerkzugang und Datenberechtigung sind getrennte Kontrollen. Network Security Perimeter und weitere Zugriffspfade können die tatsächliche Erreichbarkeit verändern.

## Voraussetzungen, Module und Berechtigungen

- PowerShell 7.2 oder neuer.
- Module `Az.Accounts` und `Az.Storage` mit den Befehlen `Get-AzContext` und `Get-AzStorageAccount`.
- Angemeldeter Azure-Kontext und vorab bewusst gewähltes Abonnement.
- Azure-Rolle **Reader** auf Abonnementebene, damit alle Storage Accounts gelesen werden können. Das Skript listet das ganze gewählte Abonnement auf und bietet keine Resource-Group-Einschränkung.
- Schreibrechte auf dem lokalen Ausgabeordner. Es sind keine Data-Plane-Rechte, Kontoschlüssel, Storage Blob Data Reader oder Contributor-Rechte erforderlich.

`Reader and Data Access` ist ausdrücklich **nicht** erforderlich; diese Rolle kann Storage-Schlüssel lesen und ist für diesen Audit zu weitreichend.

## Parameter und Ausgabe

| Parameter | Standard | Bedeutung |
|---|---|---|
| `-OutputDirectory` | `./reports` im aktuellen Arbeitsverzeichnis | Übergeordneter Ordner für einen neuen Laufordner. |

Das Skript legt einen eindeutigen Unterordner mit UTC-Zeitstempel und Zufallskennung an. Darin stehen `storage-network-exposure.csv`, `storage-network-exposure.json` und `audit.log`. Der JSON-Report enthält eine Zusammenfassung und alle Einträge. Das Log protokolliert nur Zeitpunkt, Abonnement-ID, Anzahl und Erfolg; sensible Kontoschlüssel werden nicht abgefragt oder gespeichert.

Die Ausgabe enthält Resource IDs und Account-Namen, die als betriebliche Metadaten vertraulich behandelt werden sollten. Keine IP-Regelwerte werden ausgegeben, nur deren Anzahl.

## Beispiel

```powershell
Install-Module Az.Accounts, Az.Storage -Scope CurrentUser
Connect-AzAccount
Set-AzContext -Subscription 'beispiel-abonnement'
./Invoke-StorageNetworkExposureAudit.ps1 -OutputDirectory ./reports
```

Vor dem Lauf `Get-AzContext` prüfen. Bei mehreren Abonnements das Skript je Kontext separat ausführen. Der Rückgabewert nennt die erzeugten Dateipfade.

## Einordnung der Ergebnisse

| Assessment | Bedeutung |
|---|---|
| `ReviewAllNetworks` | Öffentlicher Netzwerkzugang aktiviert und Standardregel `Allow`. Priorisiert manuell prüfen. |
| `ReviewSelectedNetworks` | Öffentlicher Netzwerkzugang aktiviert und Standardregel `Deny`. Zugelassene Netze, Ausnahmen und Perimeter manuell prüfen. |
| `PublicAccessDisabled` | Öffentlicher Netzwerkzugang laut Account-Eigenschaft deaktiviert. Private Endpunkte und Perimeter separat prüfen. |
| `UnknownReviewRequired` | Eigenschaft fehlt oder enthält einen nicht erkannten Wert. Keine Entwarnung ableiten. |

Die Zahlen für IP-, VNet- und Resource-Access-Regeln sind Hinweise, keine vollständige Zugriffsliste. `Bypass` wird als Konfigurationstext ausgegeben, weil Trusted-Service-Ausnahmen relevant sein können.

## Logging, Fehlerbehandlung und Validierung

- Fehlende Module, fehlender Kontext und nicht lesbare Storage Accounts führen zu einem Fehler **vor** dem Schreiben eines Reports.
- Schreibfehler brechen den Lauf mit einer Fehlermeldung ab. Ein dabei angelegter Laufordner kann unvollständig sein und darf nicht als valider Report gelten.
- Ein leeres Abonnement erzeugt eine CSV nur mit Kopfzeile und einen JSON-Report mit `AccountCount=0`.
- Plausibilitätsprüfung: `AccountCount` mit der Anzahl der Datenzeilen in CSV und `Accounts` in JSON vergleichen; `ReviewAllNetworks` gegen Portal/Resource Graph stichprobenartig prüfen.
- Die UTC-Zeit des Reports sowie der ausgewählte Kontext müssen zum Change-/Ticketzeitraum passen.

## Sicherheit und Einschränkungen

Es gibt keine Azure-Schreiboperation. Das Skript verwendet weder `Set-AzStorageAccount` noch `Get-AzStorageAccountKey`, SAS oder Datenendpunkte. Es liest nur Management-Plane-Eigenschaften des aktuellen Abonnements. Lokale Reports nach interner Aufbewahrungsfrist geschützt löschen.

Das Audit testet keine echte Netzverbindung, keine DNS-Auflösung, keine Datenberechtigungen und keine wirksame Network-Security-Perimeter-Regel. Die Konfiguration kann sich nach dem Lesen ändern. Fehlende oder neue API-Werte werden als `UnknownReviewRequired` behandelt.

## Rollback / Rückbau

Da das Skript keine Azure-Ressourcen verändert, ist kein Azure-Rollback nötig. Einen Testlauf lokal durch Entfernen **des eindeutig benannten Laufordners** rückbauen. Änderungen an Storage-Firewalls sind separate, genehmigte Changes mit eigenem Rollback-Plan und werden durch dieses Skript nicht ausgeführt.

## Quellen

- [Get-AzStorageAccount](https://learn.microsoft.com/powershell/module/az.storage/get-azstorageaccount)
- [Azure Storage network security FAQ](https://learn.microsoft.com/en-us/troubleshoot/azure/azure-storage/blobs/networking/storage-network-security-faq)
- [Standardregel für öffentlichen Netzwerkzugang](https://learn.microsoft.com/en-us/azure/storage/common/storage-network-security-set-default-access)
- [Azure Reader-Rolle](https://learn.microsoft.com/en-us/azure/role-based-access-control/built-in-roles/general#reader)
