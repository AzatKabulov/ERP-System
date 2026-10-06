# Agent Instructions

## Project Context

This project is an inventory-focused ERP for shops and wholesalers, with car parts stores as the first target market. The agreed scope is documented in `docs/PRD.md`.

- Confirmed client: Flutter and Dart, with Android tablets first, followed by iPad and iPhone.
- Confirmed launch market and languages: Turkmenistan; complete Russian (`ru`) and Turkmen (`tk`, modern Latin script) interfaces are required from the first Android release.
- Confirmed backend (2026-10-06): Python, Django, and Django REST Framework; not yet implemented.
- Confirmed database (2026-10-06): PostgreSQL; not yet implemented.
- Initial operating model: internet access is required for stock-changing actions; business records are isolated by business and location permissions.

The repository contains a Flutter interface prototype under `mobile/`, using in-memory demonstration operations and persistent language selection. Android and web hosts are present. Flutter 3.47.6 is pinned in `.flutter-version`; cloud activation and setup helpers are under `scripts/`. Analysis, 12 tests, web and debug APK builds, and interactive browser checks passed. Physical Android hardware and iOS remain untested. The backend is not implemented. Do not describe demonstration operations as production functionality.

## Before You Start

1. Read this file, `docs/PRD.md`, `HANDOFF.md` (current state), and `PLAN.md` (phased delivery order).
2. Read `docs/DESIGN_SYSTEM.md` before UI changes and `docs/ARCHITECTURE.md` before technical changes. The architecture distinguishes the current demonstration implementation from the planned production backend.
3. Inspect the working tree, relevant source files, existing widgets and services, dependency manifests, version pins, and any more specific `AGENTS.md` instructions before editing.
4. Follow the user's latest decisions. If documentation is stale, update the affected document as part of the authorized task rather than continuing with the old decision.
5. Resolve routine implementation details using existing conventions. Ask only when a missing decision materially affects scope, architecture, or business behavior and cannot be inferred. Continue independent work while clarification is pending.

## General Rules

- Work in the existing checkout. Cloud tasks already have isolated environments; do not create a Git worktree unless the user requests one.
- Preserve unrelated user changes. Never reset the repository or overwrite existing files to make a task easier.
- Implement the requested workflow completely, including validation and failure states. Keep changes focused on the task.
- Keep the full agreed feature scope visible. Delivery stages determine order; do not silently remove later-stage features.
- Reuse existing code before introducing another widget, service, abstraction, or dependency.
- Use pinned toolchains and lockfiles once established. Document necessary dependency additions and do not upgrade unrelated packages.
- Keep product scope in the PRD, visual rules in the design system, and technical decisions in the architecture document. Avoid duplicating long requirements across files.
- Keep setup instructions and command examples accurate as the repository changes.

## Code Guidelines

### Flutter and Dart

- Use Dart for the shared application. Do not introduce TypeScript or a separate native application without an authorized architectural decision.
- Follow Dart naming conventions: `snake_case` file names, `UpperCamelCase` types, and `lowerCamelCase` members.
- Use null safety and explicit types where they clarify public interfaces. Use immutable models and `const` widgets where appropriate.
- Keep widgets focused on presentation and interaction. Put API access and business coordination in the appropriate services or repositories, following the architecture once established.
- Represent loading, empty, validation, success, and failure states explicitly. Do not show success before the backend confirms the operation.
- Use the chosen state-management and navigation conventions consistently. Do not add competing frameworks for individual features.
- Handle asynchronous work, cancellation, and widget disposal correctly. Avoid duplicate submissions and retain the operation identity when retrying a stock-changing request.

### Backend and Database

- In the backend, use Python conventions, focused Django applications, clear API serializers, and type annotations where useful.
- Keep business rules out of UI code and avoid duplicating them across API endpoints.
- Use decimal arithmetic for money and documented rounding rules. Do not calculate financial totals using binary floating-point values.
- Use database transactions and appropriate concurrency controls for operations affecting stock or finalized financial records.
- Validate quantities, state transitions, and available stock on the server. Retried operations must not create duplicate records or movements.
- Make business and location access explicit in queries and actions. Never trust a client-supplied business identifier without checking membership and permissions.
- Retain finalized transaction history. Corrections use linked reversals or adjustments, with reasons and responsible users.
- Use database migrations for schema changes. Review their effect on existing data and deployment compatibility.

