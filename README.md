# storeBackup Docker image

Schlankes Debian-Image für regelmäßige lokale oder gemountete Backups mit
storeBackup. Die Quelle wird read-only gemountet; geschrieben wird ausschließlich
in das Backup-Ziel.

## Start

`compose.yaml` übernehmen, `OWNER` und die Pfade anpassen, anschließend:

```sh
docker compose up -d
docker compose exec storebackup backup
```

Alle Einstellungen stehen direkt in `environment:`. `KUMA_PUSH_URL` ist optional
und wird nur nach einem erfolgreichen storeBackup-Lauf aufgerufen. Ein fehlender
oder fehlerhafter Push beendet den manuellen/geplanten Lauf mit Fehler; dadurch
bleibt der Zustand sichtbar und Kuma kann alarmieren.

`KEEP_DAYS`, `KEEP_WEEKS` und `KEEP_MONTHS` werden als Altersstufen an
storeBackup `--keepRelative` übergeben. Die eigentliche Retention und Löschung
erfolgt vollständig durch storeBackup. Die Standardwerte sind 7 Tage, 4 Wochen
und 12 Monate.

## Architektur und Sicherheit

Debian trixie-slim installiert storeBackup aus Debian sowie nur cron, curl und
tzdata als Laufzeitwerkzeuge. Der Scheduler läuft im Vordergrund, und SIGTERM
wird an ihn weitergereicht. Logs gehen nach stdout/stderr. Root bleibt absichtlich
der Standard: storeBackup soll Eigentümer, Rechte, Hardlinks und Metadaten der
Quelle verlustfrei sichern; ein non-root-Betrieb ist nur mit bewusst passenden
UID/GID- und Mount-Rechten möglich.

## Builds und Updates

GitHub Actions baut und veröffentlicht nach GHCR (`latest` auf `main`, versionierte
Tags bei `v*`) und führt reguläre Builds aus. Dependabot überwacht Docker-Basisimage
und Actions; ein wöchentlicher Workflow-Build berücksichtigt außerdem neue Debian-
Paketstände ohne Änderungen am Dockerfile.

Lizenz: GPL-3.0-or-later.
