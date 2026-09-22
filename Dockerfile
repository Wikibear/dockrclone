FROM rclone/rclone:1.75.1 AS rclone

FROM debian:trixie-slim

ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update \
    && apt-get install --no-install-recommends -y cron python3 python3-yaml curl tzdata \
    && rm -rf /var/lib/apt/lists/*

COPY --from=rclone /usr/local/bin/rclone /usr/local/bin/rclone
RUN mkdir -p /config
COPY backup.sh entrypoint.sh jobs.py /usr/local/bin/
RUN chmod 0755 /usr/local/bin/backup.sh /usr/local/bin/entrypoint.sh /usr/local/bin/jobs.py

ENV TZ=UTC

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
