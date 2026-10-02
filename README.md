# ERP System

Flutter interface prototype for an inventory ERP sold in Turkmenistan, with Russian and Turkmen interfaces. Android tablets are the first target; iPad and iPhone follow later.

## What is included

- Dashboard, products, inventory, purchasing, sales and returns, expenses, warranties, reports, and administration screens.
- Three demonstration locations and a searchable car-part catalog.
- Interactive in-memory cart, checkout, linked returns, receiving, transfers, counts, and expenses.
- Persistent language selection, ARB translations, and custom Turkmen delegates for the controls used here.
- Bundled Inter and Noto Serif fonts, their licenses, and Android and web platform scaffolds.

The visible demonstration banner is intentional. Operations change sample data in memory and reset when the application restarts. Transfers complete immediately in the demo; the production transfer workflow will separately track dispatch, transit, and receipt. Warranty cards are examples. Camera scanning, printing, authentication, role enforcement, imports/exports, backups, and real payments are not connected. TMT is an illustrative currency, not a confirmed production configuration. Turkmen terminology needs fluent-speaker review.

## Interface preview

![Russian dashboard](docs/images/dashboard-ru.png)

[View the Turkmen dashboard](docs/images/dashboard-tk.png).

## Toolchain

Flutter **3.47.6**, pinned in `.flutter-version`, from official commit `5fc346839b5d0eef006ed8404392afb4dfae428d`. Android uses the corresponding Flutter templates, Android API 36, and the Gradle wrapper's pinned distribution checksum. The cloud setup installs a complete Temurin Java 21 JDK.

## Run on your development machine

Install the pinned Flutter SDK and the Android SDK appropriate to your workstation, then select an attached Android device or emulator:

```bash
cd mobile
flutter pub get
flutter gen-l10n
flutter devices
flutter run -d <android-device-id>
```

To try the same Flutter interface in an installed Chrome browser:

```bash
cd mobile
flutter run -d chrome
```

The debug Android APK and web build have been verified. Installation on physical Android hardware remains to be tested. iOS platform generation and validation are deferred to the Apple stage and require macOS/Xcode or a suitable build service.

## Cloud setup and validation

From `/workspace/ERP-System`:

```bash
bash scripts/setup_cloud.sh
source scripts/cloud_env.sh
cd mobile
dart format lib test
flutter analyze
flutter test
flutter build web --no-web-resources-cdn
flutter build apk --debug
```

The setup helper reuses the pinned SDK, installs missing Android prerequisites, and uses frozen dependency resolution with the retained application lockfile. The pinned Android command-line tools handle licensing without a separate prompt. It does not scaffold over application code. Keep `mobile/pubspec.lock` with the application.

Cloud Java clients use the environment's existing proxy and its provided public CA while retaining TLS verification. Because Maven Central rate-limits the shared cloud egress address, the helper configures Google's public Maven Central mirror inside the cloud Gradle cache. Workstation and project repository settings are unaffected. The web build bundles rendering resources locally.

For an internal cloud smoke run after the web build:

```bash
cd /workspace/ERP-System/mobile/build/web
python -m http.server 8080 --bind 127.0.0.1
```

Use internal browser requests for validation. The onboarding UI does not provide a localhost application preview.

### Current validation status

Verified in the cloud environment:

- Repeatable setup, frozen dependency resolution, and localization generation.
- Clean Dart formatting and Flutter analysis; all **12 unit/widget tests passed**.
- Web build and debug Android APK build; APK signature verification passed.
- Chromium interaction checks: dashboard, product search, cart preservation during language switching, checkout stock reduction, linked return/restocking, and language persistence after reload. No browser errors were observed.
- Phone and tablet rendering; widget layout checks at widths 360, 800, and 1400 with doubled text size.
- Russian/Turkmen font glyph coverage, matching translation keys, and official Gradle wrapper checksums.

Build artifacts are `mobile/build/web/` and `mobile/build/app/outputs/flutter-apk/app-debug.apk`. These are ignored outputs and can be recreated with the commands above. The Android APK uses development signing; it is not a store release. No physical-device, iOS, camera scanner, printer, or production backend checks have been performed.

Reusable installation and startup instructions are saved in the cloud environment configuration draft. Saving the draft does not publish it or prove readiness in a future restored session; services must restart and readiness checks must run there.

## Project documents

- [Product requirements](docs/PRD.md)
- [Agent instructions](AGENTS.md)
- [Design system](docs/DESIGN_SYSTEM.md)
- [Architecture and prototype boundaries](docs/ARCHITECTURE.md)
