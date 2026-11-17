# Azure Public IP Inventory Audit

Read-only PowerShell-Bestandsprüfung für Public-IP-Ressourcen im aktuell gewählten Azure-Abonnement oder in einer Ressourcengruppe. Sie exportiert Konfigurations- und Zuordnungshinweise als CSV, JSON und Log. Es werden keine IPs gelöscht, entkoppelt oder geändert.

## Zweck und Support-Case

Public-IP-Ressourcen sollen im Support und Systems Engineering schnell zugeordnet und vor Änderungen geprüft werden können. Der Audit zeigt Name, Ressourcengruppe, Region, Adresse, Zuordnungstyp, Version, SKU, Provisionierungszustand und das Vorhandensein einer `IpConfiguration`. Fehlende `IpConfiguration` wird nur als **`ReviewAssociation`** markiert: Eine Public IP kann auch über andere Ressourcentypen verwendet werden, etwa NAT Gateway. Der Bericht behauptet daher weder „ungenutzt“ noch „kostenpflichtig ohne Nutzen“ und führt keine Bereinigung aus.

## Voraussetzungen und Module

- PowerShell 7 oder Windows PowerShell 5.1.
- Für Live-Abfragen die Module `Az.Accounts` und `Az.Network` sowie eine bestehende Verbindung per `Connect-AzAccount`.
- Das korrekte Azure-Abonnement muss im Kontext ausgewählt sein. Der Audit wechselt oder durchsucht Abonnements nicht selbst.
- Für Offline-Tests reichen PowerShell und `ConvertFrom-Json`; keine Azure-Anmeldung nötig.
- Schreibrecht auf den lokalen Ausgabeordner.

## Rollen und minimale Berechtigungen

Die Azure-Rolle **Reader** auf dem betrachteten Abonnement oder der Ressourcengruppe genügt für Control-Plane-Lesezugriff. Alternativ ist eine engere benutzerdefinierte Rolle mit `Microsoft.Network/publicIPAddresses/read` möglich, sofern die Organisation sie bereitstellt. Keine Network-Contributor- oder Schreibrechte nötig. Der Audit speichert keine Anmeldedaten oder Tokens.

## Parameter

| Parameter | Standard | Bedeutung |
|---|---|---|
| `ResourceGroupName` | keine Einschränkung | Optional auf eine Ressourcengruppe begrenzen |
| `OutputDirectory` | `./Reports` | Ausgabeordner für CSV, JSON und Log |
| `InputJsonPath` | keiner | Synthetische JSON-Daten statt Azure-Abfrage |
| `OnlyReview` | aus | Nur Zeilen mit Review-Finding exportieren |

## Beispiele

```powershell
Connect-AzAccount
Get-AzContext  # Abonnement vor dem Audit prüfen
./Get-PublicIpInventoryAudit.ps1 -OutputDirectory './Reports'
./Get-PublicIpInventoryAudit.ps1 -ResourceGroupName 'rg-example' -OnlyReview
./Get-PublicIpInventoryAudit.ps1 -InputJsonPath './sample-public-ips.json' -OutputDirectory './Reports'
```

Synthetische Offline-Daten ohne echte Subscription-ID oder Kundendaten:

```json
[{"Name":"pip-example-01","ResourceGroupName":"rg-example","Location":"westeurope","IpAddress":"192.0.2.10","PublicIpAllocationMethod":"Static","PublicIpAddressVersion":"IPv4","Sku":{"Name":"Standard"},"ProvisioningState":"Succeeded","IpConfiguration":null}]
```

## Logging, Fehlerbehandlung und Validierung

Jeder Lauf schreibt `PublicIpInventoryAudit-*.csv`, `.json` und `.log` mit UTC-Zeitstempel. Das Log enthält nur Zähler und Dateipfade; die Ergebnisdateien können reale öffentliche Adressen und Ressourcennamen enthalten und müssen geschützt abgelegt werden. Fehlende Azure-Module, fehlender Kontext, Abfragefehler und ungültige Datensätze beenden den Lauf mit Fehler. Bei null Treffern oder `OnlyReview` ohne Findings werden eine CSV-Kopfzeile und ein leeres JSON-Array geschrieben.

Vor Live-Nutzung die synthetische Datei testen: eine fehlende `IpConfiguration` ergibt `ReviewAssociation`, ein Fehler im Provisionierungszustand `ReviewProvisioning`, eine fehlende Adresse bei vorhandener Konfiguration `ReviewAddress`. Danach die ausgegebene Ressourcengruppe und den Azure-Kontext mit dem Portal abgleichen. Review-Kandidaten vor jeder Änderung über NIC, Load Balancer, NAT Gateway und andere mögliche Bindungen prüfen.

## Sicherheit und Einschränkungen

- Ausschließlich lesende `Get-AzPublicIpAddress`-Abfragen; keine Remediation.
- `IpConfiguration` allein ist kein vollständiger Nutzungsnachweis. Insbesondere NAT-Gateway- und andere Zuordnungen müssen separat verifiziert werden.
- Eine zugewiesene öffentliche IP bedeutet nicht automatisch, dass ein Dienst aus dem Internet erreichbar ist. Netzwerkregeln und Zielressource sind gesondert zu prüfen.
- Keine Kostenberechnung und keine organisationsübergreifende oder abonnementübergreifende Inventur.
- Offline-JSON prüft die Klassifikation, nicht Azure-Berechtigungen oder Live-Daten.

## Rollback und Rückbau

Da keine Azure-Ressource verändert wird, ist kein technischer Rollback nötig. Lokale Berichte nach Aufbewahrungsregeln entfernen. Für einen späteren Cleanup sind Eigentümer-, Abhängigkeits- und Change-Prüfungen erforderlich; sie sind nicht Teil dieses Skripts.

## Quellen

- [Microsoft: Get-AzPublicIpAddress](https://learn.microsoft.com/en-us/powershell/module/az.network/get-azpublicipaddress)
- [Microsoft: Public IP addresses in Azure](https://learn.microsoft.com/en-us/azure/virtual-network/ip-services/public-ip-addresses/)
- [Microsoft: Reader role](https://learn.microsoft.com/en-us/azure/role-based-access-control/built-in-roles/general)
