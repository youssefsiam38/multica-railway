#!/bin/sh
# Railway start-up, first stage (runs as root under tini). Validates the template inputs, derives the URLs Multica
# needs from MULTICA_APP_URL, prepares the uploads volume, then drops to the unprivileged `nextjs` user.
set -eu

die() { printf 'multica-railway: %s\n' "$*" >&2; exit 1; }
log() { printf 'multica-railway: %s\n' "$*"; }

[ -n "${DATABASE_URL:-}" ] || die "DATABASE_URL is not set. This template uses the bundled PostgreSQL service."
secret=${JWT_SECRET:-}
[ "${#secret}" -ge 32 ] || die "JWT_SECRET must be at least 32 characters (generate one with: openssl rand -hex 32)."
unset secret

[ -n "${MULTICA_APP_URL:-}" ] || die "MULTICA_APP_URL is not set (e.g. https://your-app.up.railway.app)."
case "$MULTICA_APP_URL" in
  https://*|http://*) ;;
  *) die "MULTICA_APP_URL must start with https:// (got a value without a scheme)." ;;
esac
MULTICA_APP_URL=${MULTICA_APP_URL%/}
case "$MULTICA_APP_URL" in
  *://*/*) die "MULTICA_APP_URL must be an origin with no path (e.g. https://your-app.up.railway.app)." ;;
esac
# One public origin serves the app, the API, WebSockets and webhooks.
: "${FRONTEND_ORIGIN:=$MULTICA_APP_URL}"
: "${MULTICA_PUBLIC_URL:=$MULTICA_APP_URL}"
: "${GOOGLE_REDIRECT_URI:=$MULTICA_APP_URL/auth/callback}"
MULTICA_PUBLIC_ORIGIN=$MULTICA_APP_URL
export MULTICA_APP_URL FRONTEND_ORIGIN MULTICA_PUBLIC_URL GOOGLE_REDIRECT_URI MULTICA_PUBLIC_ORIGIN

# Who may create an account. Upstream's default is anyone; this template refuses to start wide open by accident.
if [ "${ALLOW_SIGNUP:-false}" != "true" ] && [ -z "${ALLOWED_EMAILS:-}" ] && [ -z "${ALLOWED_EMAIL_DOMAINS:-}" ]; then
  die "ALLOWED_EMAILS is empty: nobody could create the first account. Set it to your email address."
fi
[ -z "${MULTICA_DEV_VERIFICATION_CODE:-}" ] || die "MULTICA_DEV_VERIFICATION_CODE must not be set on a public instance."
[ "${APP_ENV:-production}" = "production" ] || die "APP_ENV must stay production on a public instance."

if [ -z "${SMTP_HOST:-}" ] && [ -z "${RESEND_API_KEY:-}" ]; then
  log "no email service configured: sign-in codes and invitation links are written to this service's logs."
fi

: "${LOCAL_UPLOAD_DIR:=/data/uploads}"
export LOCAL_UPLOAD_DIR
mkdir -p "$LOCAL_UPLOAD_DIR"
if [ "$(id -u)" -eq 0 ]; then
  chown nextjs "$LOCAL_UPLOAD_DIR"
  exec su-exec nextjs /opt/multica-railway/supervisor.sh
fi
exec /opt/multica-railway/supervisor.sh
