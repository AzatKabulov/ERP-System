#!/usr/bin/env bash
# One-time setup of a TEST server on a fresh Ubuntu 22.04 / 24.04 machine (a free Oracle Cloud VM,
# a cheap VPS, or any computer that stays on). Run it from a checkout of this repository as a
# normal user that may use sudo:
#
#     bash scripts/deploy/bootstrap_vm.sh
#
# It installs Docker, writes infra/.env with fresh random secrets, opens ports 80 and 443, starts
# the stack, creates the first business with its owner and sets up a nightly backup. Safe to run
# again: an existing infra/.env and an existing business are left alone.
#
# Answers can be given in advance instead of being asked:
#   DOMAIN=shop.example.com  BUSINESS_NAME="Test shop"  OWNER_USERNAME=owner  OWNER_EMAIL=me@example.com
# A computer with no domain and no open ports can use a free temporary address instead:
#   MODE=tunnel bash scripts/deploy/bootstrap_vm.sh
# Or run everything on your own computer, for you and anyone on the same Wi-Fi (plain http on
# port 8080; needs Docker already installed, e.g. Docker Desktop; nothing is opened or scheduled):
#   MODE=local bash scripts/deploy/bootstrap_vm.sh
set -euo pipefail
# shellcheck source=common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

MODE="${MODE:-domain}"
[ "$(id -u)" -ne 0 ] || fail "Run this as a normal user (it uses sudo where needed), not as root."

say "1/7  Docker"
if ! command -v docker >/dev/null 2>&1; then
  [ "$MODE" != "local" ] || fail "Docker is not installed. Install Docker Desktop (docker.com), start it, and run this again."
  note "Installing Docker (the official script from get.docker.com)..."
  curl -fsSL https://get.docker.com | sudo sh
  sudo usermod -aG docker "$USER" || true
fi
$(docker_cmd) compose version >/dev/null 2>&1 || fail "Docker Compose is missing. Install the docker compose plugin and run this again."
note "Docker is ready."

say "2/7  Questions"
if [ "$MODE" = "tunnel" ]; then
  DOMAIN=""
  note "Tunnel mode: a temporary https address will be created for you (no domain needed)."
elif [ "$MODE" = "local" ]; then
  DOMAIN=""
  note "Local mode: the server runs on this computer only (plain http on port 8080, reachable from the same Wi-Fi)."
else
  if [ -z "${DOMAIN:-}" ]; then
    read -r -p "   Domain name that points at this server (e.g. myshop.duckdns.org; empty = plain http by IP): " DOMAIN
  fi
fi
if [ "$MODE" = "domain" ] && [ -z "$DOMAIN" ] && [ "${ALLOW_PLAIN_HTTP:-}" != "yes" ]; then
  printf '\n   Without a domain name the server speaks plain http: passwords and sales travel unencrypted.\n'
  printf '   Fine on a private network; not for anything real. Better: get a free name at duckdns.org, or use MODE=tunnel.\n'
  read -r -p "   Type 'yes' to go on with plain http anyway: " answer
  [ "$answer" = "yes" ] || fail "Stopped. Run again with a domain name (DOMAIN=...) or MODE=tunnel."
fi
BUSINESS_NAME="${BUSINESS_NAME:-}"
if [ -z "$BUSINESS_NAME" ]; then read -r -p "   Name of the first business (e.g. Test shop): " BUSINESS_NAME; fi
OWNER_USERNAME="${OWNER_USERNAME:-}"
if [ -z "$OWNER_USERNAME" ]; then read -r -p "   Owner's login (e.g. owner): " OWNER_USERNAME; fi
OWNER_EMAIL="${OWNER_EMAIL:-}"
if [ -z "$OWNER_EMAIL" ]; then read -r -p "   Owner's email: " OWNER_EMAIL; fi
LOCATION_NAME="${LOCATION_NAME:-Main store}"

say "3/7  Firewall (ports 80 and 443)"
if [ "$MODE" = "local" ]; then
  note "Local mode: nothing is opened. If a firewall asks about Docker or port 8080, allow it for private networks only."
elif command -v ufw >/dev/null 2>&1 && sudo ufw status | grep -q "Status: active"; then
  sudo ufw allow 80/tcp >/dev/null && sudo ufw allow 443/tcp >/dev/null && sudo ufw allow 443/udp >/dev/null
  note "ufw: ports opened."
elif command -v iptables >/dev/null 2>&1 && sudo iptables -S INPUT 2>/dev/null | grep -q "REJECT"; then
  # Oracle Cloud's Ubuntu images ship with rules that reject everything but ssh.
  for port in 80 443; do
    sudo iptables -C INPUT -p tcp --dport "$port" -j ACCEPT 2>/dev/null || sudo iptables -I INPUT 1 -p tcp --dport "$port" -j ACCEPT
  done
  if command -v netfilter-persistent >/dev/null 2>&1; then sudo netfilter-persistent save >/dev/null 2>&1 || true; fi
  note "iptables: ports opened. If this is an Oracle Cloud VM also open 80 and 443 in the network security list (docs/DEPLOY_TESTING.md)."
else
  note "No host firewall to change. If the provider has its own firewall, open 80 and 443 there."
fi

say "4/7  Settings (infra/.env)"
if [ -f "$INFRA/.env" ]; then
  note "infra/.env exists: kept as it is."
