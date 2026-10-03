# syntax=docker/dockerfile:1
#
# Multica for the Railway template: the official backend and web images, pinned by digest and used unmodified, in
# one container behind a Caddy front door (images/multica/railway/):
#
#   start.sh        validates the template inputs, prepares the uploads volume, drops to the unprivileged user
#   supervisor.sh   runs database migrations, starts the API and the web app on loopback, waits for both, and only
#                   then starts Caddy on $PORT
#   Caddyfile       the public front door: WebSockets and API paths go straight to the API (Next.js rewrites cannot
#                   carry a WebSocket upgrade), everything else to the web app; one origin for browser, CLI and daemon
#
# Not affiliated with Multica or Index Labs (Hong Kong) Limited.
ARG MULTICA_BACKEND_IMAGE=ghcr.io/multica-ai/multica-backend:v0.6.1@sha256:824d42a4a4436efad96a2d15354a5512786c895672ac48fa05f9b2be4d8fbd5c
ARG MULTICA_WEB_IMAGE=ghcr.io/multica-ai/multica-web:v0.6.1@sha256:cc8260b0371661896dce52f968c8822d8275e0b275a43484347e5a59efffbb7c
ARG CADDY_IMAGE=docker.io/library/caddy:2.10.2@sha256:c3d7ee5d2b11f9dc54f947f68a734c84e9c9666c92c88a7f30b9cba5da182adb

FROM ${CADDY_IMAGE} AS caddy
FROM ${MULTICA_BACKEND_IMAGE} AS backend

FROM ${MULTICA_WEB_IMAGE}
ARG WRAPPER_VERSION=0.0.0-dev
ARG VCS_REF=unknown
ARG BUILD_DATE=1970-01-01T00:00:00Z

USER root
# The API runs on the web image, so it needs the runtime packages the official backend image ships: tzdata (IANA
# zones for user timezones, autopilot schedules and wakeups) and ca-certificates. The parity check below enforces it.
RUN apk add --no-cache bash tini su-exec tzdata ca-certificates
COPY --from=caddy /usr/bin/caddy /usr/local/bin/caddy
# The backend's own files, at the layout its entrypoint expects (./migrate and ./server next to ./migrations).
COPY --from=backend /app/server /app/migrate /app/multica /opt/multica-backend/
COPY --from=backend /app/migrations/ /opt/multica-backend/migrations/
COPY --from=backend /app/LICENSE /app/NOTICE /opt/multica-backend/
# Parity guard: fail the build if any package installed in the backend image is missing here, so a pin bump that adds
# a backend runtime dependency breaks CI instead of the deployment.
COPY --from=backend /lib/apk/db/installed /tmp/backend-apk-installed
RUN missing=$(awk '/^P:/ { print substr($0, 3) }' /tmp/backend-apk-installed | while read -r p; do \
      apk info -e "$p" >/dev/null || echo "$p"; done) \
  && rm /tmp/backend-apk-installed \
  && if [ -n "$missing" ]; then echo "backend runtime packages missing from the image: $missing" >&2; exit 1; fi \
  && test -f /usr/share/zoneinfo/Africa/Cairo
COPY images/multica/railway/ /opt/multica-railway/
RUN chmod 0755 /opt/multica-railway/start.sh /opt/multica-railway/supervisor.sh \
  && chmod 0644 /opt/multica-railway/Caddyfile \
  && ln -s /opt/multica-backend/multica /usr/local/bin/multica \
  && PORT=8080 MULTICA_API_PORT=8081 MULTICA_WEB_PORT=3001 MULTICA_PUBLIC_ORIGIN=https://example.com \
     caddy validate --adapter caddyfile --config /opt/multica-railway/Caddyfile

# Internet-facing defaults. The API and the web app listen on loopback; only Caddy is public.
ENV APP_ENV=production \
    ALLOW_SIGNUP=false \
    LOCAL_UPLOAD_DIR=/data/uploads \
    MULTICA_API_PORT=8081 \
    MULTICA_WEB_PORT=3001 \
    MULTICA_TRUSTED_PROXIES=127.0.0.1/32 \
    PORT=8080 \
    XDG_DATA_HOME=/tmp/caddy-data \
    XDG_CONFIG_HOME=/tmp/caddy-config

LABEL org.opencontainers.image.title="multica-railway" \
      org.opencontainers.image.description="Multica for the Railway template: the official backend and web images pinned by digest, behind one front door, sign-up restricted. Not affiliated with Multica." \
      org.opencontainers.image.source="https://github.com/youssefsiam38/multica-railway" \
      org.opencontainers.image.licenses="MIT AND LicenseRef-Multica" \
      org.opencontainers.image.version="${WRAPPER_VERSION}" \
      org.opencontainers.image.revision="${VCS_REF}" \
      org.opencontainers.image.created="${BUILD_DATE}"

EXPOSE 8080
ENTRYPOINT ["/sbin/tini", "--", "/opt/multica-railway/start.sh"]
CMD []
