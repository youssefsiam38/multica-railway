#!/usr/bin/env bash
# Railway start-up, second stage (runs as `nextjs`). Order matters:
#   1. database migrations (upstream's own `migrate up`, as in its entrypoint)
#   2. the API and the web app start on loopback
#   3. once both answer, Caddy starts on $PORT; only now is anything reachable from outside
# If any process exits, the others are stopped and the container exits so Railway restarts it.
set -euo pipefail

log() { printf 'multica-railway: %s\n' "$*"; }
fail() { printf 'multica-railway: %s\n' "$*" >&2; }

API_PORT=${MULTICA_API_PORT:-8081}
WEB_PORT=${MULTICA_WEB_PORT:-3001}
BOOT_TIMEOUT=${MULTICA_BOOT_TIMEOUT_SEC:-600}

pids=()
shutdown() {
  trap - TERM INT
  for pid in "${pids[@]}"; do kill -TERM "$pid" 2>/dev/null || true; done
  wait || true
}
trap 'shutdown; exit 143' TERM INT

# Upstream's entrypoint shares one database start-up budget between the migrator and the server.
MULTICA_INTERNAL_DATABASE_STARTUP_STARTED_AT_UNIX=$(date +%s)
export MULTICA_INTERNAL_DATABASE_STARTUP_STARTED_AT_UNIX

cd /opt/multica-backend
log "running database migrations"
./migrate up

PORT="$API_PORT" ./server &
pids+=("$!")

# The web app needs no secrets: give it only what it reads.
cd /app
env -i PATH="$PATH" HOME=/tmp NODE_ENV=production HOSTNAME=127.0.0.1 PORT="$WEB_PORT" \
  REMOTE_API_URL="http://127.0.0.1:$API_PORT" DOCS_URL="${DOCS_URL:-}" \
  node apps/web/server.js &
pids+=("$!")

wait_for() {
  local name=$1 url=$2 start
  start=$(date +%s)
  until wget -q -T 5 -O /dev/null "$url" 2>/dev/null; do
    for pid in "${pids[@]}"; do
      kill -0 "$pid" 2>/dev/null || { fail "$name start-up failed: a process exited"; shutdown; exit 1; }
    done
    if [ $(( $(date +%s) - start )) -ge "$BOOT_TIMEOUT" ]; then
      fail "$name did not answer within ${BOOT_TIMEOUT}s"; shutdown; exit 1
    fi
    sleep 1
  done
}
wait_for "the API" "http://127.0.0.1:$API_PORT/health"
wait_for "the web app" "http://127.0.0.1:$WEB_PORT/login"
log "API and web app are up"

caddy run --adapter caddyfile --config /opt/multica-railway/Caddyfile &
pids+=("$!")
log "listening on :${PORT} (public URL ${MULTICA_APP_URL})"

set +e
wait -n "${pids[@]}"
code=$?
set -e
fail "a process exited (code $code); stopping the others"
shutdown
exit "$code"
