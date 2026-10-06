#!/usr/bin/env bash
# Claude Code cloud: start the VM's PostgreSQL cluster and prepare a LOCAL-ONLY
# development database for backend/. Idempotent.
#
# Generates backend/.env (git-ignored) with a random database password and Django
# secret key on first run. Nothing generated here is committed or reused elsewhere.
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
env_file="$repo_root/backend/.env"
pg_version="${PG_CLUSTER_VERSION:-16}"
pg_cluster="${PG_CLUSTER_NAME:-main}"
db_user=erp
db_name=erp

if ! pg_isready -q -h 127.0.0.1 -p 5432; then
  pg_ctlcluster "$pg_version" "$pg_cluster" start
fi
for _ in $(seq 1 30); do
  pg_isready -q -h 127.0.0.1 -p 5432 && break
  sleep 1
done
pg_isready -h 127.0.0.1 -p 5432

mkdir -p "$repo_root/backend"
if [ ! -f "$env_file" ]; then
  (
    umask 077
    cat > "$env_file" <<ENV
DJANGO_ENV=development
DJANGO_DEBUG=true
DJANGO_SECRET_KEY=$(python3 -c 'import secrets; print(secrets.token_urlsafe(50))')
DJANGO_ALLOWED_HOSTS=127.0.0.1,localhost
POSTGRES_DB=$db_name
POSTGRES_USER=$db_user
POSTGRES_PASSWORD=$(python3 -c 'import secrets; print(secrets.token_urlsafe(24))')
POSTGRES_HOST=127.0.0.1
POSTGRES_PORT=5432
ENV
  )
fi
db_password="$(grep '^POSTGRES_PASSWORD=' "$env_file" | cut -d= -f2-)"

# The password goes through stdin, not the process arguments.
psql_admin() { runuser -u postgres -- psql -v ON_ERROR_STOP=1 -qAt "$@"; }
if [ -z "$(psql_admin -c "select 1 from pg_roles where rolname='$db_user'")" ]; then
  printf "create role %s login createdb password '%s';\n" "$db_user" "$db_password" | psql_admin
else
  printf "alter role %s login createdb password '%s';\n" "$db_user" "$db_password" | psql_admin
fi
if [ -z "$(psql_admin -c "select 1 from pg_database where datname='$db_name'")" ]; then
  psql_admin -c "create database $db_name owner $db_user encoding 'UTF8' template template0 lc_collate 'C.UTF-8' lc_ctype 'C.UTF-8'"
fi
echo "PostgreSQL ready: database '$db_name', role '$db_user'; settings in backend/.env"
