#!/usr/bin/env bash
# Backs up the database and the uploaded files (receipt photos) into infra/backups/, keeps the
# last 14 days. A backup that stays on the same machine does not survive losing the machine:
# copy infra/backups somewhere else now and then (scp, rsync, a cloud drive).
set -euo pipefail
# shellcheck source=common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

STAMP="$(date +%Y%m%d-%H%M)"
DEST="$INFRA/backups"
mkdir -p "$DEST"
DB_USER="$(env_value POSTGRES_USER)"; DB_NAME="$(env_value POSTGRES_DB)"

compose exec -T db pg_dump -U "${DB_USER:-erp}" -d "${DB_NAME:-erp}" --no-owner --clean --if-exists | gzip > "$DEST/db-$STAMP.sql.gz"
# the files volume is named after the compose project (the folder name: "infra")
VOLUME="$($(docker_cmd) volume ls -q | grep -E '(^|_)privatefiles$' | head -1 || true)"
if [ -n "$VOLUME" ]; then
  $(docker_cmd) run --rm -v "$VOLUME":/data:ro -v "$DEST":/backup alpine tar czf "/backup/files-$STAMP.tar.gz" -C /data .
fi
find "$DEST" -maxdepth 1 \( -name 'db-*.sql.gz' -o -name 'files-*.tar.gz' \) -mtime +14 -delete
echo "$(date -Is) backup $STAMP: $(du -h "$DEST/db-$STAMP.sql.gz" | cut -f1) database, $(ls "$DEST"/files-"$STAMP".tar.gz >/dev/null 2>&1 && du -h "$DEST/files-$STAMP.tar.gz" | cut -f1 || echo 'no') files"
