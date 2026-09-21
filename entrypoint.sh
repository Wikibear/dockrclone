#!/bin/sh
set -eu

if [ "${1:-}" = "backup" ]; then
  exec /usr/local/bin/backup.sh
fi
if [ "$#" -gt 0 ]; then
  exec "$@"
fi

case "${SCHEDULE:-}" in
  ""|*[!0-9*/,-\ ]*)
    echo "entrypoint: SCHEDULE must be a five-field cron expression" >&2
    exit 2
    ;;
esac
if [ "$(printf '%s' "$SCHEDULE" | awk '{print NF}')" -ne 5 ]; then
  echo "entrypoint: SCHEDULE must contain exactly five fields" >&2
  exit 2
fi

export TZ
ln -snf "/usr/share/zoneinfo/$TZ" /etc/localtime
printf 'SHELL=/bin/sh\nPATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin\nTZ=%s\n' "$TZ" > /etc/cron.d/storebackup
env | awk -F= '/^(SOURCE_DIR|BACKUP_DIR|SERIES|KEEP_DAYS|KEEP_WEEKS|KEEP_MONTHS|KUMA_PUSH_URL)=/ { print $0 }' >> /etc/cron.d/storebackup
printf '%s root /usr/local/bin/backup.sh\n' "$SCHEDULE" >> /etc/cron.d/storebackup
chmod 0644 /etc/cron.d/storebackup

term() { echo 'entrypoint: stopping cron'; kill -TERM "$cron_pid" 2>/dev/null || true; }
trap term INT TERM
echo "entrypoint: schedule='$SCHEDULE' timezone='$TZ'"
cron -f &
cron_pid=$!
wait "$cron_pid"
