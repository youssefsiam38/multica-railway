# Third-party notices

This template packages and runs the following third-party software. Each keeps its own licence; the template's own
files are MIT (see `LICENSE`).

## Multica

- Source: https://github.com/multica-ai/multica, © 2025-2026 Index Labs (Hong Kong) Limited
- Licence: the Multica License (Apache-2.0 plus additional conditions), complete text in `licenses/MULTICA-LICENSE`;
  attribution in `licenses/MULTICA-NOTICE`. Both also ship inside the image (`/app/LICENSE`, `/app/NOTICE`,
  `/opt/multica-backend/LICENSE`, `/opt/multica-backend/NOTICE`).
- Used unmodified from the official images `ghcr.io/multica-ai/multica-backend` and `ghcr.io/multica-ai/multica-web`
  (pinned in `UPSTREAM.md`). The Multica user interface, logo, name and copyright information are unchanged.
- Hosted or embedded commercial use for third parties requires a commercial licence from Index Labs
  (https://www.multica.ai/contact-sales). Internal use within one organisation does not.
- `assets/icon.png` is this template's own icon and does not reproduce Multica branding.

## Caddy

- Source: https://github.com/caddyserver/caddy, licence Apache-2.0. The official binary is copied unmodified.

## PostgreSQL and pgvector

- `pgvector/pgvector` image: PostgreSQL (PostgreSQL License) with pgvector (PostgreSQL License), used unmodified.
