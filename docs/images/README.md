# Interface previews

These screenshots show the Flutter demonstration build with synthetic sample data and its visible demo banner. They illustrate the shared visual language and Russian/Turkmen localization, not connected API behavior or a real business's figures.

Refreshed on 2026-10-16 from source commit `dedd55feccad08bf4c69510abb40bcd18f44f574`, using Flutter 3.47.6 / Dart 3.13.5. Both dashboard captures use a 1440 × 1100 viewport. The removed Purchasing navigation item is absent in this version.

From `mobile/`, using the SDK pinned in `.flutter-version`:

```sh
flutter pub get --enforce-lockfile
flutter gen-l10n
flutter build web --no-web-resources-cdn --dart-define=DEMO_MODE=true
```

Serve `mobile/build/web` locally and capture the dashboard in Russian and Turkmen at 1440 × 1100. Preserve the demo banner. Do not use production records, credentials, or customer details. Camera scanning and physical printing cannot be validated by these browser images.
