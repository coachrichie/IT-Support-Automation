# Shared Mailbox Permission Audit

Read-only PowerShell-Audit für delegierte Berechtigungen auf freigegebenen Exchange-Online-Postfächern. Das Skript führt **keine Änderungen** an Postfächern oder Berechtigungen aus.

## Zweck und Support-Case

Bei Tickets wie „Ich kann das Funktionspostfach öffnen, aber nicht daraus senden“ oder bei regelmäßigen Berechtigungsreviews fehlt oft eine konsolidierte Sicht. Das Skript erfasst `FullAccess`, `SendAs` und `SendOnBehalf`, führt die Einträge pro Postfach und Trustee zusammen und markiert unvollständige Kombinationen mit `Review`.

Microsoft unterscheidet diese Rechte bewusst: Full Access erlaubt den Zugriff auf Inhalte, aber nicht automatisch das Senden. Send As und Send on Behalf erlauben das Senden mit unterschiedlicher Absenderdarstellung.

## Voraussetzungen

- PowerShell 7.2 oder neuer
- Modul `ExchangeOnlineManagement`
- Netzwerkzugriff auf Exchange Online
- Ein Konto mit Exchange-Online-RBAC-Zugriff auf die verwendeten Get-Cmdlets

```powershell
Install-Module ExchangeOnlineManagement -Scope CurrentUser
```

## Rollen und minimale Berechtigungen

Das Skript benötigt nur lesenden Zugriff auf:

- `Get-EXOMailbox`
- `Get-EXOMailboxPermission`
- `Get-EXORecipientPermission`

Verwenden Sie eine möglichst kleine, organisationsspezifische Exchange-RBAC-Zuweisung. Welche Managementrollen die Cmdlets im eigenen Tenant bereitstellen, lässt sich nach Anmeldung prüfen:

```powershell
Get-ManagementRole -Cmdlet Get-EXOMailbox
Get-ManagementRole -Cmdlet Get-EXOMailboxPermission
Get-ManagementRole -Cmdlet Get-EXORecipientPermission
```

Global Administrator ist nicht erforderlich und sollte für diesen Report nicht verwendet werden.

## Parameter

| Parameter | Standard | Bedeutung |
|---|---|---|
| `OutputDirectory` | `./Reports` | Ziel für CSV und Logdatei |
| `MailboxFilter` | `*` | Wildcard-Filter auf Anzeigename oder primäre SMTP-Adresse |
| `IncludeInherited` | aus | Nimmt geerbte FullAccess-Einträge zusätzlich auf |
| `SkipConnect` | aus | Verwendet eine bereits bestehende Exchange-Online-Sitzung |
| `DisconnectOnExit` | aus | Trennt nur eine vom Skript aufgebaute Sitzung nach dem Lauf |
| `Organization` | leer | Optionaler Tenant-/Organisationswert für `Connect-ExchangeOnline` |

## Beispiele

Tenantweiter Audit mit interaktiver Anmeldung:

```powershell
./Get-SharedMailboxPermissionAudit.ps1 -OutputDirectory C:\Reports\SharedMailbox
```

Nur Postfächer mit „Support“ im Namen oder in der SMTP-Adresse:

```powershell
./Get-SharedMailboxPermissionAudit.ps1 -MailboxFilter '*support*' -DisconnectOnExit
```

Vorhandene Sitzung verwenden:

```powershell
Connect-ExchangeOnline
./Get-SharedMailboxPermissionAudit.ps1 -SkipConnect
```

## Ausgabe und Bewertung

Die CSV enthält pro Postfach und Trustee unter anderem:

- `HasFullAccess`
- `HasSendAs`
- `HasSendOnBehalf`
- `ContainsDeny`
- `ContainsInherited`
- `Status`
- `Permissions`

Statuswerte:

- `Complete`: FullAccess plus mindestens ein Senderecht
- `Review`: nur Zugriff oder nur Senderecht; fachlich prüfen
- `Review-Deny`: mindestens ein expliziter Deny-Eintrag
- `No-Delegates`: keine delegierten Rechte gefunden
- `Collection-Error`: dieses Postfach konnte nicht vollständig gelesen werden

