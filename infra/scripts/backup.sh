#!/usr/bin/env bash
# Dumps Postgres and the uploads volume to /var/backups/medusa. Runs nightly
# from the deploy user's crontab and before each deploy. These backups live on
# the same disk as the data: set BACKUP_REMOTE (an rsync target) to copy them
# off the server.
set -euo pipefail
cd "$(dirname "$0")/../.."
set -a; . ./.env; set +a

dir="${BACKUP_DIR:-/var/backups/medusa}"
stamp="$(date -u +%Y%m%dT%H%M%SZ)"
keep_days="${BACKUP_KEEP_DAYS:-14}"
umask 077

docker compose exec -T postgres pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Fc > "$dir/db-$stamp.dump.tmp"
mv "$dir/db-$stamp.dump.tmp" "$dir/db-$stamp.dump"
docker compose exec -T postgres pg_restore --list < "$dir/db-$stamp.dump" >/dev/null

docker run --rm -v medusa_uploads:/uploads:ro alpine tar -C /uploads -czf - . > "$dir/uploads-$stamp.tgz.tmp"
mv "$dir/uploads-$stamp.tgz.tmp" "$dir/uploads-$stamp.tgz"

find "$dir" -type f -mtime "+$keep_days" -delete

if [ -n "${BACKUP_REMOTE:-}" ]; then
  rsync -a "$dir/" "$BACKUP_REMOTE/"
fi

echo "Backup done: db-$stamp.dump ($(du -h "$dir/db-$stamp.dump" | cut -f1)), uploads-$stamp.tgz"
