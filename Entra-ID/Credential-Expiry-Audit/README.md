# Microsoft Entra ID – Credential Expiry Audit

Dieser read-only PowerShell-Case findet abgelaufene und bald ablaufende Client Secrets sowie Zertifikate in Microsoft Entra ID. Er unterstützt die proaktive Erneuerung von Anwendungs-Credentials, bevor Workloads oder Integrationen ihre Authentifizierung verlieren.

## Funktionsumfang

- prüft standardmäßig alle App-Registrierungen
- kann optional auch Service Principals einbeziehen
- wertet \`passwordCredentials\` und \`keyCredentials\` aus
- verwendet ein frei konfigurierbares Warnfenster (Standard: 30 Tage)
- klassifiziert Ergebnisse als \`Expired\`, \`Critical\` (höchstens 7 Tage) oder \`Warning\`
- exportiert einen sortierten CSV-Report
- protokolliert Ablauf und Fehler in einer Logdatei
- verändert keine Credentials und führt keine automatische Rotation durch

## Voraussetzungen

- Windows PowerShell 5.1 oder PowerShell 7
- Microsoft Graph PowerShell SDK, mindestens das Modul \`Microsoft.Graph.Applications\`
- ein Konto mit Zustimmung für den delegierten Microsoft-Graph-Scope \`Application.Read.All\`

Installation des benötigten Moduls:

\`\`\`powershell
Install-Module Microsoft.Graph.Applications -Scope CurrentUser
\`\`\`

Je nach Tenant-Einstellungen ist für \`Application.Read.All\` eine Administratorzustimmung erforderlich.

## Verwendung

App-Registrierungen mit dem Standardwarnfenster von 30 Tagen prüfen:

\`\`\`powershell
.\Get-EntraCredentialExpiryAudit.ps1
\`\`\`

Warnfenster auf 60 Tage erweitern und Service Principals einbeziehen:

\`\`\`powershell
.\Get-EntraCredentialExpiryAudit.ps1 -WarningDays 60 -IncludeServicePrincipals
\`\`\`

Eigene Ausgabeziele verwenden:

\`\`\`powershell
.\Get-EntraCredentialExpiryAudit.ps1 \
  -OutputPath C:\Reports\Entra-Credentials.csv \
  -LogPath C:\Reports\Entra-Credentials.log
\`\`\`

## CSV-Felder

| Feld | Bedeutung |
|---|---|
| \`ObjectType\` | \`Application\` oder \`ServicePrincipal\` |
| \`DisplayName\` | Anzeigename des Entra-Objekts |
| \`AppId\` | Client-/Anwendungs-ID |
| \`ObjectId\` | Objekt-ID in Entra ID |
| \`CredentialType\` | \`ClientSecret\` oder \`Certificate\` |
| \`CredentialName\` | Anzeigename des Credentials, sofern vorhanden |
| \`KeyId\` | Eindeutige Credential-ID |
| \`StartDateTimeUtc\` | Beginn der Gültigkeit in UTC |
| \`EndDateTimeUtc\` | Ablaufzeitpunkt in UTC |
| \`DaysRemaining\` | Verbleibende volle Tage; negative Werte sind bereits abgelaufen |
| \`Status\` | \`Expired\`, \`Critical\` oder \`Warning\` |
| \`CertificateThumbprint\` | Thumbprint des Zertifikats, sofern von Graph geliefert |
| \`SecretHint\` | Von Graph gelieferter kurzer Hinweis; niemals der Secret-Wert |

## Berechtigungen und Sicherheit

Das Skript fordert ausschließlich \`Application.Read.All\` an und verwendet nur lesende Graph-Aufrufe. Client-Secret-Werte können über Microsoft Graph nicht ausgelesen werden; der Report enthält lediglich Metadaten wie Key-ID, Ablaufdatum und gegebenenfalls den Secret-Hinweis.

Die CSV- und Logdateien können dennoch sensible Bestandsdaten enthalten. Speichere sie geschützt, beschränke den Zugriff und lösche sie entsprechend den internen Aufbewahrungsregeln.

## Validierung

1. Zunächst in einem Test-Tenant oder mit einem begrenzten Administratorkonto ausführen.
2. Prüfen, ob bekannte Test-Credentials im erwarteten Warnfenster erscheinen.
3. \`DaysRemaining\`, \`Status\` und \`EndDateTimeUtc\` gegen das Entra Admin Center abgleichen.
4. Bei Verwendung von \`-IncludeServicePrincipals\` stichprobenartig auf mögliche Doppelmeldungen prüfen, da App-Registrierung und zugehöriger Service Principal eigene Credential-Bestände besitzen können.
5. Das Skript mit einem kleinen Warnfenster erneut ausführen und die erwartete Reduktion der Ergebnisse bestätigen.

## Einschränkungen

- Das Skript rotiert, verlängert oder entfernt keine Credentials.
- Es prüft nur Credentials, die Microsoft Graph in \`passwordCredentials\` und \`keyCredentials\` zurückgibt.
- App-Registrierungen und Service Principals können dasselbe logische Workload repräsentieren; ihre Objekte werden bewusst getrennt ausgewiesen.
- Throttling und temporäre Graph-Fehler werden vom Microsoft Graph PowerShell SDK behandelt; bei einem terminierenden Fehler wird der Lauf abgebrochen und protokolliert.
- Die Lösung wurde nicht gegen einen produktiven Tenant ausgeführt. Vor dem produktiven Einsatz ist eine Validierung erforderlich.

## Rollback

Es gibt keinen Tenant-Rollback, weil das Skript keine Änderungen in Entra ID ausführt. Lokale CSV- und Logdateien können bei Bedarf gelöscht werden.

## Weiterführende Dokumentation

- [Microsoft Entra recommendation: Renew expiring application credentials](https://learn.microsoft.com/en-us/entra/identity/monitoring-health/recommendation-renew-expiring-application-credential)
- [Microsoft Graph: List applications](https://learn.microsoft.com/en-us/graph/api/application-list)
- [Microsoft Graph: List servicePrincipals](https://learn.microsoft.com/en-us/graph/api/serviceprincipal-list)
- [Microsoft Graph throttling guidance](https://learn.microsoft.com/en-us/graph/throttling)
