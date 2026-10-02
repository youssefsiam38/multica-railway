# Security

## What the template closes

| Upstream behaviour on a public URL | This template |
|---|---|
| `ALLOW_SIGNUP` defaults to `true`: anyone who finds the URL can request a code and create an account and workspaces. | `ALLOW_SIGNUP=false`; `ALLOWED_EMAILS` is a required input. Invited addresses can still sign up (upstream's own invitation allowance). The container refuses to start if nobody could sign in. |
| Plain deploy of the two images: the web app's rewrites cannot carry WebSocket upgrades, so live updates and agent daemons need a hand-made proxy, and the WebSocket origin allowlist defaults to `localhost` (`403` from any real domain). | Caddy routes `/ws` and the API paths to the API; `FRONTEND_ORIGIN` is the public URL. A request whose `Origin` equals its own `Host` (same-origin by definition; Railway routes only the service's domains here) is presented as the configured origin, so a domain rename doesn't silently break live updates. Cross-site origins are still refused. |
| `/health/realtime` serves metrics to any loopback caller; behind a same-host proxy every request is loopback. | Caddy answers `/health/*` with 404. |
| Behind a proxy the API sees one client IP for everyone. | Caddy sends the resolved client IP alone; `MULTICA_TRUSTED_PROXIES=127.0.0.1/32` makes the API trust it from loopback only. |
| `MULTICA_DEV_VERIFICATION_CODE` (a fixed code valid for every address) is honoured outside production. | `APP_ENV=production` is enforced and the variable is refused at start. |
| Telemetry on by default. | `DO_NOT_TRACK=true` (change it if you want to share the snapshot). |

## Sign-in codes

Multica signs people in with a six-digit emailed code (or Google, if configured). Without SMTP or Resend, upstream
prints codes and invitation links to the service log. Railway logs are visible only to members of your Railway
project, so this is safe for a one-person start, but configure email before inviting a team. Codes expire after 10
minutes, allow 5 attempts, and an address can request one per minute (enforced in PostgreSQL). Upstream's per-IP
auth rate limiter needs Redis, which this template does not include; the per-code limits above still apply.

## Trust boundaries

- **Caddy is the only public listener.** The web app binds `127.0.0.1:3001`. The API binds `:8081` on all
  interfaces (no upstream setting), so it is reachable on Railway's private network, which in this project holds
  only the database.
- **PostgreSQL** has no public domain.
- **Uploads** are served at `/uploads/<workspace>/<uuid>.<ext>` without a session, as upstream does for local
  storage: the URL is the capability. Don't paste upload links anywhere public.
- **Agents run on your teammates' machines**, not in this service, with the permissions of whoever runs the daemon.
  The server hands them short-lived task tokens scoped to the task's workspace.
- **Secrets** are generated per deploy. The four `*_SECRET_KEY` values encrypt stored integration credentials;
  losing or changing one makes those credentials unreadable.

## Reporting

Template issues: https://github.com/youssefsiam38/multica-railway/issues. Multica vulnerabilities: see
https://github.com/multica-ai/multica/security.
