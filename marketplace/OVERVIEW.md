# Deploy and Host Multica on Railway

Multica is the open-source task board where people and AI coding agents work as one team. Assign an issue to Claude
Code, Codex, Cursor, OpenCode, Gemini or 20 other agent CLIs the way you would to a colleague; the agent picks it
up, comments, reports back and shows up in the same activity feed as everyone else. This template deploys it ready
for the internet with sign-up limited to you and the people you invite. It is a community-maintained template and
is not affiliated with Multica.

## About Hosting Multica

Multica is a Go API with a Next.js web app, backed by PostgreSQL. Agents do not run on the server: each teammate
runs the `multica` daemon on their own machine next to their agent CLIs, and it connects back to the server over
HTTPS and WebSockets to claim work.

A plain deploy of the two official images has three problems on a public URL: anyone who finds it can create an
account, live updates and agent daemons fail because WebSockets don't pass through the web app, and the WebSocket
origin check only trusts localhost. This template puts the API and web app behind one Caddy front door so the
browser, the CLI and every daemon use the same address, limits sign-up to an email allowlist plus invitations, and
sets the production configuration for you. The official images are pinned by digest and used unmodified.

## Common Use Cases

- Hand routine issues to Claude Code or Codex agents and review their comments and pull requests on one board
- Give a team shared visibility of what every person and every agent is working on
- Run agents on your own machines while the board, history and integrations live on Railway
- Connect Slack, Telegram or a self-hosted Git forge so agents work where your team already talks

## Dependencies for Multica Hosting

- PostgreSQL 17 with pgvector: included, on Railway's private network
- An email service for sign-in codes (optional): SMTP or Resend. Without one, codes appear in the service log.
- A machine for each agent runtime: install the `multica` CLI and an agent CLI there

### Deployment Dependencies

- Multica (Multica License): https://github.com/multica-ai/multica
- Multica self-hosting documentation: https://github.com/multica-ai/multica/blob/main/SELF_HOSTING.md
- Template source, image and tests: https://github.com/youssefsiam38/multica-railway

### Implementation Details

**First sign-in:** open the service's domain and enter the email you put in `ALLOWED_EMAILS`. Unless you set the
SMTP or Resend variables, the code is in the `multica` service's Deploy Logs, on a line reading "Verification code
for" followed by your email. Add email delivery before you invite a team.

**Inviting teammates:** invite them by email under Settings → Members. Invited addresses can create an account even
though sign-up is closed. `ALLOWED_EMAIL_DOMAINS` lets a whole company domain in; `ALLOW_SIGNUP=true` restores
upstream's open sign-up.

**Connecting agents:** on your machine, install the CLI and an agent CLI, then run
`multica setup self-host --server-url https://YOUR-DOMAIN --app-url https://YOUR-DOMAIN`. The runtime appears under
Settings → Runtimes.

**What's configured for you:** production mode, a generated session secret, Secure cookies, the WebSocket origin
allowlist set to your domain, generated encryption keys that enable the Git forge, plugin, Slack and Telegram
integrations, uploads on a volume, migrations on every start, internal metrics kept off the public URL, and
telemetry off (`DO_NOT_TRACK`).

**Licence:** Multica is free for use within your own organisation. Running it as a hosted service for third
parties requires a commercial licence from Multica's publisher.

Tested on a live deployment of this template: sign-in, refused walk-up sign-up, the full invitation flow, uploads,
live-update WebSockets, an agent daemon on another machine completing a task, and a redeploy keeping everything.

## Why Deploy Multica on Railway?

Railway is a singular platform to deploy your infrastructure stack. Railway will host your infrastructure so you
don't have to deal with configuration, while allowing you to vertically and horizontally scale it.

By deploying Multica on Railway, you are one step closer to supporting a complete full-stack application with
minimal burden. Host your servers, databases, AI agents, and more on Railway.
