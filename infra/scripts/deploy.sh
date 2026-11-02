#!/usr/bin/env bash
# Runs on the server. Rolls the stack to a new image pair and reverts the
# images if it does not come up healthy.
#   deploy.sh <backend-image> <storefront-image>
#
# Rollback restores images only. Migrations are not reversed, so a release
# with a breaking migration needs the pre-deploy backup instead.
set -euo pipefail
cd "$(dirname "$0")/../.."

backend="${1:?backend image}"
storefront="${2:?storefront image}"

set_var() { sed -i "s|^$1=.*|$1=$2|" .env; }
current() { grep "^$1=" .env | cut -d= -f2-; }
healthy() {
  . ./.env
  curl -fsS -m 10 --resolve "api.$DOMAIN:443:127.0.0.1" "https://api.$DOMAIN/health" >/dev/null &&
  curl -fsS -m 10 --resolve "$DOMAIN:443:127.0.0.1" "https://$DOMAIN/api/health" >/dev/null
}
wait_healthy() {
  for _ in $(seq 1 40); do
    healthy && return 0
    sleep 3
  done
  return 1
}

previous_backend="$(current BACKEND_IMAGE)"
previous_storefront="$(current STOREFRONT_IMAGE)"

if docker compose ps --status running --services 2>/dev/null | grep -qx postgres; then
  infra/scripts/backup.sh
fi

set_var BACKEND_IMAGE "$backend"
set_var STOREFRONT_IMAGE "$storefront"

if docker compose up -d --remove-orphans && wait_healthy; then
  echo "Deployed $backend + $storefront"
  docker image prune -f >/dev/null
  exit 0
fi

echo "Release failed its health checks" >&2
docker compose ps -a >&2
docker compose logs --tail 40 medusa-server storefront >&2 || true

if [[ "$previous_backend" == *:none || "$previous_storefront" == *:none ]]; then
  echo "No previous release to roll back to" >&2
  exit 1
fi

echo "Rolling back to $previous_backend + $previous_storefront" >&2
set_var BACKEND_IMAGE "$previous_backend"
set_var STOREFRONT_IMAGE "$previous_storefront"
docker compose up -d --remove-orphans
wait_healthy && echo "Rollback healthy" >&2 || echo "Rollback is NOT healthy" >&2
exit 1
