#!/usr/bin/env bash
# Builds images locally and ships them to the server without a registry, for
# use before CI is set up or on a server too small to build on.
#   DEPLOY_TARGET=deploy@host [DEPLOY_PORT=22] [APP_DIR=../my-store] infra/scripts/release.sh [--sync-only]
# DEPLOY_TARGET can be a Host alias from ~/.ssh/config. Leave DEPLOY_PORT empty
# to use the port from there. --sync-only copies the compose file and scripts.
# APP_DIR builds the apps of another repository with the same layout (see
# "Deploying your own store code" in docs/deployment.md) instead of this one's.
set -euo pipefail
cd "$(dirname "$0")/../.."

target="${DEPLOY_TARGET:?set DEPLOY_TARGET, for example deploy@203.0.113.10}"
remote_dir=/opt/medusa
ssh_cmd=(ssh -o BatchMode=yes)
[ -z "${DEPLOY_PORT:-}" ] || ssh_cmd+=(-p "$DEPLOY_PORT")
ssh_cmd+=("$target")
app_dir="$(cd "${APP_DIR:-.}" && pwd)"
for f in apps/backend/Dockerfile apps/storefront/Dockerfile; do
  [ -f "$app_dir/$f" ] || { echo "$app_dir has no $f" >&2; exit 1; }
done
# The tag names the app commit, and says so when the build has uncommitted changes
dirty=""
[ -z "$(git -C "$app_dir" status --porcelain)" ] || dirty=-dirty
tag="$(git -C "$app_dir" rev-parse --short HEAD)$dirty-$(date -u +%Y%m%d%H%M%S)"

sync_files() {
  tar -czf - docker-compose.yml infra/docker infra/scripts | "${ssh_cmd[@]}" "tar -xzf - -C $remote_dir"
}
ship() { docker save "$1" | gzip -1 | "${ssh_cmd[@]}" 'gunzip | docker load'; }

if [ "${1:-}" = "--sync-only" ]; then
  sync_files
  echo "Copied docker-compose.yml and infra/ to $target:$remote_dir"
  exit 0
fi

domain="$("${ssh_cmd[@]}" "grep ^DOMAIN= $remote_dir/.env | cut -d= -f2")"
key="$("${ssh_cmd[@]}" "cd $remote_dir && infra/scripts/publishable-key.sh" 2>/dev/null || true)"

echo "Building $app_dir as $tag"
docker build -f "$app_dir/apps/backend/Dockerfile" -t "medusa-backend:$tag" "$app_dir"

sync_files
ship "medusa-backend:$tag"

if [ -z "$key" ]; then
  echo "First deploy: starting the backend to create the publishable key"
  "${ssh_cmd[@]}" "cd $remote_dir && sed -i 's|^BACKEND_IMAGE=.*|BACKEND_IMAGE=medusa-backend:$tag|' .env && docker compose up -d medusa-server medusa-worker"
  key="$("${ssh_cmd[@]}" "cd $remote_dir && infra/scripts/publishable-key.sh")"
fi

docker build -f "$app_dir/apps/storefront/Dockerfile" -t "medusa-storefront:$tag" \
  --build-arg "NEXT_PUBLIC_MEDUSA_BACKEND_URL=https://api.$domain" \
  --build-arg "NEXT_PUBLIC_BASE_URL=https://$domain" \
  --build-arg "NEXT_PUBLIC_MEDUSA_PUBLISHABLE_KEY=$key" "$app_dir"
ship "medusa-storefront:$tag"

"${ssh_cmd[@]}" "cd $remote_dir && infra/scripts/deploy.sh medusa-backend:$tag medusa-storefront:$tag"
