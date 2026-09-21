#!/bin/sh
set -eu

: "${SOURCE_DIR:=/source}"
: "${BACKUP_DIR:=/backup}"
: "${SERIES:=default}"
: "${KEEP_DAYS:=7}"
: "${KEEP_WEEKS:=4}"
: "${KEEP_MONTHS:=12}"

mkdir -p "$BACKUP_DIR"

for value in "$KEEP_DAYS" "$KEEP_WEEKS" "$KEEP_MONTHS"; do
  case "$value" in
    ""|*[!0-9]*) echo "backup: retention values must be non-negative integers" >&2; exit 2 ;;
  esac
done

KUMA_BASE=${KUMA_BASE:-${KUMA_URL:-}}
case "$KUMA_BASE" in
  ""|http://*|https://*) ;;
  *) echo "backup: KUMA_BASE must use http or https" >&2; exit 2 ;;
esac
case "${KUMA_TOKEN:-}" in
  "") ;;
  *[!A-Za-z0-9_-]*) echo "backup: KUMA_TOKEN contains unsupported characters" >&2; exit 2 ;;
esac
if { [ -n "$KUMA_BASE" ] && [ -z "${KUMA_TOKEN:-}" ]; } || \
   { [ -z "$KUMA_BASE" ] && [ -n "${KUMA_TOKEN:-}" ]; }; then
  echo "backup: KUMA_BASE and KUMA_TOKEN must either both be set or both be empty" >&2
  exit 2
fi

kuma_push() {
  kuma_status=$1
  kuma_message=$2
  [ -n "$KUMA_BASE" ] || return 0
  curl --fail --silent --show-error --max-time 30 --proto '=http,https' \
    --get \
    --data-urlencode "status=$kuma_status" \
    --data-urlencode "msg=$kuma_message" \
    "${KUMA_BASE%/}/api/push/${KUMA_TOKEN}" >/dev/null
}

sources_tmp=
cleanup() { [ -z "$sources_tmp" ] || rm -f "$sources_tmp"; }
trap cleanup EXIT INT TERM

if [ -n "${SOURCES_FILE:-}" ] && [ -r "$SOURCES_FILE" ]; then
  sources_file=$SOURCES_FILE
else
  sources_tmp=$(mktemp)
  sources_file=$sources_tmp
  if [ -n "${SOURCES:-}" ]; then
    printf '%s\n' "$SOURCES" > "$sources_file"
  else
    printf '%s=%s\n' "$SERIES" "$SOURCE_DIR" > "$sources_file"
  fi
fi

KEEP_WEEKS_DAYS=$((KEEP_WEEKS * 7))
KEEP_MONTHS_DAYS=$((KEEP_MONTHS * 30))
source_count=0
seen_series='|'

while IFS= read -r source_line || [ -n "$source_line" ]; do
  case "$source_line" in
    ""|'#'*) continue ;;
    *=*) source_series=${source_line%%=*}; source_dir=${source_line#*=} ;;
    *) echo "backup: invalid SOURCES entry: $source_line" >&2; exit 2 ;;
  esac

  case "$source_series" in
    ""|/*|..|../*|*/../*|*/..|*[!A-Za-z0-9._/-]*)
      echo "backup: invalid source name: $source_series" >&2
      exit 2
      ;;
  esac
  case "$seen_series" in
    *"|$source_series|"*) echo "backup: duplicate source name: $source_series" >&2; exit 2 ;;
  esac
  case "$source_dir" in
    /*) ;;
    *) echo "backup: source path must be absolute: $source_dir" >&2; exit 2 ;;
  esac
  if [ ! -d "$source_dir" ]; then
    echo "backup: source directory does not exist: $source_dir" >&2
    kuma_push down "source '$source_series' does not exist" || echo "backup: Uptime Kuma error push failed" >&2
    exit 2
  fi

  seen_series="${seen_series}${source_series}|"
  source_count=$((source_count + 1))
  echo "backup: starting source=$source_dir target=$BACKUP_DIR series=$source_series retention=${KEEP_DAYS}d/${KEEP_WEEKS}w/${KEEP_MONTHS}m"

  if storeBackup --sourceDir "$source_dir" --backupDir "$BACKUP_DIR" \
      --series "$source_series" \
      --keepAll "${KEEP_DAYS}d" \
      --keepLastOfWeek "${KEEP_WEEKS_DAYS}d" \
      --keepLastOfMonth "${KEEP_MONTHS_DAYS}d" \
      --logFile /dev/stdout; then
    echo "backup: source '$source_series' completed successfully"
  else
    run_status=$?
    error_message="source '$source_series' failed with exit code $run_status"
    echo "backup: $error_message" >&2
    kuma_push down "$error_message" || echo "backup: Uptime Kuma error push failed" >&2
    exit "$run_status"
  fi
done < "$sources_file"

if [ "$source_count" -eq 0 ]; then
  echo "backup: SOURCES does not contain any source entries" >&2
  exit 2
fi

echo "backup: all $source_count source(s) completed successfully"
if [ -n "$KUMA_BASE" ]; then
  echo "backup: sending Uptime Kuma heartbeat"
  if ! kuma_push up ok; then
    echo "backup: Uptime Kuma push failed" >&2
    exit 1
  fi
fi
