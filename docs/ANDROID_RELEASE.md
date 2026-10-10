# Android app for direct install (and Google Play later)

Decision D12 (owner, 2026-10-09): **direct install first** (a file people download and install), Google Play later.

## Why a signing key, and why it matters

Android only lets an app update itself in place when the new file is signed with the **same key** as the installed one. So one key, made once, must be used for every build you ever give to anyone, and **it must never be lost**: if it is, every tester has to uninstall and reinstall (and Google Play can no longer be connected to the already installed copies).

The key stays outside the repository and outside this cloud session: **you** create it, on your own computer.

## One-time setup (about 10 minutes)

1. Install Java if you do not have it (any JDK 17+), then create the key:

   ```bash
   keytool -genkeypair -v -storetype JKS -keystore erp-release.jks \
     -alias erp -keyalg RSA -keysize 2048 -validity 10000
   ```

   It asks for a password (twice) and some details about you or your company. Remember the password and the alias (`erp`).
2. **Back it up now**: the file `erp-release.jks` and its two passwords go into a password manager and onto a second place (an offline drive). Never into git, never into a chat.
3. Turn the file into text for GitHub: `base64 -w0 erp-release.jks` (on a Mac: `base64 -i erp-release.jks`).
4. In GitHub open the repository > Settings > Secrets and variables > Actions > New repository secret, and add four:

   | Name | Value |
   | --- | --- |
   | `ANDROID_KEYSTORE_BASE64` | the text from step 3 |
   | `ANDROID_KEYSTORE_PASSWORD` | the keystore password |
   | `ANDROID_KEY_ALIAS` | `erp` |
   | `ANDROID_KEY_PASSWORD` | the key password (the same as the keystore password if you were not asked for two) |

## Making a release

**Before the first run: the workflow must be on `main`.** GitHub only shows the "Run workflow" button for workflows that exist on the repository's default branch (`main`), and `release-apk.yml` lives on the working branch until it is merged (PLAN step 0.1: pull request from `claude/laughing-faraday-3dkwcb` into `main`). Either merge first, or skip the button and push a tag from the branch instead (`git tag v0.1.0 <commit> && git push origin v0.1.0`): a tag runs the workflow from the tagged commit.

GitHub > Actions > **Release APK** > Run workflow (leave the server field empty unless you want an address built in as the default: the app can always be pointed at another server on its sign-in screen). It runs the tests, builds the signed app and the web app, checks the signature, and offers the files for download from the finished run (kept 90 days). Pushing a tag such as `v0.1.0` does the same and attaches the files to a draft release.

The version number the app shows comes from `mobile/pubspec.yaml` (`version: 0.1.0+1`); the build number is the run number, so every build is newer than the last one and Android accepts it as an update.

Put the files on your server with `scripts/deploy/install_release.sh` (`docs/DEPLOY_TESTING.md`).

## Installing on a tablet or phone

Testers open `https://your-server/install/` (Russian and Turkmen), download the file and install it. Android asks once to allow installing from that source (the browser or the Files app). Google Play Protect may say "unknown developer": that is normal for apps outside the store; "Install anyway". After that, the first thing to do is type the server address on the sign-in screen.

An update is the same: download the new file and open it; the data stays.

## Things to know before real clients

- **The application id** `app.erpsystem.mobile` (`mobile/android/app/build.gradle.kts`) is a placeholder I chose. It is the app's permanent identity: a different id is a different app, and Google Play will not let you change it later. **Decide the final one before the first real client installs** (a reverse domain name you control, for example `com.yourcompany.shop`), change that one line, and make a new release. Testers then reinstall once.
- **Release builds do not shrink the code yet** (`isMinifyEnabled = false`). Switch it on after the camera scanner, printing and file flows have been tried on a real device with a release build; it makes the file smaller.
- **Not verified**: nothing about the release build was run on a device (only compiled in GitHub). The first real tablet test is the check for scanning, photos, printing and sharing.
- The browser (web) build only ever talks to the server it was loaded from.

## Google Play later

Google Play wants an app bundle (`.aab`, built by the same workflow with `flutter build appbundle`), a developer account (a one-time fee), a privacy policy, store texts and screenshots. Use **Play App Signing** and, when you enrol the app, upload **this same key** as the app signing key (Play lets you do that at the first upload): then the copies already installed by direct download keep updating from the store. Keep using the id and the key above; that is why they matter now.
