#!/bin/sh
set -eu

: "${SOURCE_DIR:=/source}"
: "${BACKUP_DIR:=/backup}"
: "${SERIES:=default}"
: "${KEEP_DAYS:=7}"
: "${KEEP_WEEKS:=4}"
: "${KEEP_MONTHS:=12}"

if [ ! -d "$SOURCE_DIR" ]; then
  echo "backup: source directory does not exist: $SOURCE_DIR" >&2
  exit 2
fi
mkdir -p "$BACKUP_DIR"

for value in "$KEEP_DAYS" "$KEEP_WEEKS" "$KEEP_MONTHS"; do
  case "$value" in
    ""|*[!0-9]*) echo "backup: retention values must be non-negative integers" >&2; exit 2 ;;
  esac
done

KEEP_WEEKS_DAYS=$((KEEP_WEEKS * 7))
KEEP_MONTHS_DAYS=$((KEEP_MONTHS * 30))
echo "backup: starting source=$SOURCE_DIR target=$BACKUP_DIR series=$SERIES retention=${KEEP_DAYS}d/${KEEP_WEEKS}w/${KEEP_MONTHS}m"

if storeBackup --sourceDir "$SOURCE_DIR" --backupDir "$BACKUP_DIR" \
    --series "$SERIES" \
    --keepAll "${KEEP_DAYS}d" \
    --keepLastOfWeek "${KEEP_WEEKS_DAYS}d" \
    --keepLastOfMonth "${KEEP_MONTHS_DAYS}d" \
    --logFile /dev/stdout; then
  echo "backup: storeBackup completed successfully"
else
  status=$?
  echo "backup: storeBackup failed with exit code $status" >&2
  exit "$status"
fi

if [ -n "${KUMA_PUSH_URL:-}" ]; then
  echo "backup: sending Uptime Kuma heartbeat"
  if ! curl --fail --silent --show-error --max-time 30 "$KUMA_PUSH_URL" >/dev/null; then
    echo "backup: Uptime Kuma push failed" >&2
    exit 1
  fi
fi
