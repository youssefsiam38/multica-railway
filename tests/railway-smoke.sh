#!/usr/bin/env bash
# shellcheck disable=SC2015,SC2016
# Live end-to-end test against a deployed template, over HTTPS.
#
#   APP_URL=https://<domain> OWNER_EMAIL=<an ALLOWED_EMAILS address> \
#     LOGS_CMD='<command printing the multica service log>' STATE_FILE=/tmp/multica-live.json \
#     tests/railway-smoke.sh                 # full run; records what it created in STATE_FILE
#   ... tests/railway-smoke.sh --verify      # after a redeploy: is it all still there?
#
# Sign-in codes come from the service log (no email service configured, the template default) or, with
# MAIL_URL=<Mailpit base URL> and SMTP configured on the service, from the delivered emails.
# Optional: SKIP_DAEMON=1 skips the agent-daemon run (it needs Docker and the wrapper image locally).
# Never prints codes, tokens or cookies.
set -euo pipefail
REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd); export REPO_ROOT
[ -n "${APP_URL:-}" ] || { echo "set APP_URL=https://<your-domain>" >&2; exit 2; }
[ -n "${OWNER_EMAIL:-}" ] || { echo "set OWNER_EMAIL (an address in ALLOWED_EMAILS)" >&2; exit 2; }
[ -n "${LOGS_CMD:-}" ] || [ -n "${MAIL_URL:-}" ] || { echo "set LOGS_CMD or MAIL_URL" >&2; exit 2; }
APP_URL=${APP_URL%/}
: "${STATE_FILE:=$(mktemp)}"
# shellcheck source=tests/lib.sh
. "$REPO_ROOT/tests/lib.sh"
MODE=${1:-full}
cleanup() { docker rm -f multica-live-daemon >/dev/null 2>&1 || true; }
trap cleanup EXIT

section "front door"
assert_eq "HTTPS /health" "200" "$(http_code "$APP_URL/health")"
assert_eq "the sign-in page is served" "200" "$(http_code "$APP_URL/login")"
assert_eq "loopback-trusting realtime metrics stay internal" "404" "$(http_code "$APP_URL/health/realtime")"
req "" GET /api/config
assert_eq "the app reports sign-up as closed" "false" "$(jq -r .allow_signup <<<"$BODY")"
assert_eq "daemons are told to use the public URL" "$APP_URL" "$(jq -r .daemon_server_url <<<"$BODY")"

section "owner"
if sign_in "$OWNER_EMAIL" "$TEST_TMP/owner.jar"; then pass "owner signs in over HTTPS with an emailed code"; else fail "owner sign-in: HTTP $CODE"; fi
OTOK=$TOKEN
req "$OTOK" GET /api/me
assert_eq "the session belongs to the owner" "$(tr '[:upper:]' '[:lower:]' <<<"$OWNER_EMAIL")" "$(jq -r .email <<<"$BODY")"
case "$APP_URL" in
  https://*) assert_eq "the auth cookie is Secure" "TRUE" "$(awk '$6 == "multica_auth" {print $4; exit}' "$TEST_TMP/owner.jar")" ;;
esac

if [ "$MODE" = "--verify" ]; then
  section "after redeploy"
  WS_ID=$(jq -r .workspaceId "$STATE_FILE")
  req "$OTOK" GET "/api/issues/$(jq -r .issueId "$STATE_FILE")"
  assert_eq "the issue survived" "$(jq -r .issueTitle "$STATE_FILE")" "$(jq -r .title <<<"$BODY")"
  req "$OTOK" GET "/api/attachments/$(jq -r .attachmentId "$STATE_FILE")/content"
  assert_eq "the upload survived (volume)" "$(jq -r .attachmentContent "$STATE_FILE")" "$BODY"
  if sign_in "$(jq -r .inviteeEmail "$STATE_FILE")" "$TEST_TMP/inv.jar"; then pass "the invited member signs in"; else fail "member sign-in: HTTP $CODE"; fi
  WS_ID=""; req "$TOKEN" GET /api/workspaces
  assert_contains "the member still belongs to the workspace" "$(jq -r .workspaceSlug "$STATE_FILE")" "$BODY"
  summary; exit $?
fi

section "sign-up is closed"
send_code "stranger-$(rand)@example.com"
assert_eq "a stranger cannot get a sign-in code" "403" "$CODE"

