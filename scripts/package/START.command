#!/bin/bash
# Mac: double-click this file (first time: right-click > Open).
cd "$(dirname "$0")" || exit 1
case "$(uname -m)" in
  arm64) UV=tools/mac-arm/uv ;;
  *) UV=tools/mac-intel/uv ;;
esac
chmod +x "$UV" 2>/dev/null
"$UV" run --project backend --with pixeltable-pgserver==0.6.0 python scripts/local/run_local.py --web app/erp-system-test-web.zip --apk app/erp-system-test-debug.apk "$@"
read -r -p "Press Enter to close this window..." _
