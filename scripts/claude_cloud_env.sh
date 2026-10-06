#!/usr/bin/env bash
# Source this file before Flutter commands in a Claude Code cloud session.
# Counterpart of cloud_env.sh, which is written for the Codex cloud (/workspace paths).
# The VM already provides a Java 21 JDK, the egress proxy settings, and Chromium.
export ERP_FLUTTER_DIR="${ERP_FLUTTER_DIR:-$HOME/.tools/flutter}"
export FLUTTER_SUPPRESS_ANALYTICS=true
export CHROME_EXECUTABLE="${CHROME_EXECUTABLE:-/opt/pw-browsers/chromium}"
case ":$PATH:" in
  *":$ERP_FLUTTER_DIR/bin:"*) ;;
  *) export PATH="$ERP_FLUTTER_DIR/bin:$PATH" ;;
esac
