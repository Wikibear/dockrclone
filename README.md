# dockrclone

A lightweight container for scheduled synchronization from local directories
to rclone remotes. rclone supports FTP, SFTP, WebDAV, and many cloud and object
storage services. The container also includes a cron schedule and optional
Uptime Kuma heartbeat.

## Setup

Create the persistent `config` directory in the project folder and configure
`rclone.conf` there. This file contains remote definitions and credentials, so
it is excluded from Git:

```sh
mkdir -p config
docker compose run --rm rclone config
```

This opens rclone's interactive configuration wizard. It will create a remote,
for example one named `backup`. Set `REMOTE_ROOT` in `compose.yaml` to that
remote name. The default `backup:` sends each source to
`backup:<source-name>`.

## Start and run a backup manually

```sh
docker compose config
docker compose up -d --build
docker compose exec rclone backup
docker compose logs -f rclone
```

You can also run rclone commands inside the running container. Pass the
configuration file explicitly:

```sh
docker compose exec rclone rclone --config=/config/rclone.conf listremotes
```

Before a real run, use `--dry-run` to preview the changes:

```sh
docker compose exec rclone rclone sync --dry-run \
  --config=/config/rclone.conf /source/appdata backup:appdata
```

The backup script processes each configured source in sequence. Avoid running
overlapping jobs against the same remote.

## Compose configuration

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

The host directory is intentionally named just `config`; rclone reads
`/config/rclone.conf` from it. Keep the file private with restricted file
permissions. Some OAuth remotes need to update tokens in the config file. For
those remotes, rclone needs write access to the directory, so the host file
permissions must allow the container's user to write there.

## Settings

| Variable | Default | Description |
| --- | --- | --- |
| `TZ` | `UTC` | Time zone used by cron |
| `SCHEDULE` | `0 3 * * *` | Five-field cron expression |
| `SOURCES` | empty | Multiline list in the format `name=/absolute/path` |
| `REMOTE_ROOT` | `backup:` | rclone destination root, e.g. `backup:` |
| `DELETE_EXTRANEOUS` | `true` | `true` uses `rclone sync`; `false` uses `rclone copy` and does not delete destination files |
| `KUMA_BASE` | empty | Uptime Kuma base URL |
| `KUMA_TOKEN` | empty | Uptime Kuma push token |

Each source is copied into a subdirectory under `REMOTE_ROOT`. With
`DELETE_EXTRANEOUS=true`, files missing from the source are deleted from the
destination. rclone does not delete destination files if a sync run encounters
errors. Use `rclone sync --dry-run` to preview a mirror operation without
making changes.

## Updates

Dependabot checks the pinned `rclone/rclone` Docker image version weekly and
opens an update pull request when a newer version is available. The scheduled
GitHub Actions build also refreshes the published image weekly. Image builds
pull the referenced base images before building. After local changes, rebuild
and restart the container with:

```sh
docker compose build --pull
docker compose up -d
```

The existing GitHub repository builds the container image and publishes it to
GHCR. The repository was renamed to `dockrclone`; it did not need to be deleted
or recreated.

License: GPL-3.0-or-later.
