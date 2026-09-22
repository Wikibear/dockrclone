FROM rclone/rclone:latest AS rclone

FROM debian:trixie-slim

ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update \
    && apt-get install --no-install-recommends -y cron curl tzdata \
    && rm -rf /var/lib/apt/lists/*

COPY --from=rclone /usr/local/bin/rclone /usr/local/bin/rclone
RUN mkdir -p /config
COPY backup.sh entrypoint.sh /usr/local/bin/
RUN chmod 0755 /usr/local/bin/backup.sh /usr/local/bin/entrypoint.sh

ENV TZ=UTC \
    SCHEDULE="0 3 * * *" \
    SOURCE_DIR=/source \
    REMOTE_ROOT=backup: \
    SERIES=default \
    DELETE_EXTRANEOUS=true

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
