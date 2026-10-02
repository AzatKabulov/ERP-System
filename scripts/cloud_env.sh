#!/usr/bin/env bash
# Source this file before cloud development commands.
export PUB_CACHE="${PUB_CACHE:-/workspace/.cache/pub}"
export GRADLE_USER_HOME="${GRADLE_USER_HOME:-/workspace/.cache/gradle}"
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-/workspace/.cache/flutter-config}"
export ANDROID_HOME="${ANDROID_HOME:-/workspace/.tools/android-sdk}"
export ANDROID_USER_HOME="${ANDROID_USER_HOME:-/workspace/.cache/android-user}"
export FLUTTER_SUPPRESS_ANALYTICS=true
export CHROME_EXECUTABLE="${CHROME_EXECUTABLE:-/usr/bin/chromium}"
export PATH="/workspace/.tools/flutter/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/cmdline-tools/latest/bin:$PATH"
if [ -x /workspace/.tools/jdk-21/bin/javac ]; then
  export JAVA_HOME=/workspace/.tools/jdk-21
  export PATH="$JAVA_HOME/bin:$PATH"
fi

# Java does not read HTTPS_PROXY itself. Supply the existing proxy endpoint,
# preserving Java's default certificate verification and any caller options.
task_java_proxy_flags="$(python - <<'PY'
import os, re
from urllib.parse import urlparse
proxy = urlparse(os.environ.get('HTTPS_PROXY', ''))
if proxy.hostname and re.fullmatch(r'[A-Za-z0-9._:-]+', proxy.hostname):
    print(' '.join(f'-D{scheme}.proxyHost={proxy.hostname} -D{scheme}.proxyPort={proxy.port or 80}' for scheme in ['http', 'https']))
PY
)"
if [ -n "$task_java_proxy_flags" ]; then
  case " ${JAVA_OPTS:-} " in
    *" $task_java_proxy_flags "*) ;;
    *) export JAVA_OPTS="${JAVA_OPTS:+$JAVA_OPTS }$task_java_proxy_flags" ;;
  esac
fi
unset task_java_proxy_flags