## Design Rules

- Follow `docs/DESIGN_SYSTEM.md`: off-white surfaces, electric-blue accents, restrained depth, and tablet-focused layouts. Distinguish provisional choices from established design tokens.
- Build reusable Flutter themes and widgets rather than hardcoding separate styles in each screen.
- Design for tablet portrait and landscape layouts, then adapt to smaller screens. Base layout decisions on available space rather than device names alone.
- Provide readable contrast, text scaling, accessible labels, comfortable touch targets, and clear focus behavior where keyboard or scanner input is supported.
- Use clear business language in the interface. Keep technical implementation details out of user-facing workflows.
- Make destructive actions and financial consequences clear. Provide suitable confirmation or approval where the business policy requires it.
- Test long product names, empty catalogs, large values, and validation failures. Scanning must have a usable manual-entry fallback.
- Do not promise scanner or printer compatibility without validating the selected hardware and platform.

## Localization Rules

- Implement Russian and Turkmen as first-release requirements, not optional later translations.
- Keep user-facing system strings in Flutter localization resources, using ARB files and generated localization accessors when the scaffold is established. Do not hardcode interface strings inside widgets.
- Include validation messages, authentication screens, notifications, accessibility labels, reports, and generated business documents in localization coverage. Use parameterized messages and proper plural handling rather than assembling sentences from fragments.
- Verify the chosen Flutter localization delegates and formatting libraries support `tk`. Where support is missing, provide tested locale data or delegates; do not substitute Turkish (`tr`) for Turkmen.
- Remember each user's selected language. Preserve entered form data when switching languages. Keep document-language selection separate from interface-language selection.
- Use fonts that cover Russian Cyrillic, including `Ёё`, and Turkmen Latin characters, including `Ää`, `Çç`, `Ňň`, `Öö`, `Şş`, `Üü`, `Ýý`, and `Žž`. Verify document and print fonts as well as screen fonts.
- Preserve Unicode user data through the API, database, search, CSV imports and exports, and document generation. Do not transliterate or automatically translate product names, customer names, or identifiers when the locale changes.
- Format displayed dates, numbers, and currency using verified locale support and business settings. Do not infer currency or tax policy from a user's interface language.
- Return structured API error codes and parameters where practical so the client can display localized messages instead of exposing English server exceptions.
- Test affected screens and workflows in both languages, including long text, text scaling, language persistence, missing translations, and document output. Mark provisional translations for fluent-speaker review rather than claiming they are approved.

## Security Rules

- Never commit credentials or include server secrets in Flutter code, assets, build configuration, screenshots, or logs.
- Use environment configuration for server secrets and platform-appropriate secure storage for mobile sessions. Do not request secret values in chat.
- Enforce authentication, business isolation, location access, and action permissions on the server. Hiding a button does not provide authorization.
- Apply access controls to reports, exports, uploads, and document downloads as well as ordinary API records.
- Validate uploaded file type and size, import data, and user input. Protect spreadsheet-compatible exports against formula injection.
- Use verified HTTPS for remote services. Do not disable TLS, package-signature, or checksum verification to bypass setup failures.
- Keep customer data, session tokens, and secrets out of logs. Audit important business changes without logging sensitive payloads unnecessarily.
- Do not weaken production protections for development convenience. Local development overrides must be scoped, documented, and excluded from production configuration.

## Commands

On the cloud machine, first run `source /workspace/ERP-System/scripts/cloud_env.sh`. The helper activates the SDK paths, caches, complete Java JDK, browser, and Java proxy settings required by this environment. `bash scripts/setup_cloud.sh` from the repository root prepares missing dependencies and a cloud-cache Maven Central mirror with TLS verification enabled. Setup has completed successfully; see `README.md` for the validation status.

