# Shared helpers for the deployment scripts (sourced, not run).
# shellcheck shell=bash

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
INFRA="$ROOT/infra"

say() { printf '\n\033[1m%s\033[0m\n' "$*"; }
note() { printf '   %s\n' "$*"; }
fail() { printf '\n\033[31mError: %s\033[0m\n' "$*" >&2; exit 1; }

# "docker" if the current user may use it, else "sudo docker".
docker_cmd() {
  if docker info >/dev/null 2>&1; then echo "docker"; else echo "sudo docker"; fi
}

# Runs docker compose inside infra/, so infra/.env (and its COMPOSE_FILE) is picked up.
compose() {
  # shellcheck disable=SC2046
  (cd "$INFRA" && $(docker_cmd) compose "$@")
}

# Waits until the API answers its health page through Caddy (about 2 minutes at most).
wait_healthy() {
  local url="$1" code="000"
  local deadline=$((SECONDS + 120))
  while [ "$SECONDS" -lt "$deadline" ]; do
    code="$(curl -s --connect-timeout 2 --max-time 5 -o /dev/null -w '%{http_code}' "$url" || true)"
    [ "$code" = "200" ] && return 0
    sleep 2
  done
  echo "The health page $url answered $code" >&2
  return 1
}

# Read this project's actual API mount, never the first similarly named volume
# on the Docker host (which might belong to a different shop).
private_files_volume() {
  local container volume
  container="$(compose ps --all -q api)"
  [ -n "$container" ] || return 1
  # shellcheck disable=SC2046
  volume="$($(docker_cmd) inspect --format '{{range .Mounts}}{{if and (eq .Type "volume") (eq .Destination "/var/lib/erp/private_files")}}{{println .Name}}{{end}}{{end}}' "$container")"
  [ -n "$volume" ] || return 1
  printf '%s\n' "$volume"
}

env_value() { # env_value NAME: the value of NAME in infra/.env
  grep -E "^$1=" "$INFRA/.env" | head -1 | cut -d= -f2-
}
