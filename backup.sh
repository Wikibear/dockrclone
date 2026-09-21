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

# storeBackup's native relative retention keeps one suitable backup in each age bucket.
KEEP_RELATIVE="1d ${KEEP_DAYS}d ${KEEP_WEEKS}w ${KEEP_MONTHS}m"
echo "backup: starting source=$SOURCE_DIR target=$BACKUP_DIR series=$SERIES retention='$KEEP_RELATIVE'"

if storeBackup --sourceDir "$SOURCE_DIR" --backupDir "$BACKUP_DIR" \
    --series "$SERIES" --keepRelative "$KEEP_RELATIVE" --logFile /dev/stdout; then
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