section "workspace, issue, upload"
slug="live-$(rand)"
req "$OTOK" POST /api/workspaces "$(jq -nc --arg s "$slug" '{name:"Live WS", slug:$s}')"
assert_eq "create a workspace" "201" "$CODE"
WS_ID=$(jq -r .id <<<"$BODY")
title="Live issue $(rand)"
req "$OTOK" POST /api/issues "$(jq -nc --arg t "$title" '{title:$t}')"
assert_eq "create an issue" "201" "$CODE"
IID=$(jq -r .id <<<"$BODY")
content="live upload $(rand)"; printf '%s' "$content" >"$TEST_TMP/u.txt"
req "$OTOK" POST /api/upload-file "" -F "file=@$TEST_TMP/u.txt;type=text/plain"
assert_eq "upload a file" "200" "$CODE"
ATT=$(jq -r .id <<<"$BODY"); url=$(jq -r .url <<<"$BODY")
req "$OTOK" GET "/api/attachments/$ATT/content"
assert_eq "the upload reads back" "$content" "$BODY"
assert_eq "the upload URL is served" "$content" "$(curl -s "${CURL_EXTRA[@]}" "$APP_URL$url")"

section "live updates (WebSocket)"
assert_eq "the browser's WebSocket upgrades over HTTPS" "101" "$(ws_upgrade "$APP_URL" "workspace_id=$WS_ID" "$TEST_TMP/owner.jar")"
assert_eq "a cross-site origin is refused" "403" "$(ws_upgrade "https://evil.example" "workspace_id=$WS_ID" "$TEST_TMP/owner.jar")"

section "invitation"
INVITEE="invitee-$(rand)@example.com"
req "$OTOK" POST "/api/workspaces/$WS_ID/members" "$(jq -nc --arg e "$INVITEE" '{email:$e, role:"member"}')"
assert_eq "the owner invites a teammate" "201" "$CODE"
INV=$(jq -r .id <<<"$BODY")
if [ -n "${MAIL_URL:-}" ]; then
  sleep 3
  inv_mail=$(curl -s "$MAIL_URL/api/v1/search?query=$(jq -rn --arg q "to:$INVITEE" '$q|@uri')&limit=5" | jq -r '[.messages[].Subject] | join(" | ")')
  assert_contains "the invitation is emailed" "invited" "$inv_mail"
else
  assert_contains "the invitation link uses the public URL" "^$APP_URL/invite/$INV" "$(invitation_link_from_logs "$INVITEE")"
fi
if sign_in "$INVITEE" "$TEST_TMP/inv.jar"; then pass "the invitee signs up despite closed sign-up"; else fail "invitee sign-in: HTTP $CODE"; fi
ITOK=$TOKEN; WS_SAVE=$WS_ID; WS_ID=""
req "$ITOK" POST "/api/invitations/$INV/accept"
assert_eq "the invitee accepts" "200" "$CODE"
WS_ID=$WS_SAVE
req "$OTOK" GET "/api/workspaces/$WS_ID/members"
assert_eq "the workspace has two members" "2" "$(jq 'length' <<<"$BODY")"

if [ -z "${SKIP_DAEMON:-}" ]; then
  section "agent daemon over the internet"
  req "$OTOK" POST /api/tokens '{"name":"live daemon","expires_in_days":1}'
  PAT=$(jq -r '.token // empty' <<<"$BODY")
  start_daemon multica-live-daemon "$APP_URL" "$PAT"
  if run_agent_task "$OTOK" "$WS_ID" "Live agent task"; then pass "a remote daemon runs an agent task and the agent replies"; else fail "agent task"; fi
  assert_contains "the daemon holds a WSS connection" "task wakeup websocket connected" "$(docker exec multica-live-daemon cat /tmp/.multica/daemon.log 2>/dev/null || true)"
  cleanup
fi

jq -n --arg w "$WS_ID" --arg s "$slug" --arg i "$IID" --arg t "$title" --arg a "$ATT" --arg c "$content" --arg e "$INVITEE" \
  '{workspaceId:$w, workspaceSlug:$s, issueId:$i, issueTitle:$t, attachmentId:$a, attachmentContent:$c, inviteeEmail:$e}' >"$STATE_FILE"
summary
