#!/usr/bin/env bash
# Brings the test server up to date with the repository: pulls the new code, rebuilds, applies
# database changes (migrations) and restarts. Takes a backup first.
set -euo pipefail
# shellcheck source=common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

say "Backup before the update"
"$ROOT/scripts/deploy/backup.sh"

say "Pulling the new code"
git -C "$ROOT" pull --ff-only

say "Rebuilding and restarting (migrations run first)"
compose up -d --build

SITE_ADDRESS="$(env_value SITE_ADDRESS)"
case "$SITE_ADDRESS" in
  :*) CHECK_URL="http://localhost:$(env_value HTTP_PORT)/api/v1/health/" ;;
  *)  CHECK_URL="https://$SITE_ADDRESS/api/v1/health/" ;;
esac
wait_healthy "$CHECK_URL" || fail "The server is not healthy after the update. Look at: cd infra && docker compose logs --tail 80"
say "Updated and healthy."
