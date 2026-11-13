#!/usr/bin/env bash
# Local Android test APK; no commit, push, publication or deployment.
set -euo pipefail

task_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
task_version="$(tr -d '\r\n' < "$task_root/.flutter-version")"
task_flutter="${ERP_FLUTTER_BIN:-$HOME/.tools/flutter-$task_version/bin/flutter}"
task_server="${ERP_API_URL:-}"
if [[ "$task_server" != https://* ]]; then
  printf 'Set ERP_API_URL to the HTTPS server address for this test build.\n' >&2
  exit 1
fi
task_output="$task_root/local-data/android-builds"

if [ ! -x "$task_flutter" ]; then
  printf 'Set ERP_FLUTTER_BIN to the pinned Flutter %s executable.\n' "$task_version" >&2
  exit 1
fi

mkdir -p "$task_output"
cd "$task_root/mobile"
"$task_flutter" pub get --enforce-lockfile
"$task_flutter" build apk --debug --no-pub --dart-define="API_BASE_URL=$task_server"
cp build/app/outputs/flutter-apk/app-debug.apk "$task_output/erp-android-local-debug.apk"
shasum -a 256 "$task_output/erp-android-local-debug.apk" > "$task_output/erp-android-local-debug.apk.sha256"
printf '\nLocal test APK: %s/erp-android-local-debug.apk\n' "$task_output"
printf 'Default API: %s\nDebug build for testing; store release signing is a later step.\n' "$task_server"
