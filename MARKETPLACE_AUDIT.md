# Marketplace audit

## Identity

- Template: **Multica Self-Hosted** (code `multica-self-hosted`), a task board where humans and AI coding agents
  work together.
- Upstream: [multica-ai/multica](https://github.com/multica-ai/multica), ~52k stars, releases several times a week,
  official backend and web images on GHCR.
- Five other Multica templates existed on Railway (checked 2026-10-02; 11, 2, 1, 1 and 0 deploys). This one is
  differentiated by a single-origin front door that makes WebSockets and agent daemons work, closed sign-up with an
  allowlist that keeps invitations working, and live tests including a remote agent daemon.

## Licence

- Multica: the Multica License (Apache-2.0 plus additional conditions). Redistributing the unmodified images and the
  complete licence file is permitted; the template does not remove or change the UI's logo, name or copyright.
  Hosting Multica as a service for third parties needs a commercial licence from Index Labs; the README, overview
  and notices say so. Each deployer runs their own instance for their own organisation, which the licence allows.
- Caddy: Apache-2.0. PostgreSQL and pgvector: PostgreSQL License. See `THIRD_PARTY_NOTICES.md`.
- The icon is the template's own; the licence reserves Multica's branding. Non-affiliation notice in the README,
  overview, image label and notices.

## Security review

- **Closed sign-up by default** (`ALLOW_SIGNUP=false`, required `ALLOWED_EMAILS`); invitations still admit the
  invited address. The container refuses to start with nobody allowed in, with upstream's fixed dev code, or
  outside production mode.
- **One public listener (Caddy).** The web app binds loopback; the API binds all interfaces (no upstream option) on
  a private network that holds only the database. `/health/*` (loopback-trusting metrics) answers 404.
- **WebSocket origin check** set to the public URL; cross-site origins refused (tested); same-origin requests from a
  renamed domain still work (tested locally).
- **Generated secrets**: JWT secret, four integration encryption keys, PostgreSQL password. None in images or the
  repository; tests never print codes, tokens or cookies.
- **Sign-in codes** go to the service log until email is configured; disclosed in README, SECURITY and overview.
  Codes expire in 10 minutes with 5 attempts and one code per minute per address.
- **Disclosed**: upload URLs are capability URLs (upstream local storage); agents run on teammates' machines.
- Telemetry off by default (`DO_NOT_TRACK=true`).

## Tests

- `tests/static.sh` (41): syntax, shellcheck, compose shape, digest pins, same-release check, bind addresses,
  start-up order, front-door routing, guards, log streams, secret scan.
- `tests/smoke.sh` (43): start-up order, network exposure, closed sign-up, owner sign-in by logged code, workspace,
  issue, upload on the volume, WebSocket upgrade and origin checks, the invitation flow, a real `multica` daemon with
  a stand-in Claude CLI completing an assigned task through the front door, restart, start-up guards.
- `tests/persistence.sh` (5): issue, upload and sign-in survive recreating every service.
- `tests/railway-smoke.sh` (23, `--verify` 12): the same flows over HTTPS, with a daemon on another machine. Run on a
  clean-room deploy of the template (23/23), after redeploying both services (12/12), with SMTP delivery through a
  temporary Mailpit (21/21, codes and the invitation arrived by email), and on a deploy of the published code
  (23/23), 2026-10-02.

Not covered: a real LLM-backed agent against a provider; Google sign-in; Resend; the UI beyond request-level tests
(no browser clicking).

## Verdict

Shippable. Self-contained (Multica + PostgreSQL), reproducible (digest-pinned), sign-up closed, one URL for
browser, CLI and daemons.
