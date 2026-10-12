#!/usr/bin/env bash
# Builds ERP-Test.zip: one download that holds everything needed to try the whole system on a
# Windows or Mac computer: the server code, the web app, the Android test app, and the small
# tool (uv) that starts it. Unzip, double-click START, done. Used by CI; needs git and zip.
#
#   bash scripts/package/make_test_package.sh <web.zip> <app.apk> <output.zip>
#
# NO_UV=1 skips the uv downloads (for checking the package layout offline).
set -euo pipefail

WEB="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
APK="$(cd "$(dirname "$2")" && pwd)/$(basename "$2")"
OUT_DIR="$(cd "$(dirname "$3")" && pwd)"
OUT="$OUT_DIR/$(basename "$3")"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
UV_VERSION="${UV_VERSION:-0.11.32}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
PKG="$WORK/ERP-Test"
mkdir -p "$PKG/app" "$PKG/tools/win" "$PKG/tools/mac-arm" "$PKG/tools/mac-intel"

# the server code and the launcher, exactly as committed
git -C "$ROOT" archive --format=tar HEAD backend scripts/local infra/site/install | tar -x -C "$PKG"
cp "$WEB" "$PKG/app/erp-system-test-web.zip"
cp "$APK" "$PKG/app/erp-system-test-debug.apk"
cp "$ROOT/scripts/package/START.bat" "$ROOT/scripts/package/START.command" "$ROOT/scripts/package/START.sh" "$ROOT/scripts/package/README.txt" "$PKG/"
chmod +x "$PKG/START.command" "$PKG/START.sh"

if [ "${NO_UV:-}" != "1" ]; then
  base="https://github.com/astral-sh/uv/releases/download/$UV_VERSION"
  fetch() { curl -fsSL --retry 3 -o "$WORK/$1" "$base/$1"; }
  fetch uv-x86_64-pc-windows-msvc.zip
  unzip -q -j "$WORK/uv-x86_64-pc-windows-msvc.zip" uv.exe -d "$PKG/tools/win"
  fetch uv-aarch64-apple-darwin.tar.gz
  tar -xzf "$WORK/uv-aarch64-apple-darwin.tar.gz" -C "$WORK" && cp "$WORK/uv-aarch64-apple-darwin/uv" "$PKG/tools/mac-arm/uv"
  fetch uv-x86_64-apple-darwin.tar.gz
  tar -xzf "$WORK/uv-x86_64-apple-darwin.tar.gz" -C "$WORK" && cp "$WORK/uv-x86_64-apple-darwin/uv" "$PKG/tools/mac-intel/uv"
  chmod +x "$PKG/tools/mac-arm/uv" "$PKG/tools/mac-intel/uv"
fi

rm -f "$OUT"
(cd "$WORK" && zip -qr "$OUT" ERP-Test)
echo "Built $OUT ($(du -h "$OUT" | cut -f1))"