### Flutter Commands

Working directory: `/workspace/ERP-System/mobile`. Dependency resolution, localization generation, formatting, analysis, tests, and the Android/web builds below have run successfully. Device execution requires an attached device or emulator.

| Purpose | Command |
| --- | --- |
| Inspect SDK and device prerequisites | `flutter doctor -v` |
| Install declared dependencies | `flutter pub get` |
| Refresh dependencies without changing an existing lockfile | `flutter pub get --enforce-lockfile` |
| Generate localized strings | `flutter gen-l10n` |
| Check formatting, once both directories exist | `dart format --output=none --set-exit-if-changed lib test` |
| Analyze code | `flutter analyze` |
| Run unit and widget tests | `flutter test` |
| List available devices | `flutter devices` |
| Run on a selected device | `flutter run -d <device-id>` |
| Build a debug Android APK | `flutter build apk --debug` |
| Build the same interface with local rendering resources | `flutter build web --no-web-resources-cdn` |

Use Flutter 3.47.6 and retain `mobile/pubspec.lock`; use frozen resolution during setup. The prototype uses `ChangeNotifier`/`AnimatedBuilder`, generated ARB localizations, and `SharedPreferences` only for the selected language. iOS builds require a suitable macOS/Xcode environment or configured cloud build service; do not claim they were verified on a Linux environment.

For internal web smoke testing, serve a successfully built `mobile/build/web` directory using `python -m http.server 8080 --bind 127.0.0.1`. Do not expose localhost preview links in cloud onboarding. Use local requests and browser checks instead.

The debug APK build and APK signature have been verified. This does not establish real-device scanner or printer compatibility, release signing, or store readiness.

### Planned Backend Commands

Working directory: the future backend directory, tentatively `backend/`. These commands assume Django has been installed from the chosen dependency manifest into an active project virtual environment and `manage.py` exists.

| Purpose | Command |
| --- | --- |
| Check Django configuration | `python manage.py check` |
| Check for missing migrations | `python manage.py makemigrations --check --dry-run` |
| Apply migrations to the configured local development database | `python manage.py migrate` |
| Run backend tests | `python manage.py test` |
| Run the local development server | `python manage.py runserver 127.0.0.1:8000` |

The dependency installation command, required environment variables, PostgreSQL startup, formatting and linting tools, and health checks must be added after the actual scaffold is chosen and validated. Use the project's selected test runner if it differs from Django's runner. Do not invent a dependency filename or configuration module.

## Validation and Reporting

- Run checks appropriate to the change. Documentation-only changes require review for accuracy and consistency, not an application build.
- For business logic changes, cover relevant stock movements, returns, partial deliveries, transfer states, permissions, and duplicate-request behavior with meaningful tests.
- Run stock concurrency checks against PostgreSQL when that database is adopted; SQLite results alone do not validate PostgreSQL locking behavior.
- Test widgets and API failure states for the affected workflow. Run existing integration or device checks when the change involves platform behavior.
- Confirm tests actually executed. Distinguish passing, failing, skipped, and unrun checks; a zero-test run is not validation.
- Do not disable assertions or weaken checks to obtain a passing result. Diagnose whether failures come from setup or application defects.
- Report what changed, what was verified, and any remaining limitations. A successful build does not prove a scanner, printer, stock workflow, or backup restore works.

## Boundaries

- Do not change the agreed framework, product scope, offline operating model, or major architecture without authorization. A user request explicitly directing that change is sufficient; do not request duplicate approval.
- Do not invent tax rules, inventory costing policies, warranty terms, refund eligibility, or approval limits. Use documented decisions or clarify the decision before finalizing the affected behavior.
- Do not deploy, publish app releases, send messages to external parties, or run destructive operations on shared or production data without authorization.
- Test backup restoration in a separate environment. Never restore over active business records as a routine verification step.
- Routine reversible fixes, relevant tests, and documentation updates within the requested task do not need a separate approval step.
