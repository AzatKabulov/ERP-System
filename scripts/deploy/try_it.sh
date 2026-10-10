#!/usr/bin/env bash
# The shortest way to try the system on your own computer. Needs Docker running and the test
# build downloaded from GitHub (Actions > the latest green run > Artifacts > erp-system-test-build,
# saved in your Downloads folder). One command, no questions:
#
#     bash scripts/deploy/try_it.sh
#
# It starts the whole system (plain http on port 8080, nothing opened to the internet), finds the
# downloaded app files, puts them on the server, and prints the addresses for the computer and for
# a tablet on the same Wi-Fi. Safe to run again (for example after downloading the files).
set -euo pipefail
# shellcheck source=common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

LOG="$(mktemp)"
WORK="$(mktemp -d)"
trap 'rm -rf "$LOG" "$WORK"' EXIT

say "1/3  Starting the system on this computer (the first time takes 5 to 10 minutes)"
MODE=local \
  BUSINESS_NAME="${BUSINESS_NAME:-Test shop}" \
  OWNER_USERNAME="${OWNER_USERNAME:-owner}" \
  OWNER_EMAIL="${OWNER_EMAIL:-owner@example.test}" \
  bash "$ROOT/scripts/deploy/bootstrap_vm.sh" 2>&1 | tee "$LOG"

# The newest file that matches a name pattern in the usual download places.
newest() {
  local pattern="$1" dir f
  local -a dirs=("$HOME/Downloads" "$HOME/downloads" "$PWD" "$ROOT") found=()
  for dir in /mnt/c/Users/*/Downloads; do [ -d "$dir" ] && dirs+=("$dir"); done
  for dir in "${dirs[@]}"; do
    [ -d "$dir" ] || continue
    while IFS= read -r f; do found+=("$f"); done < <(find "$dir" -maxdepth 1 -type f -name "$pattern" 2>/dev/null)
  done
  [ "${#found[@]}" -gt 0 ] || return 0
  local best=""
  for f in "${found[@]}"; do
    if [ -z "$best" ] || [ "$f" -nt "$best" ]; then best="$f"; fi
  done
  printf '%s\n' "$best"
}

say "2/3  The app files"
WEB="$(newest 'erp-system-test-web*.zip')"
APK="$(newest 'erp-system-test-debug*.apk')"
if [ -z "$WEB" ] || [ -z "$APK" ]; then
  BUNDLE="$(newest 'erp-system-test-build*.zip')"
  if [ -n "$BUNDLE" ]; then
    command -v unzip >/dev/null 2>&1 || fail "unzip is missing. On Ubuntu or Windows (WSL) run:  sudo apt-get install -y unzip   and then this command again."
    note "Found $BUNDLE"
    unzip -q -o "$BUNDLE" -d "$WORK"
    WEB="$(find "$WORK" -type f -name 'erp-system-test-web*.zip' | head -1)"
    APK="$(find "$WORK" -type f -name 'erp-system-test-debug*.apk' | head -1)"
  fi
fi
if { [ -z "$WEB" ] || [ -z "$APK" ]; } && command -v gh >/dev/null 2>&1; then
  # The GitHub command line tool (always there inside a Codespace) can fetch the newest green
  # build of this branch itself, if it is signed in with the right to read it.
  BRANCH="$(git -C "$ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
  if [ -n "$BRANCH" ]; then
    RUN="$( (cd "$ROOT" && gh run list --branch "$BRANCH" --workflow CI --status success --limit 1 --json databaseId --jq '.[0].databaseId') 2>/dev/null || true)"
    if [ -n "$RUN" ] && (cd "$ROOT" && gh run download "$RUN" -n erp-system-test-build -D "$WORK" >/dev/null 2>&1); then
      note "Downloaded the newest green test build of $BRANCH from GitHub."
      WEB="$(find "$WORK" -type f -name 'erp-system-test-web*.zip' | head -1)"
      APK="$(find "$WORK" -type f -name 'erp-system-test-debug*.apk' | head -1)"
    fi
  fi
fi
if [ -n "$WEB" ] && [ -n "$APK" ]; then
  bash "$ROOT/scripts/deploy/install_release.sh" "$WEB" "$APK"
else
  note "The app files were not found in your Downloads folder."
  note "Download  erp-system-test-build  from GitHub (Actions > the latest green run > Artifacts),"
  note "leave the zip in Downloads (in a Codespace: drag it into the file list on the left), and run"
  note "this command again. The system itself is already running."
fi

# The address of this computer on the Wi-Fi, as best it can be told.
lan_ip() {
  local ip=""
  if grep -qi microsoft /proc/version 2>/dev/null && command -v ipconfig.exe >/dev/null 2>&1; then
    # inside WSL the Windows address is the one a tablet can reach
    ip="$(ipconfig.exe 2>/dev/null | tr -d '\r' | awk -F': ' '/IPv4/ {print $2}' | grep -E '^(192\.168\.|10\.)' | head -1 || true)"
  elif command -v ipconfig >/dev/null 2>&1; then
    ip="$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || true)"
  else
    ip="$(hostname -I 2>/dev/null | awk '{print $1}' || true)"
  fi
  printf '%s' "$ip"
}

say "3/3  Ready"
PORT="$(env_value HTTP_PORT)"
IP="$(lan_ip)"
if [ -n "${CODESPACE_NAME:-}" ]; then
  # inside a GitHub Codespace the computer is a cloud machine: the address comes from GitHub
  PUBLIC="https://${CODESPACE_NAME}-${PORT}.${GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN:-app.github.dev}"
  if gh codespace ports visibility "${PORT}:public" -c "$CODESPACE_NAME" >/dev/null 2>&1; then
    note "Port $PORT is now public (anyone who has the address can reach the sign-in page: stop the Codespace when you are done)."
  else
    note "Open the PORTS tab at the bottom, right-click port $PORT > Port Visibility > Public."
  fi
  note "Open this in a browser, on the computer or on the tablet:  $PUBLIC/"
  note "On the tablet install the app from  $PUBLIC/install/  and in the app: Server > Change > $PUBLIC"
elif [ -n "$IP" ]; then
  note "On this computer:  http://localhost:$PORT/"
  note "On a tablet or phone on the same Wi-Fi:  http://$IP:$PORT/install/   (install the app, then in the app: Server > Change > http://$IP:$PORT)"
else
  note "On this computer:  http://localhost:$PORT/"
  note "For a tablet: find this computer's Wi-Fi address (Windows: ipconfig; Mac: System Settings > Wi-Fi > Details) and open http://<address>:$PORT/install/"
fi
PASSWORD_LINE="$(grep 'Owner password' "$LOG" | sed 's/^ *//' | head -1 || true)"
if [ -n "$PASSWORD_LINE" ]; then
  echo
  note "Login: owner"
  note "$PASSWORD_LINE"
fi
echo
[ -n "${CODESPACE_NAME:-}" ] || note "If Windows asks whether Docker may accept connections, allow it on private networks."
