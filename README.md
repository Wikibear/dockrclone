# dockrclone

Schlanker Container für geplante Synchronisationen lokaler Verzeichnisse zu
rclone-Remotes. rclone unterstützt unter anderem FTP, SFTP, WebDAV sowie diverse
Cloud- und Objektspeicher. Cron-Zeitplan und optionaler Uptime-Kuma-Heartbeat
bleiben im Container integriert.

## Einrichtung

Lege im Projektverzeichnis den persistenten Konfigurationsordner `config` an
und erstelle darin `rclone.conf`. Die Datei enthält die Remotes und Zugangsdaten
und wird nicht ins Git-Repository aufgenommen:

```sh
mkdir -p config
docker compose run --rm rclone config
```

Der Befehl führt den rclone-Konfigurationsdialog aus. Danach enthält die Datei
beispielsweise ein Remote namens `backup`. Passe `REMOTE_ROOT` in `compose.yaml`
an diesen Remote-Namen an. Der Standard `backup:` synchronisiert Quellen in
`backup:<Quellenname>`.

## Start und manueller Lauf

```sh
docker compose config
docker compose up -d --build
docker compose exec rclone backup
docker compose logs -f rclone
```

Für einzelne rclone-Befehle im laufenden Container kannst du `rclone` als
Entrypoint-Unterbefehl verwenden. Die persistent gemountete Konfiguration wird
automatisch mitgegeben, zum Beispiel:

```sh
docker compose exec rclone rclone listremotes
```

Vor einem echten Lauf kann rclone mit `--dry-run` prüfen, was geändert würde:

```sh
docker compose exec rclone rclone sync --dry-run \
  --config=/config/rclone.conf /source/appdata backup:appdata
```

Das Backup-Skript führt für jede Quelle den gewählten Modus nacheinander aus.
Parallele Läufe sollten vermieden werden, wenn sie auf dieselben Remotes
zugreifen.

## Compose-Konfiguration

```yaml
name: dockrclone

services:
  rclone:
    build: .
    restart: unless-stopped
    security_opt:
      - no-new-privileges:true
    environment:
      TZ: Europe/Berlin
      SCHEDULE: "0 3 * * *"
      SOURCES: |
        docker-volumes=/source/docker-volumes
        appdata=/source/appdata
      REMOTE_ROOT: "backup:"
      DELETE_EXTRANEOUS: "true"
      KUMA_BASE: ""
      KUMA_TOKEN: ""
    volumes:
      - /var/lib/docker/volumes:/source/docker-volumes:ro
      - /opt/appdata:/source/appdata:ro
  - ./config:/config
```

Der Hostordner heißt absichtlich nur `config`; rclone liest dort
`/config/rclone.conf`. Halte die Datei mit eingeschränkten Dateirechten privat.
Wenn du für OAuth-Remotes Token-Aktualisierungen erlauben willst, muss rclone
in diesen Ordner schreiben können. Dafür müssen die Host-Dateirechte zum im
Container laufenden Benutzer passen.

## Einstellungen

| Variable | Standard | Beschreibung |
| --- | --- | --- |
| `TZ` | `UTC` | Zeitzone für Cron |
| `SCHEDULE` | `0 3 * * *` | Fünffeld-Cron-Ausdruck |
| `SOURCES` | leer | Mehrzeilige Liste `name=/absoluter/pfad` |
| `REMOTE_ROOT` | leer | rclone-Zielbasis, z. B. `backup:` |
| `DELETE_EXTRANEOUS` | `true` | `true` nutzt `rclone sync`; `false` nutzt `rclone copy` ohne Löschen am Ziel |
| `KUMA_BASE` | leer | Kuma-Basis-URL |
| `KUMA_TOKEN` | leer | Kuma-Push-Token |

Jede Quelle wird in ein Unterverzeichnis unter `REMOTE_ROOT` synchronisiert.
`DELETE_EXTRANEOUS=true` löscht am Ziel Dateien, die in der Quelle nicht mehr
vorhanden sind. rclone löscht bei einem Lauf mit Fehlern keine Ziel-Dateien.
Für einen nicht-destruktiven Spiegeltest kann `rclone sync --dry-run` verwendet
werden.

## Aktualisierung

Dependabot prüft wöchentlich die Docker-Referenz `rclone/rclone:latest` im
Dockerfile. Zusammen mit dem wöchentlichen Build wird so das aktuelle offizielle
rclone-Binary in das dockrclone-Image übernommen. Nach Änderungen:

```sh
docker compose build --pull
docker compose up -d
```

Das Container-Image wird vom bestehenden GitHub-Repository gebaut und nach
GHCR veröffentlicht. Das Repository muss für die Umbenennung auf dockrclone
nicht neu angelegt werden; GitHub kann das bestehende Repository umbenennen.

Lizenz: GPL-3.0-or-later.
