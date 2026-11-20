# Windows Server Firewall Profile Health Audit

## Zweck und Support-Fall

Das Skript prüft auf **dem lokalen Windows Server** die effektiv aktiven Firewall-Profile Domain, Private und Public. Es unterstützt First-/Second-Level-Support bei der Erstaufnahme nach Änderungen an Gruppenrichtlinien, Serverrollen oder Netzzuordnung: Ist ein Profil deaktiviert? Erlaubt es eingehende Verbindungen standardmäßig? Ist die Protokollierung blockierter Pakete aktiv?

Der Report ist eine **Konfigurationsprüfung**, kein vollständiger Firewall- oder Penetrationstest. `Configured` bedeutet nur, dass die im Skript geprüften Profileigenschaften den genannten Bedingungen entsprechen.

## Voraussetzungen, Module, Rollen und minimale Berechtigungen

- Unterstützter Windows Server mit Windows PowerShell 5.1 oder PowerShell 7 und verfügbarem Modul `NetSecurity`.
- Befehl `Get-NetFirewallProfile` muss lokal aufrufbar sein. Keine Azure-/M365-Module nötig.
- Leserechte auf die lokalen Firewall-Profile und Schreibrechte auf den gewählten lokalen Reportordner. Für eine verlässliche Ausführung im Serverbetrieb wird eine erhöhte PowerShell-Sitzung empfohlen; es ist keine Domain-Admin-Rolle und keine Änderungserlaubnis im Skript erforderlich.
- Das Skript fragt `ActiveStore` ab. Dieser Store enthält die aktuell wirksame Kombination der anwendbaren Richtlinien. Ohne `-PolicyStore ActiveStore` würde der Cmdlet-Standard nur `PersistentStore` abfragen.

## Parameter und Beispiele

| Parameter | Standard | Bedeutung |
|---|---|---|
| `-OutputDirectory` | `./reports` im aktuellen Arbeitsverzeichnis | Oberordner für einen neuen, eindeutig benannten Laufordner. |

```powershell
./Invoke-FirewallProfileHealthAudit.ps1
./Invoke-FirewallProfileHealthAudit.ps1 -OutputDirectory 'C:\Reports\Firewall'
```

Für einen anderen Server das Skript **dort** ausführen, etwa in einer dafür freigegebenen Remoting-Sitzung. Das Skript selbst baut keine Remoteverbindung auf.

## Ausgaben und Einordnung

Jeder Lauf erzeugt einen neuen UTC-Zeitstempelordner mit Zufallskennung. Darin liegen `firewall-profiles.csv`, `firewall-profiles.json` und `audit.log`. CSV/JSON enthalten je eine Zeile für Domain, Private und Public mit `Enabled`, Standardaktionen, `LogBlocked`, Logpfad, Loggröße, Assessment und Prüfzeit. Das Log enthält nur Hostname, Zeit, Profilanzahl und Erfolg.

| Assessment | Bedeutung |
|---|---|
| `ReviewFirewallDisabled` | Das Profil meldet `Enabled=False`; priorisiert manuell prüfen. |
| `ReviewDefaultInboundAllow` | Das aktivierte Profil erlaubt eingehende Verbindungen standardmäßig; Regelwerk und Ausnahmeprozess prüfen. |
| `ReviewBlockedLoggingOff` | Das aktivierte Profil blockiert standardmäßig eingehend, protokolliert aber blockierte Pakete nicht; Logging-Anforderung prüfen. |
| `Configured` | Profil aktiviert, Standard-Inbound `Block`, `LogBlocked=True`. Keine Aussage über einzelne Regeln oder tatsächliche Erreichbarkeit. |
| `UnknownMissingProfile` / `UnknownReviewRequired` | Profil fehlt oder Werte konnten nicht eindeutig klassifiziert werden; keine Entwarnung ableiten. |

## Logging, Fehlerbehandlung und Validierung

- Fehlt `Get-NetFirewallProfile`, schlägt die Abfrage fehl oder liefert sie gar keine Profile, endet das Skript mit Fehler **ohne** Report.
- Ein einzelnes fehlendes erwartetes Profil wird als `UnknownMissingProfile` exportiert. Doppelte Profilnamen führen zum Abbruch, statt unklarer Ergebnisse.
- Bei Schreibfehlern bricht der Lauf ab. Ein bereits angelegter Laufordner kann dann unvollständig sein und ist kein gültiger Report.
- Zur Validierung die drei Zeilen und die UTC-Zeit prüfen und stichprobenartig mit `Get-NetFirewallProfile -PolicyStore ActiveStore` sowie der Windows-Firewall-Konsole vergleichen.
- Die Netzwerkkategorie eines Interfaces bestimmt, welches Profil gerade verwendet wird; dieses Skript prüft die Konfiguration aller drei Profile und identifiziert keine aktive Interface-Profilzuordnung.

## Sicherheit, Einschränkungen und Rollback

Das Skript ruft nur `Get-NetFirewallProfile` auf. Es enthält keine `Set-`, `New-`, `Remove-` oder `Enable-NetFirewall*`-Operation. Es liest keine einzelnen Firewallregeln, Pakete, Verbindungen oder GPO-Herkunft. Auch ein `Configured`-Profil kann zu breite Allow-Regeln enthalten. Profileigenschaften können sich nach dem Lauf ändern.

CSV und JSON enthalten Hostname und lokale Logpfade und sind als Betriebsdaten geschützt aufzubewahren. Nach Ablauf der internen Aufbewahrungsfrist den **eindeutig benannten lokalen Laufordner** entfernen. Ein Azure-/Server-Rollback ist nicht erforderlich, da keine Firewall-Einstellungen geändert werden. Jede spätere Richtlinienänderung braucht eine eigene Change-Freigabe und einen eigenen Rückbauplan.

## Quellen

- [Get-NetFirewallProfile und ActiveStore](https://learn.microsoft.com/en-us/powershell/module/netsecurity/get-netfirewallprofile)
- [Windows Firewall über die Befehlszeile verwalten](https://learn.microsoft.com/en-us/windows/security/operating-system-security/network-security/windows-firewall/configure-with-command-line)
- [Windows Firewall Logging konfigurieren](https://learn.microsoft.com/en-us/windows/security/operating-system-security/network-security/windows-firewall/configure-logging)
