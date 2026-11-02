#!/usr/bin/env bash
# Creates /opt/medusa/.env with random secrets. Refuses to overwrite: changing
# POSTGRES_PASSWORD after first start would lock the app out of its database.
#   DOMAIN=shop.example.com ACME_EMAIL=you@example.com bash init-env.sh
set -euo pipefail
cd "$(dirname "$0")/../.."

[ ! -e .env ] || { echo ".env already exists, not touching it" >&2; exit 1; }
: "${DOMAIN:?set DOMAIN}"

secret() { openssl rand -hex 32; }

umask 077
cat > .env <<EOF
DOMAIN=${DOMAIN}
ACME_EMAIL=${ACME_EMAIL:-}
TZ=UTC
BACKEND_IMAGE=medusa-backend:none
STOREFRONT_IMAGE=medusa-storefront:none
POSTGRES_USER=medusa
POSTGRES_DB=medusa
POSTGRES_PASSWORD=$(secret)
REDIS_PASSWORD=$(secret)
JWT_SECRET=$(secret)
COOKIE_SECRET=$(secret)
S3_BUCKET=
S3_REGION=
S3_ENDPOINT=
S3_FILE_URL=
S3_ACCESS_KEY_ID=
S3_SECRET_ACCESS_KEY=
SENDGRID_API_KEY=
SENDGRID_FROM=
EOF
echo "Wrote $(pwd)/.env"