Ein `Review` ist kein automatischer Fehler. Manche Rollen benötigen absichtlich nur Lesezugriff oder nur Send As. Gruppenmitgliedschaften werden nicht rekursiv aufgelöst.

## Logging und Fehlerbehandlung

Jeder Lauf erzeugt neben der CSV eine UTF-8-Logdatei. Fehler bei einem einzelnen Postfach werden protokolliert und als `Collection-Error` in den Report aufgenommen; die übrigen Postfächer werden weiter verarbeitet. Fehlende Module, Cmdlets oder Verbindungsfehler beenden den Lauf mit einer verständlichen Fehlermeldung.

## Validierung

1. Prüfen Sie `ErrorCount` und alle `Collection-Error`-Zeilen.
2. Vergleichen Sie Stichproben mit Exchange Admin Center > Empfänger > Freigegebene Postfächer > Delegierung.
3. Prüfen Sie `Review`-Zeilen gegen den genehmigten Sollzustand.
4. Archivieren Sie Report und Log geschützt; sie enthalten interne Postfach- und Identitätsdaten.

## Sicherheit

- Standardmäßig read-only; es werden ausschließlich Get-Cmdlets verwendet.
- Keine eingebetteten Zugangsdaten, Tokens, Tenant-IDs oder Beispiel-Kundendaten.
- CSV und Logs können personenbezogene bzw. organisatorische Daten enthalten. Zugriff, Aufbewahrung und Löschung müssen dem internen Schutzkonzept entsprechen.
- Automatisierte Ausführung sollte mit Zertifikatsauthentifizierung und einer dedizierten, minimal berechtigten App erfolgen. Das Skript erzwingt keinen Authentifizierungsweg.
- Führen Sie Reports zuerst in einer Testumgebung bzw. mit einem engen `MailboxFilter` aus.

## Einschränkungen

- Gruppen werden als Trustee ausgewiesen; ihre Mitglieder werden nicht expandiert.
- Die reine Rechtekombination beweist nicht, dass der Zugriff fachlich genehmigt ist.
- `GrantSendOnBehalfTo` kann je nach Objekt als Name oder Objektidentität erscheinen.
- Hybridbereitstellungen können zusätzliche On-Premises-Zuständigkeiten und Synchronisationswege haben.
- Automapping ist aus den gelesenen Berechtigungsobjekten nicht zuverlässig ableitbar.

## Rollback / Rückbau

Das Skript verändert keine Exchange-Konfiguration. Ein technischer Rollback ist daher nicht erforderlich. Zum Rückbau löschen Sie ausschließlich die lokal erzeugten CSV- und Logdateien gemäß Aufbewahrungsrichtlinie. Berechtigungsänderungen sollten nach separater Freigabe und mit dokumentiertem Change erfolgen; sie sind bewusst nicht Teil dieses Skripts.

## Quellen

- [Shared mailboxes in Exchange Online](https://learn.microsoft.com/en-us/exchange/collaboration/shared-mailboxes/shared-mailboxes)
- [Manage permissions for recipients in Exchange Online](https://learn.microsoft.com/en-us/exchange/recipients-in-exchange-online/manage-permissions-for-recipients)
- [Get-EXOMailbox](https://learn.microsoft.com/en-us/powershell/module/exchangepowershell/get-exomailbox?view=exchange-ps)
- [Get-EXOMailboxPermission](https://learn.microsoft.com/en-us/powershell/module/exchangepowershell/get-exomailboxpermission?view=exchange-ps)
- [Exchange Online PowerShell module](https://learn.microsoft.com/en-us/powershell/exchange/exchange-online-powershell-v2?view=exchange-ps)
- [Find permissions required to run Exchange cmdlets](https://learn.microsoft.com/en-us/powershell/exchange/find-exchange-cmdlet-permissions?view=exchange-ps)
