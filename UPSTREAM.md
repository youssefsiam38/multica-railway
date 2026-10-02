# Upstream and pinned versions

## Multica

- Project: https://github.com/multica-ai/multica
- Licence: Multica License, Apache-2.0 with additional conditions (`licenses/MULTICA-LICENSE`, `licenses/MULTICA-NOTICE`)
- Release: `v0.6.1` (2026-10-01), commit `2ea01ae4ef55de4310b99af192d2dbd367832883`
- `ghcr.io/multica-ai/multica-backend:v0.6.1` — digest `sha256:824d42a4a4436efad96a2d15354a5512786c895672ac48fa05f9b2be4d8fbd5c`
- `ghcr.io/multica-ai/multica-web:v0.6.1` — digest `sha256:cc8260b0371661896dce52f968c8822d8275e0b275a43484347e5a59efffbb7c`
- Used unmodified. The wrapper is `FROM` the web image and copies `server`, `migrate`, `multica`, `migrations/`,
  `LICENSE` and `NOTICE` from the backend image into `/opt/multica-backend`.

### Upstream contracts the wrapper depends on

Check these on every bump (the smoke test exercises all of them):

| Contract | Where upstream |
|---|---|
| Backend start = `./migrate up` then `./server` in a directory holding `migrations/`; `MULTICA_INTERNAL_DATABASE_STARTUP_STARTED_AT_UNIX` budget | `docker/entrypoint.sh` |
| Web start = `node apps/web/server.js` in `/app`; reads `HOSTNAME`, `PORT`, `REMOTE_API_URL`, `DOCS_URL` at run time | `Dockerfile.web`, `apps/web/config/runtime-urls.ts` |
| Backend paths: `/api`, `/v1`, `/ws`, `/uploads`, `/health`, `/auth/*` except `/auth/callback` and `/auth/hg-sso/callback` | `apps/web/config/runtime-urls.ts`, `server/cmd/server/router.go` |
| `/health/realtime` trusts loopback callers when `REALTIME_METRICS_TOKEN` is unset | `server/cmd/server/health_realtime.go` |
| `ALLOW_SIGNUP`, `ALLOWED_EMAILS`, `ALLOWED_EMAIL_DOMAINS`, pending-invitation allowance | `server/internal/handler/auth.go` (`checkSignupAllowed`) |
| Codes printed as `[DEV] Verification code for <email>: <code>` when no email backend | `server/internal/service/email.go` |
| Secure cookie follows the `FRONTEND_ORIGIN` scheme; WebSocket origin allowlist = `CORS_ALLOWED_ORIGINS` or `FRONTEND_ORIGIN` | `server/internal/auth/cookie.go`, `server/cmd/server/router.go` |
| Database extensions: `pgcrypto`, `pg_trgm` (required); `pg_cron`, `pg_bigm` optional | `server/migrations` |

## Caddy

- `caddy:2.10.2` (official), binary copied — digest `sha256:c3d7ee5d2b11f9dc54f947f68a734c84e9c9666c92c88a7f30b9cba5da182adb`

## PostgreSQL

- `pgvector/pgvector:0.8.7-pg17` (the image upstream's self-host compose uses) — digest
  `sha256:ac08538c6f8b9904c33c8224c5e5706dbe760aca29db1d096972b4052c22a75d`

## Refreshing a digest

```bash
gh api repos/multica-ai/multica/releases --jq '.[0:3][] | .tag_name + " " + .published_at'
docker buildx imagetools inspect ghcr.io/multica-ai/multica-backend:<tag> | sed -n 3p
docker buildx imagetools inspect ghcr.io/multica-ai/multica-web:<tag> | sed -n 3p
```
