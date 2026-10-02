#!/usr/bin/env bash
set -euo pipefail

task_repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$task_repo_root/scripts/cloud_env.sh"
bash "$task_repo_root/scripts/configure_gradle.sh"
mkdir -p /workspace/.tools /workspace/.cache "$ANDROID_USER_HOME"
# adb currently requires this directory even when ANDROID_USER_HOME is set.
mkdir -p "$HOME/.android" "$HOME/.dart-tool" "$HOME/.dartServer"

if [ ! -x /workspace/.tools/jdk-21/bin/javac ]; then
  task_jdk_archive=/workspace/.cache/temurin-jdk-21.tar.gz
  curl --fail --location --silent --show-error \
    'https://github.com/adoptium/temurin21-binaries/releases/download/jdk-21.0.12.1%2B1/OpenJDK21U-jdk_x64_linux_hotspot_21.0.12.1_1.tar.gz' \
    -o "$task_jdk_archive"
  printf '%s  %s\n' ce79869e1307ed8ee1e2baa86a412b1eb5b75d10a01006d788a6f968bcfaee94 "$task_jdk_archive" | sha256sum --check
  mkdir -p /workspace/.tools/jdk-21
  tar -xzf "$task_jdk_archive" --strip-components=1 -C /workspace/.tools/jdk-21
fi
source "$task_repo_root/scripts/cloud_env.sh"
# Add only the platform-provided public CA to the JDK's normal trust store.
# Certificate verification remains enabled for Gradle and other Java clients.
if [ -f "${CODEX_PROXY_CERT:-}" ]; then
  if "$JAVA_HOME/bin/keytool" -list -alias cloud-egress -keystore "$JAVA_HOME/lib/security/cacerts" -storepass changeit >/dev/null 2>&1; then
    "$JAVA_HOME/bin/keytool" -delete -alias cloud-egress -keystore "$JAVA_HOME/lib/security/cacerts" -storepass changeit
  fi
  "$JAVA_HOME/bin/keytool" -importcert -noprompt -alias cloud-egress -file "$CODEX_PROXY_CERT" -keystore "$JAVA_HOME/lib/security/cacerts" -storepass changeit
fi

task_flutter_commit=5fc346839b5d0eef006ed8404392afb4dfae428d
if [ ! -d /workspace/.tools/flutter ]; then
  git clone --depth 1 --branch 3.47.6 https://github.com/flutter/flutter.git /workspace/.tools/flutter
fi
if [ "$(git -C /workspace/.tools/flutter rev-parse HEAD)" != "$task_flutter_commit" ]; then
  printf '%s\n' 'The existing cloud Flutter SDK differs from the pinned commit. Resolve the SDK version before continuing.' >&2
  exit 1
fi
if [ "$(tr -d '\r\n' < "$task_repo_root/.flutter-version")" != '3.47.6' ]; then
  printf '%s\n' 'Update the setup helper when changing the pinned Flutter version.' >&2
  exit 1
fi

if [ ! -x "$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" ]; then
  task_android_archive=/workspace/.cache/android-commandline-23.zip
  curl --fail --location --silent --show-error \
    https://dl.google.com/android/repository/commandlinetools-linux-16111833_latest.zip \
    -o "$task_android_archive"
  printf '%s  %s\n' e025545c62a8e64c7559119566a569fb1dec5f60 "$task_android_archive" | sha1sum --check
  task_android_extract="$(mktemp -d /workspace/.cache/android-extract.XXXXXX)"
  unzip -q "$task_android_archive" -d "$task_android_extract"
  mkdir -p "$ANDROID_HOME/cmdline-tools"
  mv "$task_android_extract/cmdline-tools" "$ANDROID_HOME/cmdline-tools/latest"
  chmod +x "$ANDROID_HOME/cmdline-tools/latest/bin/"*
  rmdir "$task_android_extract"
fi

# The pinned command-line tools handle licensing without a separate prompt.
sdkmanager --sdk_root="$ANDROID_HOME" \
  'platform-tools' 'platforms;android-36' 'build-tools;36.0.0' 'ndk;28.2.13676358'

# Flutter uses its standard verified HTTPS artifact downloads here.
# storage.googleapis.com must be allowed by runtime networking.
flutter --suppress-analytics --version
flutter config --android-sdk "$ANDROID_HOME"
flutter config --jdk-dir "$JAVA_HOME"
flutter precache --android --web
cd "$task_repo_root/mobile"
if [ -f pubspec.lock ]; then
  flutter pub get --enforce-lockfile
else
  flutter pub get
fi
flutter gen-l10n
