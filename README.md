# dockrclone (Experimental)

A lightweight container for scheduled synchronization and backups from local
directories to rclone remotes. Each job has its own source, destination, mode,
and cron schedule, all configured in one YAML file.

## Setup

Create the persistent `config` directory and copy the example job list:

```sh
mkdir -p config
cp jobs.example.yml config/jobs.yml
```

Configure rclone remotes interactively. The wizard writes their connection
details to `config/rclone.conf`:

```sh
docker compose run --rm rclone config
```

The remote names used in `jobs.yml` must match the names in `rclone.conf`.
For example, `nas:backups/home` uses the remote named `nas`.

## Configure jobs

Edit `config/jobs.yml`. The repository includes this example:

```yaml
jobs:
  - name: nas-weekly
    schedule: "30 21 * * 0"
    source: /source/appdata
    destination: "nas:backups/appdata"
    mode: copy

  - name: server-nightly-mirror
    schedule: "0 2 * * *"
    source: /source/appdata
    destination: "server:mirror/appdata"
    mode: sync

  - name: cloud-monthly
    schedule: "0 3 1 * *"
    source: /source/appdata
    destination: "cloud:backups/appdata"
    mode: copy
```

Each job needs a unique `name`, a five-field cron `schedule`, an absolute
container `source` path, an rclone `destination`, and a `mode`:

- `copy` copies new and changed files without deleting files that exist only
  at the destination.
- `sync` mirrors the source and deletes destination files that are absent from
  the source.

Both `copy` and `sync` update files at the same destination path. A monthly
`copy` schedule by itself does not preserve a separate historical version of
each month. Use a versioned remote or distinct dated destinations if you need
point-in-time recovery.

Avoid scheduling jobs that write to the same destination at overlapping times.

Cron times use the timezone set by `TZ` in `compose.yaml`. The example uses
`Europe/Berlin`.

## Grant the container access to source directories

The `source` value is a path inside the container. Add a read-only volume mount
for each host directory the jobs need to access in `compose.yaml`. For example:

```yaml
volumes:
  - /var/lib/docker/volumes:/source/docker-volumes:ro
  - /opt/appdata:/source/appdata:ro
  - ./config:/config
```

Then refer to those container paths in `jobs.yml`, such as
`source: /source/appdata`. The YAML file describes the jobs; the Compose mounts
grant access to host data. The same source can be used by several jobs with
different schedules and destinations.

## Start and update schedules

Check the YAML and source paths, then start the container:

```sh
docker compose pull
docker compose run --rm rclone validate
docker compose up -d
```

At startup, the container reads `config/jobs.yml` and creates one cron entry
per job. Cron runs each job independently at its configured schedule.

After changing `jobs.yml`, validate it and restart the service to load the new
schedule and job settings. This does not rebuild the image:

```sh
docker compose run --rm rclone validate
docker compose restart rclone
```

The running container keeps the configuration snapshot it loaded at startup,
so a YAML edit takes effect after the restart.

## Run jobs manually

Run every configured job once, or pass a job name to run only that job:

```sh
docker compose exec rclone backup
docker compose exec rclone backup server-nightly-mirror
```

Follow the logs with:

```sh
docker compose logs -f rclone
```

To preview a mirror without changing anything, use rclone's dry-run option
with the configured remote:

```sh
docker compose exec rclone rclone sync --dry-run \
  --config=/config/rclone.conf /source/appdata server:mirror/appdata
```

## Compose configuration

The service configuration contains container-wide settings and host mounts.
Job schedules, destinations, and modes belong in `config/jobs.yml`.

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
      KUMA_BASE: ""
      KUMA_TOKEN: ""
    volumes:
      - /var/lib/docker/volumes:/source/docker-volumes:ro
      - /opt/appdata:/source/appdata:ro
      - ./config:/config
```

The host directory is intentionally named `config`. It contains `jobs.yml`
and `rclone.conf`. The latter stores remote credentials, is excluded from Git,
and should have restricted file permissions. Some OAuth remotes need to update
tokens, so the container may need write access to `rclone.conf`.

`KUMA_BASE` and `KUMA_TOKEN` are optional. If configured, each job sends its
success or failure to the Uptime Kuma push monitor when it runs.

## Updates

Dependabot checks the pinned `rclone/rclone` Docker image version weekly and
opens an update pull request when a newer version is available. The scheduled
GitHub Actions build also refreshes the published image weekly. Image builds
pull the referenced base images before building. After a new image is
published, update the container with:

```sh
docker compose pull
docker compose up -d
```

The existing GitHub repository builds the container image and publishes it to
GHCR. The repository was renamed to `dockrclone`; it did not need to be deleted
or recreated.

License: GPL-3.0-or-later.
