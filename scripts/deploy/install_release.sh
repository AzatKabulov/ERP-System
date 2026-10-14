#!/usr/bin/env bash
# Puts a release on the test server: the web build (unzipped into infra/public/) and the Android
# app (infra/public/downloads/erp.apk). Both come from the "Release APK" workflow's files:
#
#     bash scripts/deploy/install_release.sh erp-system-0.1.0-build12-web.zip erp-system-0.1.0-build12.apk
#
# Either argument may be left out (use "-") to update only the other one.
set -euo pipefail
# shellcheck source=common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

WEB="${1:--}"; APK="${2:--}"
[ "$WEB" != "-" ] || [ "$APK" != "-" ] || fail "Usage: install_release.sh <web.zip|-> <app.apk|->"
mkdir -p "$INFRA/public/downloads"

if [ "$WEB" != "-" ]; then
  [ -f "$WEB" ] || fail "File not found: $WEB"
  command -v unzip >/dev/null 2>&1 || fail "unzip is missing: sudo apt-get install -y unzip"
  # replace the web app but keep the downloads folder
  find "$INFRA/public" -mindepth 1 -maxdepth 1 ! -name downloads ! -name .gitkeep -exec rm -rf {} +
  unzip -q "$WEB" -d "$INFRA/public"
  say "Web app installed."
fi
if [ "$APK" != "-" ]; then
  [ -f "$APK" ] || fail "File not found: $APK"
  cp "$APK" "$INFRA/public/downloads/erp.apk"
  say "Android app installed: $(du -h "$INFRA/public/downloads/erp.apk" | cut -f1)"
fi
SITE="$(env_value SITE_ADDRESS)"
case "$SITE" in
  :*) PAGE="http://localhost:$(env_value HTTP_PORT)/install/" ;;
  *) PAGE="https://$SITE/install/" ;;
esac
note "Nothing needs restarting. Install page: $PAGE"
