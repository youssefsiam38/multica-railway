#!/usr/bin/env bash
# shellcheck disable=SC2015,SC2034
# Shared helpers for multica-railway tests. Source this file; do not execute it.
# Secrets are never echoed. Only names, counts, and pass/fail results are printed.

: "${APP_URL:=http://multica.test:${MULTICA_TEST_PORT:-18080}}"
: "${TEST_TIMEOUT:=600}"
: "${OWNER_EMAIL:=${MULTICA_TEST_OWNER_EMAIL:-owner@example.com}}"
# A shell command that prints the multica service's recent log. Without an email service, Multica writes sign-in
# codes and invitation links there. Locally that is `docker compose logs`; on Railway, the deployment log.
: "${LOGS_CMD:=docker compose -f ${REPO_ROOT:-.}/compose.yaml logs --no-color multica}"

# The local stack's public name is multica.test (see compose.yaml); point it at loopback without touching /etc/hosts.
CURL_EXTRA=()
case "$APP_URL" in
  http://multica.test:*) CURL_EXTRA=(--resolve "multica.test:${APP_URL##*:}:127.0.0.1") ;;
esac

TEST_TMP="${TEST_TMP:-$(mktemp -d)}"
export TEST_TMP
_PASS=0; _FAIL=0
CODE=""; BODY=""

pass() { _PASS=$((_PASS+1)); printf '  PASS  %s\n' "$*"; }
fail() { _FAIL=$((_FAIL+1)); printf '  FAIL  %s\n' "$*" >&2; }
die()  { printf 'FATAL: %s\n' "$*" >&2; exit 1; }
section() { printf '\n== %s ==\n' "$*"; }
summary() { printf '\n%d passed, %d failed\n' "$_PASS" "$_FAIL"; [ "$_FAIL" -eq 0 ]; }

assert_eq() { if [ "$2" = "$3" ]; then pass "$1 ($3)"; else fail "$1: expected [$2] got [$3]"; fi; }
assert_contains() { if grep -q -- "$2" <<<"$3"; then pass "$1"; else fail "$1: missing [$2]"; fi; }
assert_not_contains() { if grep -q -- "$2" <<<"$3"; then fail "$1: found forbidden [$2]"; else pass "$1"; fi; }

http_code() { curl -s -o /dev/null -w '%{http_code}' --max-time 30 "${CURL_EXTRA[@]}" "$@" || true; }

wait_for_code() {
  local url=$1 want=$2 timeout=${3:-$TEST_TIMEOUT} start code
  start=$(date +%s)
  while :; do
    code=$(http_code "$url")
    [ "$code" = "$want" ] && return 0
    if [ $(( $(date +%s) - start )) -ge "$timeout" ]; then printf 'timed out waiting for %s -> %s (last %s)\n' "$url" "$want" "$code" >&2; return 1; fi
    sleep 3
  done
}

compose() { docker compose -f "$REPO_ROOT/compose.yaml" "$@"; }

