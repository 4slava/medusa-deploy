#!/usr/bin/env bash
# Restores a backup over the live database and uploads, stopping the apps
# first. --check instead loads the dump into a scratch database and reports
# row counts, leaving live data alone.
#   restore.sh /var/backups/medusa/db-<stamp>.dump [--check]
set -euo pipefail
cd "$(dirname "$0")/../.."
set -a; . ./.env; set +a

dump="${1:?path to db-*.dump}"
mode="${2:-}"
[ -r "$dump" ] || { echo "Cannot read $dump" >&2; exit 1; }
psql() { docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" "$@"; }

if [ "$mode" = "--check" ]; then
  psql -d postgres -c 'DROP DATABASE IF EXISTS restore_check' -c 'CREATE DATABASE restore_check' >/dev/null
  docker compose exec -T postgres pg_restore -U "$POSTGRES_USER" -d restore_check --no-owner < "$dump"
  psql -d restore_check -At -c "SELECT 'products=' || count(*) FROM product" \
                           -c "SELECT 'orders=' || count(*) FROM \"order\"" \
                           -c "SELECT 'tables=' || count(*) FROM information_schema.tables WHERE table_schema='public'"
  psql -d postgres -c 'DROP DATABASE restore_check' >/dev/null
  exit 0
fi

read -r -p "Replace LIVE data on ${DOMAIN} with ${dump}? Type the domain to confirm: " answer
[ "$answer" = "$DOMAIN" ] || { echo "Aborted" >&2; exit 1; }

docker compose stop nginx storefront medusa-server medusa-worker
docker compose exec -T postgres pg_restore -U "$POSTGRES_USER" -d "$POSTGRES_DB" --clean --if-exists --no-owner < "$dump"

uploads="${dump/db-/uploads-}"
uploads="${uploads%.dump}.tgz"
if [ -r "$uploads" ]; then
  docker run --rm -i -v medusa_uploads:/uploads alpine sh -c 'rm -rf /uploads/* && tar -C /uploads -xzf -' < "$uploads"
fi

docker compose up -d
echo "Restored $dump"
