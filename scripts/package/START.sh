#!/usr/bin/env bash
# Starts the whole system (Linux, or any computer that already has uv).
cd "$(dirname "$0")" || exit 1
UV=uv
[ -x tools/linux/uv ] && UV=tools/linux/uv
"$UV" run --project backend --with pixeltable-pgserver==0.6.0 python scripts/local/run_local.py --web app/erp-system-test-web.zip --apk app/erp-system-test-debug.apk "$@"
