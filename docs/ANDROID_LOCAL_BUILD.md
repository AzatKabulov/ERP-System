# Local Android test build

This is step 1 of the Android-first plan: build the existing Flutter application as a native
Android test APK, connect it to the existing HTTPS API, and smoke-test installation and launch.
Initial setup stayed local. The owner subsequently authorized source sharing, a website
update and another test APK; see HANDOFF.md for the actual delivery state. The shared Dart application and the existing Android host are reused.

## Build again on this Mac

From the repository root:

```bash
ERP_API_URL=https://your-test-server.example bash scripts/local/build_android_test.sh
```

The helper uses the pinned Flutter version from `.flutter-version`, resolves the existing
lockfile without upgrading dependencies, and builds a **debug** APK. Set the HTTPS API address
with `ERP_API_URL`; the helper refuses an absent or non-HTTPS address. The sign-in screen can
still change the server for this installation. Do not commit your deployment address.
It does not embed credentials or change server configuration.

Output (git-ignored):

- `local-data/android-builds/erp-android-local-debug.apk`
- `local-data/android-builds/erp-android-local-debug.apk.sha256`

Optional overrides:

```bash
ERP_API_URL=https://your-test-server.example \
ERP_FLUTTER_BIN=/absolute/path/to/flutter/bin/flutter \
bash scripts/local/build_android_test.sh
```

Flutter has been configured locally to use:

| Component | Local installation |
| --- | --- |
| Flutter 3.47.6 | `~/.tools/flutter-3.47.6` |
| Temurin JDK 21.0.13+9 (ARM64) | `~/.tools/jdk-21/Contents/Home` |
| Android SDK | `~/.tools/android-sdk` |
| SDK tools | `~/.tools/android-sdk/cmdline-tools/23.0/bin` |

SDK packages include platforms 34–36, build tools 36.0.0, platform tools, NDK 28.2.13676358,
CMake 3.22.1, and the API 36 Google APIs ARM64 emulator image. Project Gradle and plugin
versions remain unchanged. Tool archives were downloaded from their publishers and checked
against published checksums. SDKs, Gradle caches, generated host files, emulator data, and
signing keys are not source files to commit.

## Install on an Android phone or tablet

Transfer the APK to the Android device and open it. Android may ask to allow installation
from the selected browser or Files app. Open **ERP System**, then use the normal sign-in
screen. Test-role selection appears only if the configured server advertises that capability.

With USB debugging enabled and the device authorized on the Mac:

```bash
~/.tools/android-sdk/platform-tools/adb devices
~/.tools/android-sdk/platform-tools/adb -s DEVICE_SERIAL install -r \
  local-data/android-builds/erp-android-local-debug.apk
```

Choose the intended device serial explicitly. This APK uses the existing application ID
`app.erpsystem.mobile`, version from `mobile/pubspec.yaml`, and this Mac's local debug signing key. If an existing
installation uses a different signing key, Android will reject an in-place update. Do not
uninstall an existing app without checking any device-local data first.

## Verification and limits

Verified on 2026-11-09 (client date):

- The helper completed successfully; a second, cached build took 3.5 seconds in Gradle.
- `apksigner verify --print-certs` passed with this Mac's Android Debug certificate;
  the copied APK also passed its SHA-256 check.
- The APK is 189,976,821 bytes (about 181 MiB), supports `arm64-v8a`, `armeabi-v7a`, and
  `x86_64`, and declares minimum API 24 and target API 36.
- Installation and native launch passed on Android API 36 ARM64. The sign-in screen showed
  the HTTPS server; test-role sign-in opened the owner dashboard.
- At tablet geometry (2560×1600, 320 dpi), the catalog loaded the server's product, image,
  stock quantity, and scanning control. Russian and Turkmen interfaces switched successfully.
- At simulated phone geometry (1080×2400, 440 dpi), the catalog, bottom navigation, sales
  search, scanning control, and empty cart were accessible. This was the same AVD with a
  display override, not a separate physical phone.
- A cold app relaunch retained the signed-in session and Turkmen language. The original
  tablet display configuration was restored afterward.
- No native crashes or Flutter errors appeared in the observed app logs. Android emitted an
  `ashmem` deprecation notice. No stock changes or financial transactions were submitted;
  test sign-in records its ordinary server login/audit activity.

Local screenshots, accessibility trees, and the structured verification record are under
`local-data/android-builds/qa/` (`smoke-results.json`). These artifacts are git-ignored.
The shared Dart code and dependencies were unchanged, so this step verified the native build
and runtime rather than rerunning the previously passed web/widget suite.

The dedicated local AVD is `ERP_Local_Tablet_API36`; its data is under
`local-data/android-avd/tablet`. No physical Android device was connected during setup.
Emulator camera inputs are disabled. Real barcode scanning, camera permission behavior,
photos, printing, sharing, and performance on actual shop hardware require the next device
testing step. Debug timing and software-rendered emulator timing are not release performance
measurements.

This is an internal development build, not a production release. Permanent application ID,
owner-controlled release signing, release-mode hardware testing, and distribution are later
steps; see [ANDROID_RELEASE.md](ANDROID_RELEASE.md). iOS is not built in this step.


## Sharing with the team

Keep Android, web and backend source in the existing ERP-System repository.
Do not commit APK/AAB files or signing keys; the root ignore rules exclude them.
A source push does not update the deployed website: the server must be backed
up, the backend deployed and the matching web build uploaded separately.

CI now runs for `codex/**` as well as main and existing Claude branches. Its
`erp-system-test-build` artifact contains the debug APK and web archive (14-day
retention). These CI debug APKs use the runner's temporary signing key and are
not a replacement for the locally signed testing line already installed on
phones. The sign-in screen can configure the server if it was not built in.

For a consistent long-lived tester download, use the existing **Release APK**
workflow with the owner's repository signing secrets; it produces signed release
artifacts and, for version tags, attaches them to a draft GitHub Release. Keep the
same signing key for updates. No extra repository is required. Configure secrets
privately as described in ANDROID_RELEASE.md; never paste signing material in chat.
The APK produced locally for the current user retains this Mac's existing debug
key, so it can update that same testing installation. It is not a store release.
