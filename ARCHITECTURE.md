# Architecture

```
browser / multica CLI / agent daemons (your machines)
        │ HTTPS + WSS, one origin
        ▼
Railway edge ──► multica service, :8080 (Caddy, the only public listener)
                   ├─ /api/*, /v1/*, /ws, /uploads/*, /auth/* (except callbacks), /health ──► API  :8081 (Go)
                   ├─ /health/*  ──► 404 (realtime metrics trust loopback callers)
                   └─ everything else ─────────────────────────────────────────────► web  127.0.0.1:3001 (Next.js)
                 API ──► db (PostgreSQL 17 + pgvector, private network)
                 API ──► /data/uploads (Railway volume)
```

## Start-up (`images/multica/railway/`)

1. `start.sh` (root, under tini) validates the inputs, derives `FRONTEND_ORIGIN`, `MULTICA_PUBLIC_URL` and
   `GOOGLE_REDIRECT_URI` from `MULTICA_APP_URL`, refuses to start wide open or with upstream's fixed dev code,
   prepares `/data/uploads` and drops to `nextjs`.
2. `supervisor.sh` runs upstream's `./migrate up` (as upstream's entrypoint does, with the same start-up budget),
   starts the API (`PORT=8081`) and the web app (`127.0.0.1:3001`, an empty environment except what it reads), waits
   for both, then starts Caddy on `$PORT`. Nothing answers on the public port until the API and the web app are
   ready, so Railway's health check (`/health`) passing means the whole stack is up.
3. If any of the three processes exits, the others are stopped and the container exits; Railway restarts it.

## Why one container

The backend and web images are both Alpine; the backend is static Go binaries. Copying them into the web image
(unmodified, same release) gives one origin without a second public service, avoids Railway's IPv6-only private
network (the web app binds IPv4), and keeps the WebSocket path short. The API itself binds all interfaces (upstream
has no bind-address setting); the only other service on the private network is the database.

## Agents

Multica does not run agents on the server. Each teammate runs the `multica` daemon next to their agent CLIs; it
registers runtimes, holds a WebSocket to `/api/daemon/ws`, claims tasks and calls the API with short-lived task
tokens. The smoke tests run a real daemon (the `multica` binary shipped in this image) with a stand-in Claude CLI
against the front door.
