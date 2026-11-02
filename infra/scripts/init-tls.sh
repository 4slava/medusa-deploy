#!/usr/bin/env bash
# First-time Let's Encrypt certificate. nginx refuses to start without a
# certificate file, so serve the ACME challenge from a throwaway nginx on
# port 80, then let the real stack take over. Renewal is handled by the
# certbot service. Set STAGING=1 to test against the Let's Encrypt staging CA.
set -euo pipefail
cd "$(dirname "$0")/../.."
set -a; . ./.env; set +a

volume="$(docker volume ls -q --filter name=medusa_certs | head -1)"
if [ -n "$volume" ] && docker run --rm -v "$volume:/c:ro" alpine \
     test -f "/c/live/${DOMAIN}/fullchain.pem"; then
  echo "Certificate for ${DOMAIN} already exists"
  exit 0
fi

docker compose create certbot >/dev/null
docker rm -f acme-bootstrap >/dev/null 2>&1 || true
docker run -d --name acme-bootstrap -p 80:80 -v medusa_acme:/usr/share/nginx/html:ro nginx:1.30.6-alpine >/dev/null
trap 'docker rm -f acme-bootstrap >/dev/null' EXIT

email_args=(--register-unsafely-without-email)
[ -z "${ACME_EMAIL:-}" ] || email_args=(--email "$ACME_EMAIL")
staging_args=()
[ -z "${STAGING:-}" ] || staging_args=(--staging)

docker compose run --rm --no-deps --entrypoint certbot certbot certonly \
  --webroot -w /var/www/certbot --agree-tos --non-interactive \
  "${email_args[@]}" "${staging_args[@]}" \
  --cert-name "$DOMAIN" -d "$DOMAIN" -d "www.$DOMAIN" -d "api.$DOMAIN"
