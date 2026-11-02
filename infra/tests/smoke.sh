#!/usr/bin/env bash
# Runs a first deploy of the production stack on this machine and checks it
# through nginx: routing, TLS, the store API, search, backup and restore, and
# the automatic rollback. Uses a self-signed certificate for shop.test.
#
# Meant for CI and throwaway machines. It writes .env and deletes the stack's
# volumes when it finishes, so it refuses to run where .env already exists.
#   infra/tests/smoke.sh [backend-image] [storefront-image-to-build]
set -euo pipefail
cd "$(dirname "$0")/../.."

domain=shop.test
backend="${1:-medusa-backend:smoke}"
storefront="${2:-medusa-storefront:smoke}"

[ ! -e .env ] || { echo ".env exists. This test would replace that stack's data, so it stops here." >&2; exit 1; }

work="$(mktemp -d)"
export BACKUP_DIR="$work/backups"
mkdir -p "$BACKUP_DIR"

finish() {
  status=$?
  if [ "$status" -ne 0 ]; then
    docker compose ps -a || true
    docker compose logs --tail 80 || true
  fi
  docker compose down -v --remove-orphans >/dev/null 2>&1 || true
  rm -rf .env "$work"
  [ "$status" -eq 0 ] && echo "Smoke test passed" || echo "Smoke test FAILED" >&2
  exit "$status"
}
trap finish EXIT

step() { printf '\n== %s\n' "$*"; }
fail() { echo "FAIL: $*" >&2; exit 1; }
# Every request goes to this machine with the self-signed certificate trusted
web() {
  curl -sS -m 20 --cacert "$work/cert.pem" \
    --resolve "$domain:443:127.0.0.1" --resolve "www.$domain:443:127.0.0.1" \
    --resolve "api.$domain:443:127.0.0.1" --resolve "$domain:80:127.0.0.1" "$@"
}
json() { python3 -c "import json,sys; d=json.load(sys.stdin); print($1)"; }

step "Configure"
DOMAIN="$domain" infra/scripts/init-env.sh >/dev/null
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes -days 2 \
  -subj "/CN=$domain" -addext "subjectAltName=DNS:$domain,DNS:www.$domain,DNS:api.$domain" \
  -keyout "$work/privkey.pem" -out "$work/cert.pem" 2>/dev/null
cp "$work/cert.pem" "$work/fullchain.pem"
docker compose run --rm --no-deps -v "$work:/src:ro" --entrypoint sh certbot -c \
  "mkdir -p /etc/letsencrypt/live/$domain && cp /src/fullchain.pem /src/privkey.pem /etc/letsencrypt/live/$domain/"

step "Backend"
if [ -z "${1:-}" ]; then
  docker build -q --load -f apps/backend/Dockerfile -t "$backend" . >/dev/null
fi
sed -i "s|^BACKEND_IMAGE=.*|BACKEND_IMAGE=$backend|" .env
docker compose up -d --wait medusa-server medusa-worker
key="$(infra/scripts/publishable-key.sh)"
echo "Publishable key created"

step "Storefront"
docker build -q --load -f apps/storefront/Dockerfile -t "$storefront" \
  --build-arg "NEXT_PUBLIC_MEDUSA_BACKEND_URL=https://api.$domain" \
  --build-arg "NEXT_PUBLIC_BASE_URL=https://$domain" \
  --build-arg "NEXT_PUBLIC_MEDUSA_PUBLISHABLE_KEY=$key" . >/dev/null

step "Deploy"
# deploy.sh checks health over HTTPS with certificate verification
CURL_CA_BUNDLE="$work/cert.pem" infra/scripts/deploy.sh "$backend" "$storefront"

step "Routing and TLS"
code="$(web -o /dev/null -w '%{http_code}' -L "https://$domain/")"
[ "$code" = 200 ] || fail "store home page returned $code"
redirect="$(web -o /dev/null -w '%{http_code} %{redirect_url}' "https://www.$domain/dk?x=1")"
[ "$redirect" = "301 https://$domain/dk?x=1" ] || fail "www redirect: $redirect"
redirect="$(web -o /dev/null -w '%{http_code} %{redirect_url}' "http://$domain/")"
[ "$redirect" = "301 https://$domain/" ] || fail "HTTP redirect: $redirect"
code="$(web -o /dev/null -w '%{http_code}' "http://$domain/.well-known/acme-challenge/missing")"
[ "$code" = 404 ] || fail "ACME challenge path returned $code"
web -I "https://$domain/" | grep -qi '^strict-transport-security:' || fail "HSTS header missing"
if curl -sS -m 10 -k -o /dev/null --resolve "other.test:443:127.0.0.1" https://other.test/ 2>/dev/null; then
  fail "an unknown hostname got a TLS response"
fi
code="$(web -o /dev/null -w '%{http_code}' "https://api.$domain/app")"
[ "$code" = 200 ] || fail "admin returned $code"

step "Store API"
count="$(web -H "x-publishable-api-key: $key" "https://api.$domain/store/products?limit=1" | json 'd["count"]')"
[ "$count" -gt 0 ] || fail "no products in the store API"
echo "$count products"
hits=0
# The search index is filled in the background after startup
for _ in $(seq 1 20); do
  hits="$(web -H "x-publishable-api-key: $key" -H 'content-type: application/json' \
    -d '{"entity":"product","pagination":{"take":1,"skip":0}}' \
    "https://api.$domain/store/search" | json 'd["results"][0]["metadata"]["count"]' || echo 0)"
  [ "$hits" -gt 0 ] && break
  sleep 3
done
[ "$hits" -gt 0 ] || fail "search returned no products"
echo "$hits products in search"
code="$(web -o /dev/null -w '%{http_code}' "https://api.$domain/store/products")"
[ "$code" = 400 ] || fail "store API without a key returned $code"

step "Isolation"
published="$(docker ps --filter label=com.docker.compose.project=medusa \
  --format '{{.Label "com.docker.compose.service"}} {{.Ports}}' | grep -- '->' | cut -d' ' -f1 | sort -u | tr '\n' ' ')"
[ "$published" = "nginx " ] || fail "services with published ports: $published"
[ "$(docker compose ps --status running --services | grep -cx medusa-worker)" = 1 ] || fail "worker is not running"

step "Backup and restore check"
ls "$BACKUP_DIR"/db-*.dump >/dev/null 2>&1 || fail "deploy took no backup"
infra/scripts/backup.sh
dump="$(ls -t "$BACKUP_DIR"/db-*.dump | head -1)"
check="$(infra/scripts/restore.sh "$dump" --check 2>&1)" || fail "restore check failed: $check"
grep -q '^products=[1-9]' <<<"$check" || fail "restore check found no products: $check"

step "Rollback"
docker tag alpine:3 medusa-storefront:broken 2>/dev/null || { docker pull -q alpine:3 >/dev/null; docker tag alpine:3 medusa-storefront:broken; }
if CURL_CA_BUNDLE="$work/cert.pem" infra/scripts/deploy.sh "$backend" medusa-storefront:broken; then
  fail "a broken release was reported as deployed"
fi
grep -qx "STOREFRONT_IMAGE=$storefront" .env || fail ".env does not point at the previous storefront"
code="$(web -o /dev/null -w '%{http_code}' "https://$domain/api/health")"
[ "$code" = 200 ] || fail "store is unhealthy after rollback ($code)"
docker image rm medusa-storefront:broken >/dev/null
