# Developer setup

For the quickest complete test environment, start with [LOCAL_TEST.md](LOCAL_TEST.md). For an interface-only preview, use the README's [demo commands](../README.md#interface-only-demo-for-developers). The commands below describe development from source, not production deployment.

## Pinned toolchains

| Component | Required setup |
| --- | --- |
| Flutter | 3.47.6 from `.flutter-version`, commit `5fc346839b5d0eef006ed8404392afb4dfae428d` |
| Python | 3.13, as required by `backend/pyproject.toml` |
| Python dependencies | `uv`, `backend/uv.lock` |
| Database | PostgreSQL; CI uses version 16, SQLite is unsupported |
| Android | Android SDK with API 36 and Java 21; Gradle wrapper included |

Keep `mobile/pubspec.lock` and `backend/uv.lock`. Use frozen dependency resolution; do not replace the pinned SDK just to get a build to pass. Apple builds require macOS/Xcode or a suitable build service.

## Backend with an existing PostgreSQL installation

1. Create a disposable development database and a local role. The role needs permission to create a test database to run Django tests.
2. Copy `backend/.env.example` to `backend/.env`, enter the local database settings and a random secret key, and keep `DJANGO_ENV=development` and `DJANGO_DEBUG=true` only for development. The settings loader reads this file automatically.
3. From `backend/`:

```sh
uv sync --frozen
uv run python manage.py migrate
uv run python manage.py createcachetable
uv run python manage.py create_business --name "Test shop" --owner-username owner --owner-email owner@example.test --location "Main store"
uv run python manage.py runserver 127.0.0.1:8000
```

The business command prompts for its owner's password. Alternatively, the local test launcher creates a sample business and its test accounts for you. Do not use real shop data for testing.

Health: `http://127.0.0.1:8000/api/v1/health/`. For a separate local web frontend, set `DJANGO_CORS_ALLOWED_ORIGINS=http://localhost:8080,http://127.0.0.1:8080` in the backend environment and restart the API.

## Flutter app

From `mobile/`:

```sh
flutter pub get --enforce-lockfile
flutter gen-l10n
flutter run -d chrome --web-port 8080 --dart-define=API_BASE_URL=http://localhost:8000
```

This runs a connected development build. For sample data without the API, add `--dart-define=DEMO_MODE=true` instead. The demo has a visible banner and resets business changes on restart.

For Android, use `flutter devices` and `flutter run -d <device-id>`. The sign-in screen lets a device choose its server. On an Android emulator, the host computer is reached at `http://10.0.2.2:8000`; a physical tablet needs the computer's LAN address and appropriate private-network access. Plain HTTP is for debug development; release builds require HTTPS.

## Checks

From `mobile/`:

```sh
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter build web --no-web-resources-cdn
flutter build apk --debug
```

From `backend/`, with a disposable PostgreSQL database configured:

```sh
uv run ruff check .
uv run ruff format --check .
uv run python manage.py check
uv run python manage.py makemigrations --check --dry-run
uv run python manage.py test
uv run python manage.py reconcile_stock
```

Stock concurrency tests need PostgreSQL. `reconcile_stock` checks the records in the configured database; it is not a substitute for tests. For business workflow changes, see the [real-stack browser checks](../scripts/e2e/README.md). Their reset helper flushes its database: use an isolated throwaway environment.

Build outputs are `mobile/build/web/` and `mobile/build/app/outputs/flutter-apk/app-debug.apk`. A debug APK uses development signing. A compiled build does not verify camera, scanner, printer, sharing, or accessibility behavior on a tablet.

## Cloud helpers

### Codex cloud

From the repository root in the Linux cloud environment:

```sh
bash scripts/setup_cloud.sh
source scripts/cloud_env.sh
```

The helper reuses the pinned SDK, installs missing Android prerequisites, resolves the retained lockfile, and sets up a complete Java 21 JDK. It uses the environment's existing proxy and public CA with TLS verification. A Maven Central mirror is configured in the cloud Gradle cache; workstation repository settings are unaffected.

### Claude Code cloud

```sh
bash scripts/setup_claude_cloud.sh
source scripts/claude_cloud_env.sh
bash scripts/claude_cloud_postgres.sh
```

The PostgreSQL helper is for a fresh cloud VM: it creates a local database and writes `backend/.env`. The Flutter helper supports web checks and omits Android because that environment blocks `dl.google.com` by default. See [HANDOFF.md](../HANDOFF.md) for environment limitations.

### Preview a web build

From `mobile/build/web/`:

```sh
python -m http.server 8080 --bind 127.0.0.1
```

Use internal browser requests in a cloud environment. For a real web build, the API origin must match the build configuration and backend CORS settings. To serve the web build beside the API locally, the test launcher accepts `--web mobile/build/web`.

## Deployment and private files

Use [DEPLOY_TESTING.md](DEPLOY_TESTING.md), [ANDROID_RELEASE.md](ANDROID_RELEASE.md), and the [infra runbook](../infra/README.md). Private product images, receipt photos and documents live under `PRIVATE_FILES_ROOT`, outside public static serving. Back up that directory together with PostgreSQL and verify recovery in a separate environment.
