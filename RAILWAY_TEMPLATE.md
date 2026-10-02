# Railway template configuration

The template's exact configuration. Reproduce it from this file if it ever has to be rebuilt.

| | |
|---|---|
| Name | Multica Self-Hosted |
| Code | `multica-self-hosted` |
| Template id | `a7c73a20-6c93-4963-b089-42f22793e1cc` |
| Deploy URL | https://railway.com/deploy/multica-self-hosted |
| Category | AI/ML |
| Card description | Humans and AI coding agents on one task board. Sign-up limited to you. |
| Icon | `assets/icon.png` |
| Overview markdown | `marketplace/OVERVIEW.md` (Railway enforces its section headings) |

Generated values use Railway's `secret()` function: `hexN` is `${{secret(N, "abcdef0123456789")}}` and `alnumN` is
`${{secret(N, "a-zA-Z0-9")}}` spelled out. Alphanumeric passwords are used wherever a value is embedded in a
connection URL, so nothing needs percent-encoding. Images are referenced by tag, because the template generator
rejects digests; `UPSTREAM.md` records the digests.

## Services

### `db`

| Field | Value |
|---|---|
| Source | `pgvector/pgvector:0.8.7-pg17` |
| Public domain | none |
| Volume | `/var/lib/postgresql` |
| Restart policy | on failure, 10 retries |

| Variable | Value |
|---|---|
| `POSTGRES_USER` | `multica` |
| `POSTGRES_DB` | `multica` |
| `POSTGRES_PASSWORD` | generated, alnum48 |

### `multica`

| Field | Value |
|---|---|
| Source | `ghcr.io/youssefsiam38/multica-railway:1.0.0` |
| Public domain | target port 8080 |
| Volume | `/data` |
| Healthcheck | `/health`, timeout from `RAILWAY_HEALTHCHECK_TIMEOUT_SEC` |
| Restart policy | on failure, 10 retries |

| Variable | Value |
|---|---|
| `ALLOWED_EMAILS` | required input, no default |
| `ALLOW_SIGNUP` | `false` |
| `MULTICA_APP_URL` | `https://${{RAILWAY_PUBLIC_DOMAIN}}` |
| `DATABASE_URL` | `postgres://multica:${{db.POSTGRES_PASSWORD}}@${{db.RAILWAY_PRIVATE_DOMAIN}}:5432/multica?sslmode=disable` |
| `JWT_SECRET` | generated, hex64 |
| `MULTICA_VCS_INTEGRATION_ENABLED` | `true` |
| `MULTICA_VCS_SECRET_KEY` | generated, base64 of 32 bytes (`${{secret(43, "a-zA-Z0-9+/")}}=`) |
| `MULTICA_PLUGIN_SECRET_KEY` | generated, base64 of 32 bytes (`${{secret(43, "a-zA-Z0-9+/")}}=`) |
| `MULTICA_SLACK_SECRET_KEY` | generated, base64 of 32 bytes (`${{secret(43, "a-zA-Z0-9+/")}}=`) |
| `MULTICA_TELEGRAM_SECRET_KEY` | generated, base64 of 32 bytes (`${{secret(43, "a-zA-Z0-9+/")}}=`) |
| `DO_NOT_TRACK` | `true` |
| `PORT` | `8080` |
| `RAILWAY_HEALTHCHECK_TIMEOUT_SEC` | `600` |
| `SMTP_HOST` | optional, unset |
| `SMTP_PORT` | optional, unset |
| `SMTP_USERNAME` | optional, unset |
| `SMTP_PASSWORD` | optional, unset |
| `SMTP_FROM_EMAIL` | optional, unset |
| `RESEND_API_KEY` | optional, unset |
| `RESEND_FROM_EMAIL` | optional, unset |
| `ALLOWED_EMAIL_DOMAINS` | optional, unset |
| `DISABLE_WORKSPACE_CREATION` | optional, unset |
| `GOOGLE_CLIENT_ID` | optional, unset |
| `GOOGLE_CLIENT_SECRET` | optional, unset |
| `MULTICA_LLM_API_KEY` | optional, unset |
| `MULTICA_LLM_BASE_URL` | optional, unset |
| `MULTICA_LLM_DEFAULT_MODEL` | optional, unset |

## Notes

- Required deploy input: `ALLOWED_EMAILS`. Headless: `railway deploy -t multica-self-hosted -v "multica.ALLOWED_EMAILS=you@example.com"`.
- Optional, unset by default: `SMTP_HOST`, `SMTP_PORT`, `SMTP_USERNAME`, `SMTP_PASSWORD`, `SMTP_FROM_EMAIL`,
  `RESEND_API_KEY`, `RESEND_FROM_EMAIL`, `ALLOWED_EMAIL_DOMAINS`, `DISABLE_WORKSPACE_CREATION`, `GOOGLE_CLIENT_ID`,
  `GOOGLE_CLIENT_SECRET`, `MULTICA_LLM_API_KEY`, `MULTICA_LLM_BASE_URL`, `MULTICA_LLM_DEFAULT_MODEL`.
- Rebuild: `_audit/spec_multica.py` with `_audit/tplkit.py` (`skeleton` → `railway templates create` → `patch_template`).
