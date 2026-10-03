#!/usr/bin/env bash
# shellcheck disable=SC2015,SC2016
# Static validation: syntax, shellcheck, compose, image pins and security defaults. No Docker build.
set -euo pipefail
REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd); export REPO_ROOT
cd "$REPO_ROOT"
# shellcheck source=tests/lib.sh
. "$REPO_ROOT/tests/lib.sh"

section "syntax"
for f in tests/*.sh images/multica/railway/supervisor.sh; do
  if bash -n "$f" 2>/dev/null; then pass "parses: $f"; else fail "syntax error: $f"; fi
done
for f in images/multica/railway/start.sh tests/fixtures/fake-claude.sh; do
  if sh -n "$f"; then pass "parses: $f (POSIX sh)"; else fail "syntax error: $f"; fi
done

section "shellcheck"
if command -v shellcheck >/dev/null; then
  if shellcheck -x -s bash tests/*.sh images/multica/railway/supervisor.sh; then pass "shellcheck bash"; else fail "shellcheck bash"; fi
  if shellcheck -s sh images/multica/railway/start.sh tests/fixtures/fake-claude.sh; then pass "shellcheck sh"; else fail "shellcheck sh"; fi
else
  echo "  SKIP  shellcheck not installed"
fi

section "compose"
if docker compose -f compose.yaml config -q; then pass "compose config"; else fail "compose config"; fi
cfg=$(docker compose -f compose.yaml config --format json)
assert_eq "two services" "db multica" "$(jq -r '[.services | keys[]] | sort | join(" ")' <<<"$cfg")"
assert_eq "only multica publishes a port" "multica" "$(jq -r '[.services | to_entries[] | select(.value.ports) | .key] | join(" ")' <<<"$cfg")"
assert_eq "the port binds to loopback" "127.0.0.1" "$(jq -r '[.services.multica.ports[]? | .host_ip] | join(" ")' <<<"$cfg")"
assert_eq "the published port is the front door (\$PORT)" "$(jq -r '.services.multica.environment.PORT' <<<"$cfg")" "$(jq -r '[.services.multica.ports[]? | .target] | join(" ")' <<<"$cfg")"
assert_eq "the uploads volume is mounted" "/data" "$(jq -r '[.services.multica.volumes[]? | .target] | join(" ")' <<<"$cfg")"
assert_contains "postgres is pinned by tag and digest" '^pgvector/pgvector:.*-pg17@sha256:[0-9a-f]\{64\}$' "$(jq -r '.services.db.image' <<<"$cfg")"
assert_contains "the DB connection string is set" '^postgres://' "$(jq -r '.services.multica.environment.DATABASE_URL' <<<"$cfg")"
assert_eq "sign-up is closed" "false" "$(jq -r '.services.multica.environment.ALLOW_SIGNUP' <<<"$cfg")"
assert_contains "the compose JWT secret is a placeholder" 'local-test-only' "$(jq -r '.services.multica.environment.JWT_SECRET' <<<"$cfg")"

section "image"
df=images/multica/Dockerfile
for a in MULTICA_BACKEND_IMAGE MULTICA_WEB_IMAGE CADDY_IMAGE; do
  assert_contains "$a pinned by tag and digest" "^ARG $a=.*:.*@sha256:[0-9a-f]\{64\}$" "$(grep "^ARG $a=" "$df")"
done
be=$(grep '^ARG MULTICA_BACKEND_IMAGE=' "$df" | sed 's/@.*//; s/.*://'); we=$(grep '^ARG MULTICA_WEB_IMAGE=' "$df" | sed 's/@.*//; s/.*://')
assert_eq "backend and web are the same Multica release" "$be" "$we"
assert_contains "production mode" 'APP_ENV=production' "$(cat "$df")"
assert_contains "sign-up closed by default" 'ALLOW_SIGNUP=false' "$(cat "$df")"
assert_contains "uploads on the volume" 'LOCAL_UPLOAD_DIR=/data/uploads' "$(cat "$df")"
assert_contains "tini is PID 1" '"/sbin/tini", "--"' "$(cat "$df")"
assert_contains "IANA zoneinfo installed for the API" '^RUN apk add .*\btzdata\b' "$(cat "$df")"
assert_contains "CA certificates installed for the API" '^RUN apk add .*\bca-certificates\b' "$(cat "$df")"
assert_contains "the build checks parity with the backend image's packages" 'COPY --from=backend /lib/apk/db/installed' "$(cat "$df")"
assert_contains "upstream licence ships in the repo" 'Multica License' "$(head -1 licenses/MULTICA-LICENSE)"

section "front door"
sup=images/multica/railway/supervisor.sh
cf=images/multica/railway/Caddyfile
st=images/multica/railway/start.sh
assert_contains "the web app binds loopback only" 'HOSTNAME=127.0.0.1' "$(cat "$sup")"
assert_contains "the web app gets no secrets" 'env -i' "$(cat "$sup")"
mig_line=$(grep -n '^./migrate up' "$sup" | cut -d: -f1)
caddy_line=$(grep -n '^caddy run' "$sup" | cut -d: -f1)
wait_line=$(grep -n '^wait_for "the web app"' "$sup" | cut -d: -f1)
if [ -n "$mig_line" ] && [ -n "$wait_line" ] && [ -n "$caddy_line" ] && [ "$mig_line" -lt "$wait_line" ] && [ "$wait_line" -lt "$caddy_line" ]; then
  pass "migrations, then API + web ready, then Caddy listens"
else
  fail "Caddy must start last"
fi
assert_contains "WebSockets go straight to the API" '@api path /api /api/\* /v1 /v1/\* /ws /ws/\*' "$(cat "$cf")"
assert_contains "loopback-trusting /health/* stays internal" '@internal path /health/\*' "$(cat "$cf")"
assert_contains "frames are not buffered" 'flush_interval -1' "$(cat "$cf")"
assert_contains "same-origin requests from another domain are normalized" 'request_header @same_origin_other_domain Origin {$MULTICA_PUBLIC_ORIGIN}' "$(cat "$cf")"
assert_contains "the admin API is off" 'admin off' "$(cat "$cf")"
assert_contains "refuses to start with nobody allowed in" 'ALLOWED_EMAILS is empty' "$(cat "$st")"
assert_eq "routine log lines go to stdout (Railway colours stderr as errors)" "0" "$(grep -c '^log() .*>&2' "$sup" "$st" | awk -F: '{s+=$2} END {print s}')"
assert_contains "refuses the fixed dev code" 'MULTICA_DEV_VERIFICATION_CODE must not be set' "$(cat "$st")"

section "secrets hygiene"
mapfile -t tracked < <(git ls-files 2>/dev/null | grep . || find . -type f -not -path './.git/*')
if [ "${#tracked[@]}" -gt 0 ] && grep -lE '(sk-ant-[A-Za-z0-9_-]{20,}|sk-[A-Za-z0-9]{32,}|ghp_[A-Za-z0-9]{30,}|mul_[0-9a-f]{40}|AKIA[0-9A-Z]{16}|-----BEGIN [A-Z ]*PRIVATE KEY-----)' "${tracked[@]}" 2>/dev/null; then
  fail "a credential-shaped string is in the repository"
else
  pass "no credential-shaped strings in ${#tracked[@]} files"
fi

summary