# req TOKEN METHOD PATH [JSON] [extra curl args...] -> sets CODE and BODY. TOKEN may be "" (anonymous).
# Requests carry the app's Origin, as a browser would, and the workspace in $WS_ID when set.
req() {
  local tok=$1 method=$2 path=$3 data=${4:-}
  shift 3; [ $# -gt 0 ] && shift
  local args=(-s -o "$TEST_TMP/body" -w '%{http_code}' --max-time 60 -X "$method" -H "Origin: $APP_URL" -H 'Accept: application/json')
  [ -n "$tok" ] && args+=(-H "Authorization: Bearer $tok")
  [ -n "${WS_ID:-}" ] && args+=(-H "X-Workspace-ID: $WS_ID")
  [ -n "$data" ] && args+=(-H 'Content-Type: application/json' --data "$data")
  CODE=$(curl "${args[@]}" "${CURL_EXTRA[@]}" "$@" "$APP_URL$path" || true)
  BODY=$(cat "$TEST_TMP/body" 2>/dev/null || true)
}

# send_code EMAIL -> sets CODE/BODY. The server allows one code per email per minute.
send_code() { req "" POST /auth/send-code "$(jq -nc --arg e "$1" '{email:$e}')"; }

# codes_from_logs EMAIL -> every sign-in code for EMAIL, oldest first, one per line. From the service log, or, with
# MAIL_URL (a Mailpit base URL) set, from the emails to EMAIL. Exits non-zero if the source could not be read, so a
# transient failure is never mistaken for "no codes yet".
codes_from_logs() {
  local e out
  if [ -n "${MAIL_URL:-}" ]; then
    out=$(curl -sf --max-time 20 "$MAIL_URL/api/v1/search?query=$(jq -rn --arg q "to:$1 subject:verification" '$q|@uri')&limit=50") || return 1
    local id
    for id in $(jq -r '.messages | reverse | .[].ID' <<<"$out"); do
      curl -sf --max-time 20 "$MAIL_URL/api/v1/message/$id" | jq -r '.HTML // .Text' | grep -o '>[0-9]\{6\}<' | head -1 | tr -d '<>'
    done
    return 0
  fi
  e=${1//./[.]}
  out=$(eval "$LOGS_CMD" 2>/dev/null) || return 1
  grep -o "Verification code for $e: [0-9]\{6\}" <<<"$out" | grep -o '[0-9]\{6\}$' || true
}

# code_count EMAIL -> how many codes have been issued to EMAIL so far (retries until the source is readable).
code_count() {
  local i out
  for i in $(seq 1 10); do
    if out=$(codes_from_logs "$1"); then grep -c . <<<"$out" || true; return 0; fi
    sleep 3
  done
  return 1
}

# invitation_link_from_logs EMAIL -> the newest invitation link logged for EMAIL.
invitation_link_from_logs() {
  { eval "$LOGS_CMD" 2>/dev/null || true; } | grep -o "Invitation email to $1: .*" | tail -1 | grep -o 'https\?://[^ ]*/invite/[0-9a-f-]*' || true
}

# sign_in EMAIL JAR -> 0 on success; prints nothing. Sets TOKEN to the session JWT and leaves cookies in JAR.
# Requests a code, reads it from the log (no email service configured) and verifies it, as a person would.
sign_in() {
  local email=$1 jar=$2 code="" before i out
  before=$(code_count "$email") || { CODE="log-unreadable"; return 1; }
  # One code per email per minute: wait out the limit if a previous step just asked for one.
  for i in $(seq 1 8); do
    send_code "$email"
    [ "$CODE" = "429" ] || break
    sleep 10
  done
  [ "$CODE" = "200" ] || return 1
  # Wait for a code newer than every code seen before the request (codes are logged in order).
  for i in $(seq 1 40); do
    if out=$(codes_from_logs "$email") && [ "$(grep -c . <<<"$out" || true)" -gt "$before" ]; then
      code=$(tail -1 <<<"$out"); break
    fi
    sleep 3
  done
  [ -n "$code" ] || { CODE="no-code-in-log"; return 1; }
  rm -f "$jar"
  CODE=$(curl -s -o "$TEST_TMP/body" -w '%{http_code}' --max-time 60 -c "$jar" -X POST -H "Origin: $APP_URL" \
    -H 'Content-Type: application/json' --data "$(jq -nc --arg e "$email" --arg c "$code" '{email:$e, code:$c}')" \
    "${CURL_EXTRA[@]}" "$APP_URL/auth/verify-code" || true)
  BODY=$(cat "$TEST_TMP/body")
  TOKEN=$(jq -r '.token // empty' <<<"$BODY")
  [ "$CODE" = "200" ] && [ -n "$TOKEN" ]
}

# ws_upgrade ORIGIN QUERY [JAR] [HOST_URL] -> HTTP status of a WebSocket handshake on /ws (101 on success).
ws_upgrade() {
  local origin=$1 query=$2 jar=${3:-} url=${4:-$APP_URL} args=()
  [ -n "$jar" ] && args+=(-b "$jar")
  curl -s -o /dev/null -w '%{http_code}' --max-time 5 --http1.1 "${CURL_EXTRA[@]}" "${args[@]}" \
    -H 'Connection: Upgrade' -H 'Upgrade: websocket' -H 'Sec-WebSocket-Version: 13' \
    -H 'Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==' -H "Origin: $origin" "$url/ws?$query" || true
}

# start_daemon NAME SERVER_URL PAT [docker args...] -> runs the Multica agent daemon (from the wrapper image, which
# ships the `multica` CLI) with the stand-in Claude CLI, as a non-root user, the way a teammate's machine would.
start_daemon() {
  local name=$1 url=$2 pat=$3; shift 3
  docker rm -f "$name" >/dev/null 2>&1 || true
  docker run -d --name "$name" --user 1001 -e HOME=/tmp -e MULTICA_SERVER_URL="$url" -e MULTICA_TOKEN_INPUT="$pat" \
    -v "$REPO_ROOT/tests/fixtures/fake-claude.sh:/usr/local/bin/claude:ro" "$@" \
    --entrypoint sh "${MULTICA_RAILWAY_IMAGE:-multica-railway:local}" \
    -c 'multica login --server-url "$MULTICA_SERVER_URL" --token "$MULTICA_TOKEN_INPUT" >/dev/null 2>&1 && unset MULTICA_TOKEN_INPUT && exec multica daemon start --foreground >/tmp/daemon.log 2>&1' >/dev/null
}

# run_agent_task TOKEN WS_ID TITLE -> 0 when an agent on the newest online runtime replies on a new issue.
run_agent_task() {
  local tok=$1 rt ag is i
  WS_ID=$2
  for i in $(seq 1 30); do
    req "$tok" GET /api/runtimes
    rt=$(jq -r '[.[]? | objects | select(.status == "online")] | last | .id // empty' <<<"$BODY" 2>/dev/null || true)
    [ -n "$rt" ] && break; sleep 2
  done
  [ -n "$rt" ] || { echo "no online runtime" >&2; return 1; }
  req "$tok" POST /api/agents "$(jq -nc --arg r "$rt" --arg n "Test agent $(rand)" '{name:$n, runtime_id:$r, visibility:"workspace"}')"
  ag=$(jq -r '.id // empty' <<<"$BODY"); [ -n "$ag" ] || { echo "agent create: HTTP $CODE" >&2; return 1; }
  req "$tok" POST /api/issues "$(jq -nc --arg t "$3" --arg a "$ag" '{title:$t, assignee_type:"agent", assignee_id:$a}')"
  is=$(jq -r '.id // empty' <<<"$BODY"); [ -n "$is" ] || { echo "issue create: HTTP $CODE" >&2; return 1; }
  for i in $(seq 1 40); do
    req "$tok" GET "/api/issues/$is/comments"
    grep -q 'fake-agent: task received' <<<"$BODY" && return 0
    sleep 3
  done
  echo "no agent reply on the issue" >&2; return 1
}

rand() { head -c 6 /dev/urandom | od -An -tx1 | tr -d ' \n'; }
