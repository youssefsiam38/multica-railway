#!/usr/bin/env bash
# shellcheck disable=SC2015,SC2016
# Local end-to-end smoke test against a fresh compose stack (the image must already be built).
# Covers: start-up order, what is reachable from the network, closed sign-up, owner sign-in by emailed (logged) code,
# workspaces, issues, uploads, the invitation flow, live-update WebSockets (origin checks included), an agent daemon
# running a task through the front door, restart idempotency, and the start-up guards.
set -euo pipefail
REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd); export REPO_ROOT
# shellcheck source=tests/lib.sh
. "$REPO_ROOT/tests/lib.sh"

OWNER=$TEST_TMP/owner.jar
IMAGE=${MULTICA_RAILWAY_IMAGE:-multica-railway:local}
cleanup() { docker rm -f multica-test-daemon >/dev/null 2>&1 || true; }
trap cleanup EXIT

section "start-up"
compose down -v --remove-orphans >/dev/null 2>&1 || true
compose up -d >/dev/null 2>&1 || die "compose up failed"
wait_for_code "$APP_URL/health" 200 || { compose logs --tail 80 multica >&2; die "Multica never became healthy"; }
pass "front door answers /health"
logs=$(compose logs --no-color multica 2>&1)
assert_contains "migrations ran before start" "running database migrations" "$logs"
assert_contains "Caddy started after the API and web app" "API and web app are up" "$logs"
assert_contains "telemetry is off" "self-host telemetry disabled via DO_NOT_TRACK" "$logs"
assert_contains "the deployer is told where sign-in codes go" "sign-in codes and invitation links are written to this service's logs" "$logs"
assert_contains "VCS integration is on" "vcs integration enabled" "$logs"
assert_not_contains "plugin secrets are configured" "Plugin secrets disabled" "$logs"

section "what the network sees"
port=$(compose exec -T multica printenv PORT | tr -d '\r')
probe() { compose exec -T db bash -c "(echo > /dev/tcp/multica/$1) 2>/dev/null && echo open || echo closed" | tr -d '\r'; }
assert_eq "the front door is reachable" "open" "$(probe "$port")"
assert_eq "the web app's own port is not" "closed" "$(probe 3001)"
assert_eq "loopback-trusting realtime metrics stay internal" "404" "$(http_code "$APP_URL/health/realtime")"
assert_eq "the sign-in page is served" "200" "$(http_code "$APP_URL/login")"
req "" GET /api/config
assert_eq "the app reports sign-up as closed" "false" "$(jq -r .allow_signup <<<"$BODY")"
assert_eq "daemons are told to use the public URL" "$APP_URL" "$(jq -r .daemon_server_url <<<"$BODY")"

section "sign-up is closed"
send_code "stranger-$(rand)@example.com"
assert_eq "a stranger cannot get a sign-in code" "403" "$CODE"
send_code "Stranger-$(rand)@EXAMPLE.com"
assert_eq "case variants are refused too" "403" "$CODE"
req "" POST /auth/verify-code '{"email":"stranger@example.com","code":"888888"}'
assert_eq "a guessed code is refused" "400" "$CODE"

section "owner"
if sign_in "$OWNER_EMAIL" "$OWNER"; then pass "owner signs in with the code from the log"; else fail "owner sign-in: HTTP $CODE"; fi
OTOK=$TOKEN
req "$OTOK" GET /api/me
assert_eq "the session belongs to the owner" "$OWNER_EMAIL" "$(jq -r .email <<<"$BODY")"
assert_eq "the auth cookie is HttpOnly" "1" "$(grep -c '^#HttpOnly_.*multica_auth' "$OWNER")"
CODE=$(curl -s -o /dev/null -w '%{http_code}' -b "$OWNER" "${CURL_EXTRA[@]}" "$APP_URL/api/me")
assert_eq "the browser cookie works through the front door" "200" "$CODE"
slug="ws-$(rand)"
req "$OTOK" POST /api/workspaces "$(jq -nc --arg s "$slug" '{name:"Smoke WS", slug:$s}')"
assert_eq "create a workspace" "201" "$CODE"
WS_ID=$(jq -r .id <<<"$BODY")
req "$OTOK" POST /api/issues '{"title":"Smoke issue"}'
assert_eq "create an issue" "201" "$CODE"
printf 'smoke %s\n' "$(rand)" >"$TEST_TMP/u.txt"
req "$OTOK" POST /api/upload-file "" -F "file=@$TEST_TMP/u.txt;type=text/plain"
assert_eq "upload a file" "200" "$CODE"
url=$(jq -r .url <<<"$BODY"); att=$(jq -r .id <<<"$BODY")
assert_eq "the file is stored on the /data volume" "1" "$(compose exec -T multica sh -c "grep -rl '$(cat "$TEST_TMP/u.txt")' /data/uploads | wc -l" | tr -d '\r ')"
req "$OTOK" GET "/api/attachments/$att/content"
assert_eq "the upload reads back through the API" "$(cat "$TEST_TMP/u.txt")" "$BODY"
assert_eq "the upload URL is served by the API" "$(cat "$TEST_TMP/u.txt")" "$(curl -s "${CURL_EXTRA[@]}" "$APP_URL$url")"

