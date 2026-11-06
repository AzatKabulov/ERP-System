#!/usr/bin/env bash
# Backs up the database and the uploaded files (receipt photos) into infra/backups/, keeps the
# last 14 days. A backup that stays on the same machine does not survive losing the machine:
# copy infra/backups somewhere else now and then (scp, rsync, a cloud drive).
#
# A backup is only kept under its final name after it has been read back and checked, so a failed
# run can never leave a file that looks like a good backup. Old backups are deleted only after a
# fully successful run. The files are readable by the owner only (they hold every customer record).
set -euo pipefail
# shellcheck source=common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

umask 077
STAMP="$(date +%Y%m%d-%H%M)"
DEST="$INFRA/backups"
mkdir -p "$DEST"
DB_USER="$(env_value POSTGRES_USER)"; DB_NAME="$(env_value POSTGRES_DB)"
DB_FILE="$DEST/db-$STAMP.sql.gz"
FILES_FILE="$DEST/files-$STAMP.tar.gz"
trap 'rm -f "$DB_FILE.partial" "$FILES_FILE.partial"' EXIT

compose exec -T db pg_dump -U "${DB_USER:-erp}" -d "${DB_NAME:-erp}" --no-owner --clean --if-exists | gzip > "$DB_FILE.partial"
# pg_dump ends a complete dump with this line; a cut-off dump does not have it.
if ! gzip -dc "$DB_FILE.partial" | tail -n 5 | grep -q "PostgreSQL database dump complete"; then
  fail "The database dump is incomplete. Nothing was kept. Look at: cd infra && docker compose logs --tail 50 db"
fi
mv "$DB_FILE.partial" "$DB_FILE"

# the files volume is named after the compose project (the folder name: "infra")
VOLUME="$($(docker_cmd) volume ls -q | grep -E '(^|_)privatefiles$' | head -1 || true)"
[ -n "$VOLUME" ] || fail "The database was saved, but the uploaded-files volume was not found, so receipt photos and product pictures are NOT in this backup."
$(docker_cmd) run --rm -v "$VOLUME":/data:ro -v "$DEST":/backup alpine \
  sh -c "umask 077 && tar czf '/backup/files-$STAMP.tar.gz.partial' -C /data . && chown $(id -u):$(id -g) '/backup/files-$STAMP.tar.gz.partial'"
tar tzf "$FILES_FILE.partial" >/dev/null || fail "The files backup could not be read back. Nothing was kept for the files."
mv "$FILES_FILE.partial" "$FILES_FILE"

find "$DEST" -maxdepth 1 \( -name 'db-*.sql.gz' -o -name 'files-*.tar.gz' \) -mtime +14 -delete
echo "$(date -Is) backup $STAMP: $(du -h "$DB_FILE" | cut -f1) database, $(du -h "$FILES_FILE" | cut -f1) files"
