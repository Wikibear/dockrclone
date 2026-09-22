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
reject_multiline REMOTE_ROOT "${REMOTE_ROOT:-}"
reject_multiline SERIES "${SERIES:-}"
reject_multiline DELETE_EXTRANEOUS "${DELETE_EXTRANEOUS:-}"
reject_multiline KUMA_BASE "${KUMA_BASE:-}"
reject_multiline KUMA_URL "${KUMA_URL:-}"
reject_multiline KUMA_TOKEN "${KUMA_TOKEN:-}"

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
case "$SOURCE_DIR" in /*) ;; *) echo "entrypoint: SOURCE_DIR must be an absolute path" >&2; exit 2 ;; esac
case "$SERIES" in
  ""|/*|..|../*|*/../*|*/..)
    echo "entrypoint: SERIES must be a safe relative path" >&2
    exit 2
    ;;
esac
case "${DELETE_EXTRANEOUS:-true}" in true|false) ;; *) echo "entrypoint: DELETE_EXTRANEOUS must be true or false" >&2; exit 2 ;; esac
case "${REMOTE_ROOT:-}" in
  ""|*:) ;;
  *) echo "entrypoint: REMOTE_ROOT must end in ':' (for example 'backup:')" >&2; exit 2 ;;
esac
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
printf '%s\n' "${SOURCES:-$SERIES=$SOURCE_DIR}" > /run/dockrclone.sources
chmod 0600 /run/dockrclone.sources
printf 'SHELL=/bin/sh\nPATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin\nTZ=%s\n' "$TZ" > /etc/cron.d/dockrclone
printf 'SOURCES_FILE=/run/dockrclone.sources\nREMOTE_ROOT=%s\nDELETE_EXTRANEOUS=%s\nKUMA_BASE=%s\nKUMA_TOKEN=%s\n' \
  "${REMOTE_ROOT:-}" "${DELETE_EXTRANEOUS:-true}" "$KUMA_BASE" "${KUMA_TOKEN:-}" \
  >> /etc/cron.d/dockrclone
printf '%s root /usr/local/bin/backup.sh\n' "$SCHEDULE" >> /etc/cron.d/dockrclone
chmod 0600 /etc/cron.d/dockrclone

term() { echo 'entrypoint: stopping cron'; kill -TERM "$cron_pid" 2>/dev/null || true; }
trap term INT TERM
echo "entrypoint: schedule='$SCHEDULE' timezone='$TZ'"
cron -f &
cron_pid=$!
wait "$cron_pid"
