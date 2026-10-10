#!/usr/bin/env bash
# Restores a backup made by backup.sh into THIS server, replacing what is there:
#
#     bash scripts/deploy/restore.sh infra/backups/db-20261009-0330.sql.gz [infra/backups/files-20261009-0330.tar.gz]
#
# Use it to move the data to a new server too: set the new server up with bootstrap_vm.sh (it creates
# an empty business: this replaces it), copy the two files over, run this.
set -euo pipefail
# shellcheck source=common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

DB_DUMP="${1:-}"; FILES="${2:-}"
[ -f "$DB_DUMP" ] || fail "Usage: restore.sh <db-....sql.gz> [files-....tar.gz]"
[ -z "$FILES" ] || [ -f "$FILES" ] || fail "File not found: $FILES"
DB_USER="$(env_value POSTGRES_USER)"; DB_NAME="$(env_value POSTGRES_DB)"

say "This REPLACES all data on this server with the backup."
read -r -p "   Type 'restore' to go on: " answer
[ "$answer" = "restore" ] || fail "Not confirmed."

say "Stopping the API"
compose stop api
say "Loading the database"
compose exec -T db psql -U "${DB_USER:-erp}" -d postgres -c "DROP DATABASE IF EXISTS ${DB_NAME:-erp}" -c "CREATE DATABASE ${DB_NAME:-erp}"
gunzip -c "$DB_DUMP" | compose exec -T db psql -U "${DB_USER:-erp}" -d "${DB_NAME:-erp}" -v ON_ERROR_STOP=1 >/dev/null
if [ -n "$FILES" ]; then
  say "Restoring the uploaded files"
  VOLUME="$($(docker_cmd) volume ls -q | grep -E '(^|_)privatefiles$' | head -1)"
  [ -n "$VOLUME" ] || fail "The files volume was not found."
  $(docker_cmd) run --rm -v "$VOLUME":/data -v "$(cd "$(dirname "$FILES")" && pwd)":/backup:ro alpine \
    sh -c "rm -rf /data/* && tar xzf /backup/$(basename "$FILES") -C /data && chown -R 10001 /data"
fi
say "Starting the API (migrations run first)"
compose up -d
say "Restored."
