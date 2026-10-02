# Maintenance

## Releasing a new version

1. **Bump the pins** (see `UPSTREAM.md`): `ARG MULTICA_BACKEND_IMAGE` and `ARG MULTICA_WEB_IMAGE` in
   `images/multica/Dockerfile` (always the same release), `UPSTREAM.md`. Re-read the "upstream contracts" table
   against the release diff, especially `apps/web/config/runtime-urls.ts` (which paths belong to the API) and
   `docker/entrypoint.sh`.
2. **Run the tests locally.**
   ```bash
   docker compose build
   tests/static.sh && tests/smoke.sh && tests/persistence.sh
   ```
3. **Tag and push.** `git tag vX.Y.Z && git push --tags`. The `publish-image` workflow re-runs the tests against the
   candidate and pushes `multica-railway` as `:X.Y.Z`, `:X.Y` and `:latest`.
4. **Update the template** image tag (see `RAILWAY_TEMPLATE.md`), deploy it into a scratch project and run
   `tests/railway-smoke.sh` against it before announcing.

Multica releases several times a week and migrates on start, so a bump is a redeploy.

## Rebuilding the Railway template

The exact configuration is in `RAILWAY_TEMPLATE.md`; the generator spec is `_audit/spec_multica.py` in the
workspace, used with `_audit/tplkit.py`. Volumes, domains and health checks are only set by the skeleton step.

## Gotchas

- **`PORT` is the front door** (8080, Caddy). The API is 8081 and the web app 3001; don't point the domain at them.
- **WebSockets must not go through the web app.** Next.js rewrites drop the upgrade. Any new backend path upstream
  adds to `runtime-urls.ts` belongs in the Caddyfile's `@api` matcher.
- **PostgreSQL volume on the parent dir.** Mount `/var/lib/postgresql`; Railway volumes contain `lost+found`, which
  `initdb` refuses as a data directory.
- **Domain renames don't redeploy.** `MULTICA_APP_URL` is resolved at deploy time; the Caddyfile's same-origin
  rewrite keeps the app working, links need a redeploy. Use `{http.request.hostport}` (not `host`) in that matcher.
- **One code per email per minute.** Tests that sign the same address in twice wait out the limit.
