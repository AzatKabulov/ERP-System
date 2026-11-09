#!/usr/bin/env bash
# Backs up the database and the uploaded files (receipt photos) into infra/backups/, keeps the
# last 14 days. A backup that stays on the same machine does not survive losing the machine:
# copy infra/backups to protected off-machine storage. The API is briefly stopped
# so a replaced photo cannot disappear between database and files snapshots.
set -euo pipefail
umask 077
# shellcheck source=common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

STAMP="$(date +%Y%m%d-%H%M%S)-$$"
DEST="$INFRA/backups"
mkdir -p "$DEST"
chmod 700 "$DEST"
DB_USER="$(env_value POSTGRES_USER)"; DB_NAME="$(env_value POSTGRES_DB)"
VOLUME="$(private_files_volume)" || fail "This project's private files volume was not found. No complete backup was made."
LOCK="$DEST/.backup-in-progress"
mkdir "$LOCK" || fail "Another backup holds $LOCK. Check that job before removing a stale lock."
DB_TEMP=""; FILES_TEMP=""; API_RUNNING=""

cleanup() {
  local code=$?
  trap - EXIT
  rm -f -- "$DB_TEMP" "$FILES_TEMP" || code=1
  if [ -n "$API_RUNNING" ]; then
    compose start api || code=1
  fi
  rmdir "$LOCK" || code=1
  exit "$code"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
DB_TEMP="$(mktemp "$DEST/.db-$STAMP.XXXXXX")"
FILES_TEMP="$(mktemp "$DEST/.files-$STAMP.XXXXXX")"
API_RUNNING="$(compose ps --status running -q api)"

if [ -n "$API_RUNNING" ]; then
  say "Pausing the API for a consistent database and private-files backup"
  compose stop api
fi

compose exec -T db pg_dump -U "${DB_USER:-erp}" -d "${DB_NAME:-erp}" --no-owner --clean --if-exists | gzip > "$DB_TEMP"
$(docker_cmd) run --rm -v "$VOLUME":/data:ro -v "$DEST":/backup alpine tar czf "/backup/${FILES_TEMP##*/}" -C /data .
gzip -t "$DB_TEMP"
tar -tzf "$FILES_TEMP" >/dev/null
mv "$DB_TEMP" "$DEST/db-$STAMP.sql.gz"
mv "$FILES_TEMP" "$DEST/files-$STAMP.tar.gz"
find "$DEST" -maxdepth 1 \( -name 'db-*.sql.gz' -o -name 'files-*.tar.gz' \) -mtime +14 -delete
echo "$(date -Is) backup $STAMP: $(du -h "$DEST/db-$STAMP.sql.gz" | cut -f1) database, $(ls "$DEST"/files-"$STAMP".tar.gz >/dev/null 2>&1 && du -h "$DEST/files-$STAMP.tar.gz" | cut -f1 || echo 'no') files"
