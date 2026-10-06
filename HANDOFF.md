# Handoff

Last updated at the end of Phase 3 (2026-10-06). Read [AGENTS.md](AGENTS.md) first, then this file, then [PLAN.md](PLAN.md). Contains no secrets.

## 1. Branch and commits

- Working branch: `claude/laughing-faraday-3dkwcb` (the only branch this environment may push to). No pull request has been opened; `main` is unchanged since `48a43b4`.
- Commits on the branch, oldest first: onboarding (`73b6a6d`), plan (`dd689a8`, `ac5197b`), Phase 0 CI (`7699ea1`), Phase 1 backend foundation (`1367358`), Phase 2 app foundation (`104ace4`), Phase 3 catalog and scanning (see `git log --oneline`).
- CI (GitHub Actions) was green on each of the Phase 0, 1 and 2 pushes, all three jobs (`mobile` including the debug APK, `backend`, `docker`). The Phase 3 result is recorded in section 4 once it has run.

## 2. Implemented vs planned

| Area | Status |
| --- | --- |
| Backend: Django 5.2 + DRF + PostgreSQL 16, JWT sessions with rotation and instant revocation, error envelope, request IDs, audit trail, idempotency records and the operation-status endpoint | Implemented, tested, CI green |
| Businesses, locations, staff, roles and the permission matrix, business isolation (structural test over every route) | Implemented, tested |
| Password recovery by emailed one-time code | Implemented (SMTP settings from the environment; tests use an in-memory backend). **Provider not chosen (D16)** |
| Catalog: products, barcodes, categories, brands, units, reorder levels, warranty terms, TMT/USD price, exchange-rate history | Implemented, tested (backend and app) |
| App: sign-in, session restore, restart-safe pending-operation runner and banner, administration (business, locations, staff, language, exchange rate), catalog screens | Implemented, tested in widget tests |
| Camera barcode scanning (`mobile_scanner`) with torch, permission-denied and no-camera states and a manual fallback | **Implemented, not verified on a real tablet** (see section 6) |
| Stock ledger, purchasing, receiving | See the Phase 4 section of PLAN.md; status in section 4 |
| Sales, payments, receipts, transfers, counts, returns, expenses, warranties, import/export, reports, dashboard | **Not started**; the real build shows an honest "available in a later release" page. The demo screens exist only in the demo build |
| Staging server | Deployment files exist (`backend/Dockerfile`, `infra/`, image builds in CI); **nothing is deployed** (owner step, D2) |
| Receipt/label printing, external scanners | Not started; hardware not selected |
| iPad/iPhone | Deferred; no iOS host generated |

The default build starts at sign-in and talks to a server (`--dart-define=API_BASE_URL=...`). The in-memory demonstration is a separate build (`--dart-define=DEMO_MODE=true`) or an explicit `store:` in tests, and always shows its banner.

## 3. Decisions recorded (see the table in PLAN.md)

D1 Django + DRF + PostgreSQL (confirmed). D3 business currency TMT; selling price may be stated in TMT or USD, converted with an owner/manager-entered rate that is stored as history; costs, payments, totals and reports are TMT only. D6 costing: each purchase keeps its own cost and the oldest batch is used first (FIFO). D8a warranty terms per product (months, 0 = none, plus text). D9 first scanning method: tablet camera. D16 password recovery by emailed one-time code. D5 permission matrix and D10 default language (Russian) are **provisional**.

## 4. Checks actually run

Run from this VM (Flutter 3.47.6 / Dart 3.13.5; Python 3.13 with uv; PostgreSQL 16):

| Check | Result |
| --- | --- |
| `dart format --output=none --set-exit-if-changed lib test` | Passed |
| `flutter analyze` | Passed, no issues |
| `flutter test` | Passed: 129 tests (demo store, API client, session, operation runner incl. the restart scenario, decimal maths, repository, real-mode widgets, catalog, scanning with a fake scanner, exchange rate, ARB parity, layouts at 360/800/1400 with doubled text) |
| ARB parity (`app_ru.arb` vs `app_tk.arb`) | 366 keys each, identical sets. This shows coverage, not translation quality |
| `uv run ruff check` / `ruff format --check` | Passed |
| `manage.py check`, `makemigrations --check --dry-run` | Passed |
| `manage.py test` (PostgreSQL) | Passed: 131 tests, including multi-threaded idempotency races, append-only triggers, cross-business isolation and catalog rules |
| `flutter build web --no-web-resources-cdn` | Passed (Phase 3 build recorded below) |
| Android debug APK | **Only built in GitHub Actions**; this VM has no Android SDK |
| Docker image build | **Only built in GitHub Actions**; this VM has no Docker daemon |

**Not verified anywhere:** camera scanning on a real tablet, Android runtime behaviour (the APK is only compiled in CI), staging deployment and reachability from Turkmenistan, email delivery through a real provider, TalkBack, iOS, Turkmen wording by a fluent speaker.

## 5. Environment notes (Claude Code cloud)

- Fresh VM: `bash scripts/setup_claude_cloud.sh`, then `source scripts/claude_cloud_env.sh` in each shell. Start the local database with `bash scripts/claude_cloud_postgres.sh` (writes the git-ignored `backend/.env`), then run the backend commands from `backend/` as listed in AGENTS.md.
- `dl.google.com` is blocked in this environment, so there is no local Android SDK. GitHub Actions builds the APK instead. This is an environment limit, not an application defect.
- Reachable: `github.com`, `pub.dev`, `storage.googleapis.com`, the Python package index, `maven.google.com`, `services.gradle.org`.
- Git: ordinary pushes to the assigned branch only, never forced.
- Tests that drive taps through `tapKey` (`mobile/test/support/real_rig.dart`) pump frame by frame after scrolling: a scrollable ignores taps until its scroll animation has finished.

## 6. Owner checklist (cannot be done from the cloud session)

1. **Real-tablet camera test (PLAN step 3.3, stays unticked until done).** Install a build on the pilot tablet and record: device and Android version; permission prompt appears and "deny" shows the explanation with manual entry; EAN-13, Code 128 and QR codes from real packaging; dim and bright light; speed from tapping the camera button to the product appearing; the torch button; a scan in the product form adds the code to the draft only; a scan of an unknown code offers "add product" and saves nothing.
2. Choose a host (D2), deploy the container with `infra/` and open the health address **from the shop's own internet connection**.
3. Choose an SMTP provider (D16) and test that the recovery email arrives from Turkmenistan.
4. Review the provisional rules listed in the final message of the session that produced this file (permission matrix, FIFO reading, rounding, default unit names, over-receipt).
5. GitHub: require the CI checks on `main`; decide when to open a pull request.
6. Allow `dl.google.com` in the Claude Code cloud network settings if local Android builds are wanted.
7. Have fluent speakers review the Turkmen wording (every Turkmen string for the new screens is a draft).

## 7. Next steps

Phase 4 (stock ledger, purchasing, receiving) per PLAN.md, then Phase 5 (sales). Update this file and tick PLAN.md checkboxes only for steps that were done and verified.

## 8. Switching back to Codex

Tell Codex: "Continue from the branch `claude/laughing-faraday-3dkwcb`. Read `HANDOFF.md`, `AGENTS.md` and `PLAN.md` first, then `docs/PRD.md`. The backend is in `backend/` (uv, Django); the Flutter app is in `mobile/`. Use the Codex scripts under `scripts/` as before for the Codex cloud. Report what you verify yourself."
