# Multica on Railway

A one-click Railway template for [Multica](https://github.com/multica-ai/multica), the open-source task board where
humans and AI coding agents (Claude Code, Codex, Cursor, OpenCode, Gemini and more) work as one team: assign an
issue to an agent the way you would to a colleague, and watch it pick the work up, comment and report back. It is a
community-maintained template and is not affiliated with Multica or Index Labs (Hong Kong) Limited.

What this template adds to a bare deploy of the official images:

- **Sign-up limited to you and the people you invite.** Stock Multica lets anyone who finds the URL create an
  account. Here only addresses in `ALLOWED_EMAILS` (or `ALLOWED_EMAIL_DOMAINS`) and invited teammates can, and the
  container refuses to start if nobody would be allowed in.
- **One URL for everything.** The browser, the `multica` CLI and the agent daemons all use the service's domain.
  A Caddy front door sends WebSockets and API paths straight to the API (the web app's rewrites cannot carry a
  WebSocket upgrade, so live updates and daemons fail on a plain deploy) and everything else to the web app.
- **Internet-facing configuration.** Production mode, a generated `JWT_SECRET`, Secure host-only cookies, the
  WebSocket origin allowlist set to your domain (and kept working after a Railway domain rename), the loopback-only
  realtime metrics endpoint kept off the public URL, encryption keys generated for the Git provider, plugin, Slack
  and Telegram integrations, and telemetry off.
- **Official images, unmodified.** `ghcr.io/multica-ai/multica-backend` and `multica-web`, pinned by digest, in one
  container; uploads on a volume; PostgreSQL 17 (pgvector, as upstream) on the private network.

## Services

| Service | Image | Public | Volume |
|---|---|---|---|
| `multica` | `ghcr.io/youssefsiam38/multica-railway` (official API + web app + Caddy) | yes, port 8080 | `/data` (uploads) |
| `db` | `pgvector/pgvector:0.8.7-pg17` | no | `/var/lib/postgresql` |

## After deploying

1. Open the service's domain and enter the email you put in `ALLOWED_EMAILS`.
2. **Get the sign-in code.** Without an email service, Multica writes it to the `multica` service's **Deploy Logs**
   (`[DEV] Verification code for you@example.com: 123456`; "DEV" is upstream's label for "printed, not emailed").
   To have codes and invitations emailed, set `SMTP_HOST`, `SMTP_PORT`, `SMTP_USERNAME`, `SMTP_PASSWORD` and
   `SMTP_FROM_EMAIL` (or `RESEND_API_KEY` and `RESEND_FROM_EMAIL`). Do this before inviting a team.
3. Create your workspace. Invite teammates under **Settings → Members**; an invited address can create its account
   even though sign-up is closed.
4. **Connect an agent runtime.** Agents run on a machine you control (your laptop, a dev box), not on Railway. On
   that machine install the CLI and at least one agent CLI (e.g. Claude Code), then:
   ```bash
   brew install multica-ai/tap/multica      # or: curl -fsSL https://raw.githubusercontent.com/multica-ai/multica/main/scripts/install.sh | bash
   multica setup self-host --server-url https://<your-domain> --app-url https://<your-domain>
   ```
   The runtime appears under **Settings → Runtimes**; create an agent on it and assign it an issue.

**Changing the domain.** A Railway domain rename or a new custom domain does not redeploy the service. The app and
live updates keep working on the new domain right away, but invitation links, webhook URLs and the daemon setup
command keep the old address until you set `MULTICA_APP_URL` to `https://your.domain` and redeploy.

## Variables

| Variable | Default | Notes |
|---|---|---|
| `ALLOWED_EMAILS` | *required input* | Who may create an account (comma-separated). Invited addresses may too. |
| `ALLOW_SIGNUP` | `false` | `true` = anyone with the URL can sign up (upstream default). |
| `MULTICA_APP_URL` | `https://${{RAILWAY_PUBLIC_DOMAIN}}` | Public origin for the app, API, WebSockets and webhooks. |
| `JWT_SECRET` | generated | Signs sessions. Changing it signs everyone out. |
| `MULTICA_VCS_SECRET_KEY`, `MULTICA_PLUGIN_SECRET_KEY`, `MULTICA_SLACK_SECRET_KEY`, `MULTICA_TELEGRAM_SECRET_KEY` | generated | Encrypt stored integration credentials and enable those integrations. **Never change** after use. |
| `MULTICA_VCS_INTEGRATION_ENABLED` | `true` | Forgejo / Gitea / GitLab integration. |
| `DO_NOT_TRACK` | `true` | Upstream sends a daily anonymous usage snapshot unless this is set. |
| `DATABASE_URL` | wired to `db` | |
| `PORT` | `8080` | The front door. Railway routes the domain and health check here. |
| `SMTP_*`, `RESEND_*` | unset | Email delivery for sign-in codes and invitations. |
| `ALLOWED_EMAIL_DOMAINS`, `DISABLE_WORKSPACE_CREATION`, `GOOGLE_CLIENT_ID`/`_SECRET`, `MULTICA_LLM_*` | unset | Optional upstream settings, passed through unchanged. |

Every other upstream variable (`SELF_HOSTING_ADVANCED.md`) can be added to the service and is passed through.

## Licence

The template's files are MIT (`LICENSE`). Multica itself is under the **Multica License** (Apache-2.0 plus
additional conditions, `licenses/MULTICA-LICENSE`): internal use within your organisation is free, but running a
Multica instance as a hosted service for third parties (even free of charge) needs a commercial licence from Index
Labs, and the Multica logo, name and copyright shown in the UI must not be removed. This template does neither.

## Repository

| Path | What |
|---|---|
| `images/multica/` | The wrapper image: Dockerfile, `start.sh`, `supervisor.sh`, `Caddyfile` |
| `compose.yaml` | Local stack that mirrors the Railway services |
| `tests/` | `static.sh`, `smoke.sh` (every product flow, including an agent daemon running a task), `persistence.sh`, `railway-smoke.sh` (live) |
| `marketplace/OVERVIEW.md` | The template page text |
| `RAILWAY_TEMPLATE.md` | The template's exact configuration |

See `ARCHITECTURE.md`, `SECURITY.md`, `UPSTREAM.md` and `MAINTENANCE.md`.