section "live updates (WebSocket)"
assert_eq "the browser's WebSocket upgrades through the front door" "101" "$(ws_upgrade "$APP_URL" "workspace_id=$WS_ID" "$OWNER")"
assert_eq "a cross-site origin is refused" "403" "$(ws_upgrade "https://evil.example" "workspace_id=$WS_ID" "$OWNER")"
alt="http://other.test:${APP_URL##*:}"
alt_code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 --http1.1 --resolve "other.test:${APP_URL##*:}:127.0.0.1" -b "$OWNER" \
  -H 'Connection: Upgrade' -H 'Upgrade: websocket' -H 'Sec-WebSocket-Version: 13' -H 'Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==' \
  -H "Origin: $alt" "$alt/ws?workspace_id=$WS_ID" || true)
assert_eq "a renamed domain still gets live updates (same-origin)" "101" "$alt_code"

section "invitation"
INVITEE="invitee-$(rand)@example.com"
req "$OTOK" POST "/api/workspaces/$WS_ID/members" "$(jq -nc --arg e "$INVITEE" '{email:$e, role:"member"}')"
assert_eq "the owner invites a teammate" "201" "$CODE"
INV=$(jq -r .id <<<"$BODY")
assert_contains "the invitation link uses the public URL" "^$APP_URL/invite/$INV" "$(invitation_link_from_logs "$INVITEE")"
if sign_in "$INVITEE" "$TEST_TMP/inv.jar"; then pass "the invitee can sign up despite closed sign-up"; else fail "invitee sign-in: HTTP $CODE"; fi
ITOK=$TOKEN
WS_SAVE=$WS_ID; WS_ID=""
req "$ITOK" POST "/api/invitations/$INV/accept"
assert_eq "the invitee accepts" "200" "$CODE"
req "$ITOK" GET /api/workspaces
assert_contains "the invitee is a member" "$slug" "$BODY"
WS_ID=$WS_SAVE
req "$OTOK" GET "/api/workspaces/$WS_ID/members"
assert_eq "the workspace has two members" "2" "$(jq 'length' <<<"$BODY")"

section "agent daemon"
req "$OTOK" POST /api/tokens '{"name":"smoke daemon","expires_in_days":1}'
PAT=$(jq -r '.token // empty' <<<"$BODY")
[ -n "$PAT" ] && pass "a personal access token is issued" || fail "PAT: HTTP $CODE"
ip=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$(compose ps -q multica)")
start_daemon multica-test-daemon "$APP_URL" "$PAT" --network multica-railway-test --add-host "multica.test:$ip"
if run_agent_task "$OTOK" "$WS_ID" "Smoke agent task"; then pass "the daemon runs an agent task and the agent replies"; else fail "agent task"; fi
assert_contains "the daemon holds a WebSocket through the front door" "task wakeup websocket connected" "$(docker exec multica-test-daemon cat /tmp/.multica/daemon.log 2>/dev/null || true)"
cleanup

section "restart"
compose restart multica >/dev/null 2>&1
wait_for_code "$APP_URL/health" 200 || die "Multica did not come back"
req "$OTOK" GET /api/me
assert_eq "the session survives a restart" "200" "$CODE"

section "start-up guards"
guard() {
  docker run --rm --entrypoint /opt/multica-railway/start.sh -e DATABASE_URL=postgres://x -e JWT_SECRET=local-test-only-0123456789abcdef0123456789abcdef "$@" "$IMAGE" 2>&1 || true
}
assert_contains "refuses to start with nobody allowed in" "ALLOWED_EMAILS is empty" "$(guard -e MULTICA_APP_URL=https://x.example)"
assert_contains "refuses a URL without a scheme" "must start with https://" "$(guard -e MULTICA_APP_URL=x.example -e ALLOWED_EMAILS=a@b.c)"
assert_contains "refuses a short JWT secret" "JWT_SECRET must be at least 32" "$(guard -e MULTICA_APP_URL=https://x.example -e ALLOWED_EMAILS=a@b.c -e JWT_SECRET=short)"
assert_contains "refuses the fixed dev code" "MULTICA_DEV_VERIFICATION_CODE must not be set" "$(guard -e MULTICA_APP_URL=https://x.example -e ALLOWED_EMAILS=a@b.c -e MULTICA_DEV_VERIFICATION_CODE=888888)"

summary
