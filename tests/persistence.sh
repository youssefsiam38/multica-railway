#!/usr/bin/env bash
# shellcheck disable=SC2015
# Persistence: data written before `compose down` (volumes kept) is still there after `compose up`, and the owner
# can still sign in. Mirrors a Railway redeploy of every service.
set -euo pipefail
REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd); export REPO_ROOT
# shellcheck source=tests/lib.sh
. "$REPO_ROOT/tests/lib.sh"

section "write"
compose up -d >/dev/null 2>&1 || die "compose up failed"
wait_for_code "$APP_URL/health" 200 || die "Multica never became healthy"
sign_in "$OWNER_EMAIL" "$TEST_TMP/o.jar" || die "owner sign-in failed: HTTP $CODE"
slug="persist-$(rand)"
req "$TOKEN" POST /api/workspaces "$(jq -nc --arg s "$slug" '{name:"Persist WS", slug:$s}')"
assert_eq "create a workspace" "201" "$CODE"
WS_ID=$(jq -r .id <<<"$BODY")
req "$TOKEN" POST /api/issues '{"title":"Persisted issue"}'
IID=$(jq -r .id <<<"$BODY")
printf 'persisted %s\n' "$(rand)" >"$TEST_TMP/p.txt"
req "$TOKEN" POST /api/upload-file "" -F "file=@$TEST_TMP/p.txt;type=text/plain"
assert_eq "upload a file" "200" "$CODE"
ATT=$(jq -r .id <<<"$BODY")

section "recreate every service, keep volumes"
compose down >/dev/null 2>&1
compose up -d >/dev/null 2>&1 || die "compose up failed"
wait_for_code "$APP_URL/health" 200 || die "Multica never came back"

section "read"
if sign_in "$OWNER_EMAIL" "$TEST_TMP/o.jar"; then pass "owner signs in after recreate"; else fail "owner sign-in: HTTP $CODE"; fi
req "$TOKEN" GET "/api/issues/$IID"
assert_eq "the issue survived" "Persisted issue" "$(jq -r .title <<<"$BODY")"
req "$TOKEN" GET "/api/attachments/$ATT/content"
assert_eq "the upload survived" "$(cat "$TEST_TMP/p.txt")" "$BODY"

summary
