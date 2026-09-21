# dockrsync

Schlankes Debian-Image für regelmäßige lokale oder gemountete Backups mit
`rsync`. Die Quelle wird read-only gemountet; geschrieben wird ausschließlich
in das Backup-Ziel.

## Start

`compose.yaml` übernehmen und die Pfade anpassen, anschließend:

```sh
docker compose up -d
docker compose exec rsync backup
```

Alle Einstellungen stehen direkt in `environment:`. Es können beliebig viele
Quellen definiert werden. Der optionale Kuma-Heartbeat wird erst gesendet, wenn
alle Quellen erfolgreich gesichert wurden. Ein fehlgeschlagener Push beendet den
manuellen oder geplanten Lauf mit Fehler.

## Manuell testen

Vor dem Start kann die Compose-Konfiguration geprüft werden:

```sh
docker compose config
```

Container starten und Status kontrollieren:

```sh
docker compose up -d
docker compose ps
```

Einen vollständigen Backup-Lauf sofort im laufenden Container ausführen:

```sh
docker compose exec rsync backup
```

Der Befehl läuft im Vordergrund und liefert bei Erfolg Exit-Code `0`. Fehler von
`rsync` oder beim Kuma-Push führen zu einem Exit-Code ungleich `0`.

Ein Backup kann alternativ im Hintergrund gestartet werden:

```sh
docker compose exec -d rsync backup
docker compose logs -f rsync
```

Für manuelle Läufe ist `docker compose exec` praktisch, weil es den bereits
laufenden Container und dessen Mounts verwendet. Parallele Läufe auf dasselbe
Ziel sollten vermieden werden, da das Skript keine Sperrdatei verwaltet.

Nach Änderungen oder einem Image-Update:

```sh
docker compose pull
docker compose up -d
docker compose exec rsync backup
```

## Environment-Einstellungen

| Variable | Standard | Beschreibung |
| --- | --- | --- |
| `TZ` | `UTC` | Zeitzone für Cron, z. B. `Europe/Berlin` |
| `SCHEDULE` | `0 3 * * *` | Fünffeld-Cron-Ausdruck für den täglichen Lauf um 03:00 Uhr |
| `SOURCES` | leer | Mehrzeilige Liste im Format `name=/absoluter/pfad` |
| `BACKUP_DIR` | `/backup` | Zielverzeichnis im Container |
| `DELETE_EXTRANEOUS` | `true` | Nicht mehr vorhandene Dateien im Ziel löschen |
| `KUMA_BASE` | leer | Kuma-Basis-URL, z. B. `https://kuma.example` |
| `KUMA_TOKEN` | leer | Token des Kuma-Push-Monitors |

Jede Zeile in `SOURCES` erzeugt ein eigenes Zielverzeichnis unterhalb des
Backup-Ziels. Die Anzahl der Quellen ist nicht begrenzt. Leerzeilen und Zeilen,
die mit `#` beginnen, werden ignoriert. Für bestehende Installationen bleiben
`SOURCE_DIR` und `SERIES` als Einzelquellen-Fallback unterstützt.

Beispiel für die Konfiguration in `compose.yaml`:

```yaml
environment:
  TZ: Europe/Berlin
  SCHEDULE: "0 3 * * *"
  SOURCES: |
    docker-volumes=/source/docker-volumes
    appdata=/source/appdata
    documents=/source/documents
  BACKUP_DIR: /backup
  DELETE_EXTRANEOUS: "true"
  KUMA_BASE: "https://kuma.example"
  KUMA_TOKEN: "DEIN-TOKEN"
volumes:
  - /var/lib/docker/volumes:/source/docker-volumes:ro
  - /opt/appdata:/source/appdata:ro
  - /srv/documents:/source/documents:ro
  - /mnt/backup:/backup
```

Der Name links vom Gleichheitszeichen muss eindeutig sein und darf Buchstaben,
Zahlen, Punkte, Unterstriche, Bindestriche und Schrägstriche enthalten. Der Pfad
rechts davon ist der Mount-Pfad innerhalb des Containers.

Der Kuma-Aufruf erfolgt nach einem erfolgreichen Gesamtlauf als
`KUMA_BASE/api/push/KUMA_TOKEN?status=up&msg=ok`. Schlägt eine Quelle fehl, wird
`status=down` mit der URL-kodierten Fehlermeldung als `msg` gesendet. Ohne beide
Kuma-Variablen läuft das Backup ohne Monitoring weiter. `KUMA_URL` aus Version
1.1.0 wird übergangsweise weiterhin als Alias für `KUMA_BASE` akzeptiert.

Cron-Ausdrücke müssen in YAML als String geschrieben werden. Für eine andere
Häufigkeit kann beispielsweise `0 */6 * * *` verwendet werden.

`dockrsync` erstellt eine Spiegelkopie und keine versionierten Stände. Mit
`DELETE_EXTRANEOUS=true` wird `rsync --delete` verwendet: Dateien, die aus der
Quelle entfernt wurden, werden beim nächsten Lauf auch im Ziel gelöscht. Für
Snapshots oder Aufbewahrungsfristen muss das Ziel-Dateisystem eine eigene
Snapshot-Lösung bereitstellen.

## Architektur und Sicherheit

Debian trixie-slim installiert `rsync` sowie nur cron, curl und
tzdata als Laufzeitwerkzeuge. Der Scheduler läuft im Vordergrund, und SIGTERM
wird an ihn weitergereicht. Logs gehen nach stdout/stderr. Root bleibt absichtlich
der Standard: `rsync -aHAX --numeric-ids` soll Eigentümer, Rechte, Hardlinks,
ACLs, erweiterte Attribute und numerische Benutzer-IDs der
Quelle verlustfrei sichern; ein non-root-Betrieb ist nur mit bewusst passenden
UID/GID- und Mount-Rechten möglich. `no-new-privileges` verhindert dabei eine
nachträgliche Rechteausweitung innerhalb des Containers.

Der Beispiel-Mount `/var/lib/docker/volumes:/source/docker-volumes:ro` erlaubt das Sichern aller
Docker-Volumes, gibt dem Container aber auch lesenden Zugriff auf deren gesamten
Inhalt. Wenn nicht alle Volumes benötigt werden, sollten stattdessen nur die
gewünschten `_data`-Verzeichnisse einzeln und read-only eingebunden werden.

## Builds und Updates

GitHub Actions baut und veröffentlicht nach GHCR (`latest` auf `main`, versionierte
Tags bei `v*`) und führt reguläre Builds aus. Dependabot überwacht Docker-Basisimage
und Actions; ein wöchentlicher Workflow-Build berücksichtigt außerdem neue Debian-
Paketstände ohne Änderungen am Dockerfile. Vor dem Veröffentlichen blockiert ein
Trivy-Scan Images mit bekannten, bereits behebbaren kritischen Schwachstellen.
Veröffentlichte Images enthalten zusätzlich SBOM- und Provenance-Attestierungen.

Releases werden mit Release Please verwaltet. Änderungen auf `main` erstellen oder
aktualisieren automatisch einen Release-PR mit Versionsnummer und Changelog. Sobald
dieser PR zusammengeführt wird, werden der zugehörige `v*`-Tag und das GitHub Release
automatisch angelegt. Commit-Präfixe wie `fix:` und `feat:` bestimmen dabei, ob die
Patch- oder Minor-Version erhöht wird; `BREAKING CHANGE:` erzeugt eine Major-Version.

Lizenz: GPL-3.0-or-later.
