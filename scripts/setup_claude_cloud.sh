#!/usr/bin/env bash
# Prepares a Claude Code cloud VM for the web build and tests: installs the
# pinned Flutter SDK outside the repository, resolves dependencies from the
# committed lockfile, and generates localizations.
#
# Counterpart of setup_cloud.sh (Codex cloud). It deliberately omits the Android
# SDK: dl.google.com, which serves the Android command-line tools, is blocked by
# the default Claude Code cloud network policy. Allow that domain in the
# environment settings before adding Android setup here.
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/scripts/claude_cloud_env.sh"

flutter_version=3.47.6
flutter_commit=5fc346839b5d0eef006ed8404392afb4dfae428d

if [ "$(tr -d '\r\n' < "$repo_root/.flutter-version")" != "$flutter_version" ]; then
  printf '%s\n' 'Update this helper (and setup_cloud.sh) when changing the pinned Flutter version.' >&2
  exit 1
fi

if [ ! -d "$ERP_FLUTTER_DIR" ]; then
  mkdir -p "$(dirname "$ERP_FLUTTER_DIR")"
  git clone --depth 1 --branch "$flutter_version" https://github.com/flutter/flutter.git "$ERP_FLUTTER_DIR"
fi
if [ "$(git -C "$ERP_FLUTTER_DIR" rev-parse HEAD)" != "$flutter_commit" ]; then
  printf '%s\n' 'The installed Flutter SDK differs from the pinned commit. Resolve the SDK version before continuing.' >&2
  exit 1
fi

flutter --suppress-analytics --version
# Web artifacts come from storage.googleapis.com, which is reachable by default.
flutter precache --web
cd "$repo_root/mobile"
flutter pub get --enforce-lockfile
flutter gen-l10n
