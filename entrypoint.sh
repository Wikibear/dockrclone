#!/bin/sh
set -eu

if [ "${1:-}" = "config" ]; then
  shift
  exec /usr/local/bin/rclone config --config /config/rclone.conf "$@"
fi
if [ "${1:-}" = "rclone" ]; then
  shift
  exec /usr/local/bin/rclone --config=/config/rclone.conf "$@"
fi
if [ "${1:-}" = "backup" ]; then
  shift
  mkdir -p /run/dockrclone
  /usr/local/bin/jobs.py prepare
  exec /usr/local/bin/backup.sh "$@"
fi
if [ "${1:-}" = "validate" ]; then
  shift
  exec /usr/local/bin/jobs.py validate "$@"
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
reject_multiline KUMA_BASE "${KUMA_BASE:-}"
reject_multiline KUMA_URL "${KUMA_URL:-}"
reject_multiline KUMA_TOKEN "${KUMA_TOKEN:-}"

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
if [ ! -r /config/rclone.conf ]; then
  echo "entrypoint: /config/rclone.conf is missing or unreadable; mount a persistent rclone config directory" >&2
  exit 2
fi
KUMA_BASE=${KUMA_BASE:-${KUMA_URL:-}}
case "$KUMA_BASE" in
  ""|http://*|https://*) ;;
  *) echo "entrypoint: KUMA_BASE must use http or https" >&2; exit 2 ;;
esac
case "${KUMA_TOKEN:-}" in
  "") ;;
  *[!A-Za-z0-9_-]*) echo "entrypoint: KUMA_TOKEN contains unsupported characters" >&2; exit 2 ;;
esac
if { [ -n "$KUMA_BASE" ] && [ -z "${KUMA_TOKEN:-}" ]; } || \
   { [ -z "$KUMA_BASE" ] && [ -n "${KUMA_TOKEN:-}" ]; }; then
  echo "entrypoint: KUMA_BASE and KUMA_TOKEN must either both be set or both be empty" >&2
  exit 2
fi

export TZ
ln -snf "/usr/share/zoneinfo/$TZ" /etc/localtime
export KUMA_BASE KUMA_TOKEN
mkdir -p /run/dockrclone
/usr/local/bin/jobs.py prepare

term() { echo 'entrypoint: stopping cron'; kill -TERM "$cron_pid" 2>/dev/null || true; }
trap term INT TERM
echo "entrypoint: loaded jobs from /config/jobs.yml (timezone='$TZ')"
cron -f &
cron_pid=$!
wait "$cron_pid"
