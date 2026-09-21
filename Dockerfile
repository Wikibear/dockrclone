FROM debian:trixie-slim

ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update \
    && apt-get install --no-install-recommends -y storebackup cron curl tzdata \
    && rm -rf /var/lib/apt/lists/*

COPY backup.sh entrypoint.sh /usr/local/bin/
RUN chmod 0755 /usr/local/bin/backup.sh /usr/local/bin/entrypoint.sh

ENV TZ=UTC \
    SCHEDULE="0 3 * * *" \
    SOURCE_DIR=/source \
    BACKUP_DIR=/backup \
    SERIES=default \
    KEEP_DAYS=7 \
    KEEP_WEEKS=4 \
    KEEP_MONTHS=12

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
