#!/usr/bin/env bash
# Prints the store's publishable API key. It is public by design: the browser
# sends it with every store request.
set -euo pipefail
cd "$(dirname "$0")/../.."
set -a; . ./.env; set +a

for _ in $(seq 1 40); do
  key="$(docker compose exec -T postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -At \
    -c "SELECT token FROM api_key WHERE type='publishable' AND revoked_at IS NULL ORDER BY created_at LIMIT 1" 2>/dev/null || true)"
  if [ -n "$key" ]; then
    echo "$key"
    exit 0
  fi
  [ "${WAIT:-1}" = 1 ] || break
  sleep 3
done
echo "No publishable key found" >&2
exit 1