else
  rand() { openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | head -c "$1"; }
  if [ "$MODE" = "tunnel" ]; then
    SITE=":80"; HOSTS=".trycloudflare.com,localhost"; HTTP_PORT=8080; HTTPS_PORT=8443
    COMPOSE_LINE="COMPOSE_FILE=docker-compose.yml:docker-compose.tunnel.yml"
  elif [ "$MODE" = "local" ]; then
    SITE=":80"; HOSTS="*"; HTTP_PORT=8080; HTTPS_PORT=8443; COMPOSE_LINE=""
  elif [ -n "$DOMAIN" ]; then
    SITE="$DOMAIN"; HOSTS="$DOMAIN"; HTTP_PORT=80; HTTPS_PORT=443; COMPOSE_LINE=""
  else
    SITE=":80"; HOSTS="*"; HTTP_PORT=80; HTTPS_PORT=443; COMPOSE_LINE=""
  fi
  umask 077
  sed -e "s|^DJANGO_SECRET_KEY=.*|DJANGO_SECRET_KEY=$(rand 64)|" \
      -e "s|^POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=$(rand 32)|" \
      -e "s|^DJANGO_ALLOWED_HOSTS=.*|DJANGO_ALLOWED_HOSTS=$HOSTS|" \
      -e "s|^SITE_ADDRESS=.*|SITE_ADDRESS=$SITE|" \
      -e "s|^HTTP_PORT=.*|HTTP_PORT=$HTTP_PORT|" \
      -e "s|^HTTPS_PORT=.*|HTTPS_PORT=$HTTPS_PORT|" \
      "$INFRA/.env.example" > "$INFRA/.env"
  [ -z "$COMPOSE_LINE" ] || echo "$COMPOSE_LINE" >> "$INFRA/.env"
  note "infra/.env written with new random secrets (it stays on this machine, never in git)."
fi
mkdir -p "$INFRA/public/downloads" "$INFRA/backups"

say "5/7  Starting the stack (the first build takes a few minutes)"
compose up -d --build
SITE_ADDRESS="$(env_value SITE_ADDRESS)"
case "$SITE_ADDRESS" in
  :*) CHECK_URL="http://localhost:$(env_value HTTP_PORT)/api/v1/health/" ;;
  *)  CHECK_URL="https://$SITE_ADDRESS/api/v1/health/" ;;
esac
note "Waiting for $CHECK_URL (a new certificate can take a minute)..."
if ! wait_healthy "$CHECK_URL"; then
  compose ps
  fail "The server did not become healthy. Look at: cd infra && docker compose logs --tail 50"
fi
note "The server answers."

say "6/7  First business and owner"
COUNT="$(compose run --rm -T api python manage.py shell -c "from apps.businesses.models import Business; print(Business.objects.count())" 2>/dev/null | tail -1 | tr -dc '0-9')"
OWNER_PASSWORD=""
if [ "${COUNT:-0}" != "0" ]; then
  note "A business already exists: nothing created."
else
  OWNER_PASSWORD="$(openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | head -c 16)Aa7"
  # the password goes through the environment, not the command line (which others on the machine could see)
  ERP_OWNER_PASSWORD="$OWNER_PASSWORD" compose run --rm -T -e ERP_OWNER_PASSWORD api python manage.py create_business \
    --name "$BUSINESS_NAME" --owner-username "$OWNER_USERNAME" --owner-email "$OWNER_EMAIL" \
    --location "$LOCATION_NAME" --language ru
fi

say "7/7  Nightly backup"
CRON_LINE="30 3 * * * $ROOT/scripts/deploy/backup.sh >> $INFRA/backups/backup.log 2>&1"
if [ "$MODE" = "local" ]; then
  note "Local mode: no scheduled backup. Run  bash scripts/deploy/backup.sh  when you want one."
elif crontab -l 2>/dev/null | grep -qF "scripts/deploy/backup.sh"; then
  note "A backup job is already in your crontab."
else
  (crontab -l 2>/dev/null || true; echo "$CRON_LINE") | crontab -
  note "Backups run every night at 03:30 into infra/backups (kept 14 days). Copy them off this machine now and then."
fi

case "$SITE_ADDRESS" in
  :*)
    ADDRESS=""
    if [ "$MODE" = "tunnel" ]; then
      note "Waiting for the temporary address from Cloudflare..."
      for _ in $(seq 1 30); do
        ADDRESS="$(compose logs cloudflared 2>/dev/null | grep -o 'https://[a-z0-9-]*\.trycloudflare\.com' | tail -1 || true)"
        [ -z "$ADDRESS" ] || break
        sleep 2
      done
    fi
    if [ "$MODE" = "local" ]; then
      LAN_IP="$(hostname -I 2>/dev/null | awk '{print $1}' || true)"
      [ -n "$LAN_IP" ] || LAN_IP="$(ipconfig getifaddr en0 2>/dev/null || true)"
      ADDRESS="http://localhost:$(env_value HTTP_PORT)"
      [ -z "$LAN_IP" ] || note "From a tablet or phone on the same Wi-Fi:  http://$LAN_IP:$(env_value HTTP_PORT)   (the debug app only; see docs/DEPLOY_TESTING.md)"
    fi
    [ -n "$ADDRESS" ] || ADDRESS="http://<this machine's address>:$(env_value HTTP_PORT)"
    ;;
  *) ADDRESS="https://$SITE_ADDRESS" ;;
esac
say "Done"
note "Server address:  $ADDRESS"
if [ "$MODE" = "tunnel" ]; then
  note "(This temporary address changes when the tunnel restarts: read it again with  cd infra && docker compose logs cloudflared | grep trycloudflare )"
fi
note "Install page:    $ADDRESS/install/   (give this link to testers)"
note "Web app:         $ADDRESS/"
if [ -n "$OWNER_PASSWORD" ]; then
  echo
  note "Owner login:     $OWNER_USERNAME"
  note "Owner password: $OWNER_PASSWORD     <- shown ONCE: write it down, then change it in the app (Settings)"
fi
echo
note "Next: put the Android app and the web build on the server (scripts/deploy/install_release.sh) - see docs/DEPLOY_TESTING.md."
