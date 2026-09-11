# IT Support Automation

PowerShell-basierte Automatisierungen für wiederkehrende Aufgaben und Support-Fälle im Microsoft-Umfeld.

## Schwerpunkte

- Windows Server
- Microsoft 365
- Microsoft Entra ID
- Microsoft Intune
- Exchange Online
- Microsoft Purview
- Microsoft Defender
- Microsoft Azure

## Qualitätsstandard

Jede Lösung soll nach Möglichkeit enthalten:

- Problemstellung und konkreten Use Case
- Voraussetzungen, Module, Rollen und Berechtigungen
- robuste, parametrisierte PowerShell-Lösung
- Fehlerbehandlung und Logging
- möglichst idempotentes Verhalten
- sichere Standardwerte
- Installations- und Nutzungsanleitung
- Beispielaufrufe
- Test- und Validierungsschritte
- Sicherheits- und Betriebsaspekte
- bekannte Einschränkungen
- Rollback- bzw. Rückbau-Hinweise
- Quellen und weiterführende Dokumentation

## Struktur

```text
Windows-Server/
M365/
Entra-ID/
Intune/
Exchange/
Purview/
Defender/
Azure/
```

Jede Automatisierung erhält einen eigenen Unterordner mit PowerShell-Skript und README.

## Sicherheit

Alle Skripte sollten vor dem produktiven Einsatz in einer Testumgebung geprüft werden. Destruktive Aktionen werden vermieden oder müssen explizit aktiviert werden.
