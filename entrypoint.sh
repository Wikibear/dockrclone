#!/bin/sh
set -eu

if [ "${1:-}" = "backup" ]; then
  exec /usr/local/bin/backup.sh
fi
if [ "$#" -gt 0 ]; then
  exec "$@"
fi

reject_multiline() {
  name=$1
  value=$2
  cr=$(printf '\r')
  case "$value" in
    *'
'*|*"$cr"*)
      echo "entrypoint: $name must not contain line breaks" >&2
      exit 2
      ;;
  esac
}

reject_multiline TZ "${TZ:-}"
reject_multiline SCHEDULE "${SCHEDULE:-}"
reject_multiline SOURCE_DIR "${SOURCE_DIR:-}"
reject_multiline BACKUP_DIR "${BACKUP_DIR:-}"
reject_multiline SERIES "${SERIES:-}"
reject_multiline KUMA_PUSH_URL "${KUMA_PUSH_URL:-}"

if ! printf '%s\n' "${SCHEDULE:-}" | grep -Eq '^[0-9*/,-]+[[:blank:]]+[0-9*/,-]+[[:blank:]]+[0-9*/,-]+[[:blank:]]+[0-9*/,-]+[[:blank:]]+[0-9*/,-]+$'; then
  echo "entrypoint: SCHEDULE must contain exactly five fields" >&2
  exit 2
fi

case "$TZ" in
  ""|/*|../*|*/../*|*/..)
    echo "entrypoint: invalid TZ: $TZ" >&2
    exit 2
    ;;
esac
if [ ! -f "/usr/share/zoneinfo/$TZ" ]; then
  echo "entrypoint: unknown timezone: $TZ" >&2
  exit 2
fi
case "$SOURCE_DIR:$BACKUP_DIR" in
  /*:/*) ;;
  *) echo "entrypoint: SOURCE_DIR and BACKUP_DIR must be absolute paths" >&2; exit 2 ;;
esac
case "$SERIES" in
  ""|/*|..|../*|*/../*|*/..)
    echo "entrypoint: SERIES must be a safe relative path" >&2
    exit 2
    ;;
esac
for value in "$KEEP_DAYS" "$KEEP_WEEKS" "$KEEP_MONTHS"; do
  case "$value" in
    ""|*[!0-9]*) echo "entrypoint: retention values must be non-negative integers" >&2; exit 2 ;;
  esac
done
case "${KUMA_PUSH_URL:-}" in
  ""|http://*|https://*) ;;
  *) echo "entrypoint: KUMA_PUSH_URL must use http or https" >&2; exit 2 ;;
esac

export TZ
ln -snf "/usr/share/zoneinfo/$TZ" /etc/localtime
printf 'SHELL=/bin/sh\nPATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin\nTZ=%s\n' "$TZ" > /etc/cron.d/storebackup
printf 'SOURCE_DIR=%s\nBACKUP_DIR=%s\nSERIES=%s\nKEEP_DAYS=%s\nKEEP_WEEKS=%s\nKEEP_MONTHS=%s\nKUMA_PUSH_URL=%s\n' \
  "$SOURCE_DIR" "$BACKUP_DIR" "$SERIES" "$KEEP_DAYS" "$KEEP_WEEKS" "$KEEP_MONTHS" "${KUMA_PUSH_URL:-}" \
  >> /etc/cron.d/storebackup
printf '%s root /usr/local/bin/backup.sh\n' "$SCHEDULE" >> /etc/cron.d/storebackup
chmod 0600 /etc/cron.d/storebackup

term() { echo 'entrypoint: stopping cron'; kill -TERM "$cron_pid" 2>/dev/null || true; }
trap term INT TERM
echo "entrypoint: schedule='$SCHEDULE' timezone='$TZ'"
cron -f &
cron_pid=$!
wait "$cron_pid"
