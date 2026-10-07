# Handoff

Last updated at the end of Phase 5, after its simplification (2026-10-07). Read [AGENTS.md](AGENTS.md) first, then this file, then [PLAN.md](PLAN.md). Contains no secrets.

## 1. Branch and commits

- Working branch: `claude/laughing-faraday-3dkwcb` (the only branch this environment may push to). No pull request has been opened; `main` is unchanged since `48a43b4`.
- Commits on the branch, oldest first: onboarding (`73b6a6d`), plan (`dd689a8`, `ac5197b`), Phase 0 CI (`7699ea1`), Phase 1 backend foundation (`1367358`), Phase 2 app foundation (`104ace4`), Phase 3 catalog and scanning (`223f4fe`), Phase 4 backend (`d5e8d10`), Phase 4 app (`6aab221`), Phase 4 documentation (`7f5c431`), Phase 5 backend (`80ff348`), Phase 5 app (`13422e5`), the screen-reader fix and extended browser run (`7ed1e7a`), Phase 5 documentation (`e3f0da9`), then the **simplification after the owner's review**: backend (`3b73a75`), app (`c14fa7a`) and the final documentation commit (see `git log --oneline`).
- CI (GitHub Actions) was green on every push through the Phase 5 app commit, all three jobs each time (`mobile` including the debug APK, which now includes the `printing` plugin, `backend` on PostgreSQL, `docker` image build). Check the runs for the two newest commits on GitHub.

## 2. Implemented vs planned

| Area | Status |
| --- | --- |
| Backend: Django 5.2 + DRF + PostgreSQL 16, JWT sessions with rotation and instant revocation, error envelope, request IDs, audit trail, idempotency records and the operation-status endpoint | Implemented, tested, CI green |
| Businesses, locations, staff, roles and the permission matrix, business isolation (structural test over every route) | Implemented, tested |
| Password recovery by emailed one-time code | Implemented (SMTP settings from the environment; tests use an in-memory backend). **Provider not chosen (D16)** |
| Catalog: products, barcodes, categories, brands, units, reorder levels, warranty terms, TMT/USD price, exchange-rate history | Implemented, tested (backend and app) |
| App: sign-in, session restore, restart-safe pending-operation runner and banner, administration (business, locations, staff, language, exchange rate), catalog screens | Implemented, tested in widget tests |
| Camera barcode scanning (`mobile_scanner`) with torch, permission-denied and no-camera states and a manual fallback | **Implemented, not verified on a real tablet** (see section 6). The camera cannot run in the cloud browser either |
| Stock ledger (append-only movements, balances, FIFO cost layers), opening stock, adjustments, suppliers, purchase orders, partial and repeated receiving, stock and history screens | **Implemented**, tested on PostgreSQL (backend), in widget tests, and in a real-browser run against the real backend |
| Sales: customers, the sale command (idempotent, FIFO cost, **the seller sets the price of every line**, cash or card label, `S-000001` numbers), one plain receipt PDF (Russian or Turkmen, embedded fonts), the sales page with a restart-safe last step, sales history | **Implemented**, tested on PostgreSQL (backend), in widget tests, and in a real-browser run against the real backend. **Printing or sharing on a real tablet is not verified** (step 5.5) |
| Transfers, counts, returns, expenses, warranties, import/export, reports, dashboard | **Not started**; the real build shows an honest "available in a later release" page. The demo screens exist only in the demo build |
| Staging server | Deployment files exist (`backend/Dockerfile`, `infra/`, image builds in CI); **nothing is deployed** (owner step, D2) |
| Printer protocols, label printing, external scanners | Not started; hardware not selected. The receipt is a PDF handed to the tablet's own print and share dialogs |
| iPad/iPhone | Deferred; no iOS host generated |

The default build starts at sign-in and talks to a server (`--dart-define=API_BASE_URL=...`). The in-memory demonstration is a separate build (`--dart-define=DEMO_MODE=true`) or an explicit `store:` in tests, and always shows its banner.

## 3. Decisions recorded (see the table in PLAN.md)

D1 Django + DRF + PostgreSQL (confirmed). D3 business currency TMT; selling price may be stated in TMT or USD, converted with an owner/manager-entered rate that is stored as history; costs, payments, totals and reports are TMT only. D6 costing: each purchase keeps its own cost and the oldest batch is used first (FIFO). D8a warranty terms per product (months, 0 = none, plus text). D9 first scanning method: tablet camera. D16 password recovery by emailed one-time code. **Owner answers on 2026-10-07:** prices are not fixed (the seller sets any price); no tax, no invoices, no legal receipt format, keep one simple receipt; this is an ERP, not a cash register (no change, no amounts tendered, no split payments: only cash or card as a label); selling is in-store and online only; customers stay optional; keep everything simple (Turkmenistan: little internet, old-fashioned). D5 permission matrix, D4 (no tax, `S-000001` numbering) and D10 default language (Russian) are **provisional**.

**Assumptions made without the owner while building Phases 1-4** (all easy to change now, costly later; to confirm):

- Permission matrix: only the owner manages business settings, locations and staff; the manager manages catalog, suppliers, purchase orders, exchange rates, opening stock and adjustments; the warehouse receives goods but sees no costs; sales sees stock quantities at their own locations but no history or costs.
- FIFO means the oldest batch is used first (not average cost). USD applies to selling prices only. A sale (Phase 5) will keep the rate it was made with.
- Opening stock needs a unit cost and is allowed once per product and location; corrections are adjustments with a mandatory reason, posted by owner or manager (D7 open).
- Receiving more than is outstanding is refused. The receipt cost is the cost on the order line. Cancelling a partly received order keeps what arrived.
- Staff are new accounts only; email is required and unique; password at least 10 characters; access token 15 minutes, refresh token 14 days; a reused refresh token just returns 401.
- Purchase orders are numbered `PO-0001...` per business.
- All new Turkmen text, the Turkmen document labels and the default Turkmen unit names are drafts for a fluent speaker to review.

**Assumptions made without the owner while building Phase 5** (to confirm):

- Sale numbers are `S-000001...` per business, taken last in the transaction so there are no gaps; they are only a plain reference.
- Any seller may charge any price, including zero or below cost; the catalog price is only the starting suggestion and stays on the line for reference. The owner sees a loss in the history.
- Payment is only a label, Cash (default) or Card; bank transfer was dropped. No debt or credit sales.
- A completed sale cannot be edited or deleted. Returns and corrections are Phase 7.
- Cost and profit are visible to owner and manager only; they are never printed on the receipt.
- The cart does not reserve stock: if another tablet sells the goods first, the server refuses with the product name and the cart is kept.
- If the answer to "Complete sale" is lost, the cart is emptied and the saved record owns that sale (the pending banner shows it) so the same goods are not sold twice by hand.
- The receipt is one plain 80 mm page of my own design; its language is the business's document-language setting; address and phone (Settings) are printed when filled in.
- Selling needs the server (online only); the restart-safe resend covers a flaky connection. No offline mode.

## 4. Checks actually run

Run from this VM (Flutter 3.47.6 / Dart 3.13.5; Python 3.13 with uv; PostgreSQL 16):

| Check | Result |
| --- | --- |
| `dart format --output=none --set-exit-if-changed lib test` | Passed |
| `flutter analyze` | Passed, no issues |
| `flutter test` | Passed: 195 tests (demo store, API client, session, operation runner incl. the restart scenario, decimal maths, repositories, real-mode widgets, catalog, scanning with a fake scanner, exchange rate, stock, purchasing and receiving incl. lost answer then restart, **selling: cart maths, any price (lower, higher, zero, USD product with no rate), scan adds only, cash or card, refused sale naming the product, the receipt through a fake device, a lost answer then restart gives exactly one sale, history and roles (a loss shows to the owner), screen-reader names of every text field, layouts at 360/800 with doubled text**, business details form, ARB parity) |
| ARB parity (`app_ru.arb` vs `app_tk.arb`) | 501 keys each, identical sets. This shows coverage, not translation quality |
| `uv run ruff check` / `ruff format --check` | Passed |
| `manage.py check`, `makemigrations --check --dry-run` | Passed |
| `manage.py test` (PostgreSQL) | Passed: 265 tests, including multi-threaded races (duplicate receipts, oversell, opposite lock order, **two tablets selling the last unit, twelve concurrent sales of five units, eight concurrent copies of one sale**), append-only triggers and raw-SQL attempts on balances/layers/movements/**sales**, FIFO costs, **the seller's price (lower, higher, zero, negative refused, a USD product sold with no rate, a later catalog change never touching a sale), half-up rounding, cash or card, gapless numbering after a failed sale, the warranty snapshot surviving a product edit, receipt content type, permissions, ru vs tk text, Cyrillic and Turkmen glyphs read back with pypdf, embedded fonts, no cost on the receipt**, cross-business isolation and role/cost-hiding rules. `reconcile()` is asserted empty after every scenario. Mutation checks (removing the row lock, reversing FIFO order, the server ignoring the seller's price) make the tests fail, as intended |
| `manage.py reconcile_stock` | Passed: "Ledger is consistent" on the dev database, and again after the browser run |
| `flutter build web --no-web-resources-cdn` | Passed (also with `--dart-define=API_BASE_URL=...` for the browser run) |
| GitHub Actions on the Phase 5 app commit (`13422e5`) | **Green, all three jobs, including the Android debug APK with the `printing` plugin** |
| **Real-stack browser run** (`scripts/e2e/`, headless Chromium + Playwright against the web build, the real Django API and PostgreSQL) | **Passed: 71 of 71 checks**, no unexpected browser errors. Phases 1-4 (44 checks): sign-in; exchange rate; TMT and USD products; supplier; purchase order; partial receipt; a receipt whose answer is dropped after commit and a reload as the tablet restart (exactly two deliveries, stock exactly 10, nothing left pending); stock value 500,00 (FIFO); history; Russian to Turkmen kept after reload; the warehouse user sees no TMT amount. **Phase 5, after the simplification (27 more):** the owner sells 3 pieces from the Warehouse at a price typed by the seller (100 instead of the catalog 120) paid in cash, and the database shows one sale at 300,00, price 100,00, method cash, FIFO cost 150,00, stock 7; the page shows no change or amount fields; the Receipt button downloads a PDF from the server; a second sale paid by card (2 x 120 = 240,00) whose answer is dropped after commit (the app does not claim success and lists it), then a reload: exactly two sales, numbers 1 and 2 without a gap, stock exactly 5, `reconcile` consistent; the history lists both; the receipt read back with `pypdf` (Russian: product name, number, price charged, total, Cash, and no cost, profit, change, discount or invoice wording; Turkmen receipt: Turkmen labels and Card); the warehouse user has no Sales page |
| Android debug APK | **Only built in GitHub Actions**; this VM has no Android SDK |
| Docker image build | **Only built in GitHub Actions**; this VM has no Docker daemon |

**Not verified anywhere:** camera scanning on a real tablet; **the system print and share dialogs for the receipt on a real tablet, and any real printer (80 mm width, glyphs on paper)**; Android runtime behaviour (the APK is only compiled in CI); staging deployment and reachability from Turkmenistan; email delivery through a real provider; TalkBack (the browser run did expose and fix a real screen-reader defect, see below, but no screen reader was run); iOS; Turkmen wording by a fluent speaker; whether the plain receipt is acceptable locally (the owner decided no legal format is needed).

**Found and fixed in Phase 5:** a flaky Phase 4 test (it looked for the text `30.00` and failed whenever a timestamp read `...:30.00...`; it now checks whole JSON values), a loss shown as no profit at all (the app parser rejected `-20.00`), and, from the browser run: on the cash desk the search field's accessibility node absorbed the text of the whole page (a screen reader would read the page as the field's name). `BarcodeInput` now has its own semantics container and a test checks the name of every text field on the cash desk and payment page; it fails without the fix.

## 5. Environment notes (Claude Code cloud)

- Fresh VM: `bash scripts/setup_claude_cloud.sh`, then `source scripts/claude_cloud_env.sh` in each shell. Start the local database with `bash scripts/claude_cloud_postgres.sh` (writes the git-ignored `backend/.env`), then run the backend commands from `backend/` as listed in AGENTS.md.
- `dl.google.com` is blocked in this environment, so there is no local Android SDK. GitHub Actions builds the APK instead. This is an environment limit, not an application defect.
- Reachable: `github.com`, `pub.dev`, `storage.googleapis.com`, the Python package index, `maven.google.com`, `services.gradle.org`.
- Git: ordinary pushes to the assigned branch only, never forced.
- Tests that drive taps through `tapKey` (`mobile/test/support/real_rig.dart`) pump frame by frame after scrolling (a scrollable ignores taps until its scroll animation has finished) and once after the tap. Use `goBack` to leave a pushed screen: the route needs about 800 ms to leave.
- The real-stack browser run is in `scripts/e2e/` (README there). It reads receipts back with `scripts/e2e/pdf_text.py` (pypdf, a backend dev dependency). Do not run `reset_db.sh` against anything but a throwaway local database: it flushes it.
- Avoid `pkill -f` patterns that also match the command line of your own shell; use a bracket trick in a separate command or look up the PID first.

## 6. Owner checklist (cannot be done from the cloud session)

1. **Real-tablet camera test (PLAN step 3.3, stays unticked until done).** Install a build on the pilot tablet and record: device and Android version; permission prompt appears and "deny" shows the explanation with manual entry; EAN-13, Code 128 and QR codes from real packaging; dim and bright light; speed from tapping the camera button to the product appearing; the torch button; a scan in the product form adds the code to the draft only; a scan of an unknown code offers "add product" and saves nothing.
2. Choose a host (D2), deploy the container with `infra/` and open the health address **from the shop's own internet connection**.
3. Choose an SMTP provider (D16) and test that the recovery email arrives from Turkmenistan.
4. Review the provisional rules and assumptions: the permission matrix (D5), the FIFO reading of D6, USD only for selling prices, default Turkmen unit names, opening stock once per product and location, over-receipt refused, receipt cost = order-line cost, owner/manager-only adjustments (D7), `PO-0001` numbering, and the Phase 5 list in section 3 (receipt numbers `S-000001`, no price override at the desk, payment rules, immutable sales, cost visible to owner and manager only). The same lists are in the final message of the session that produced this file.
5. GitHub: require the CI checks on `main`; decide when to open a pull request.
6. Allow `dl.google.com` in the Claude Code cloud network settings if local Android builds are wanted.
7. Have fluent speakers review the Turkmen wording (every Turkmen string for the new screens, and the Turkmen receipt labels, is a draft).
8. **Pilot walkthrough (PLAN step 5.5, stays unticked until done).** With a build on the pilot tablet connected to staging: fill in the business's address and phone (Settings); receive stock; sell at the catalog price and at a different price, paying cash and card; print and share a receipt in Russian and in Turkmen and look at the paper or the shared file; sell the last unit from two tablets; switch the tablet to flight mode right after tapping "Complete sale", reconnect and check there is exactly one sale; switch the interface language with a full cart. Record device, Android version and findings here.
9. Choose the receipt printer if one is wanted (D9). Nothing about tax or invoices is needed (owner decision, 2026-10-07).

## 7. Next steps

Phase 6 (transfers and stock counts) per PLAN.md. It builds on what exists: `inventory.services.post()` (transfers become paired postings with an in-transit state; FIFO layers must travel with the goods), `run_idempotent` plus the app's `OperationRunner` (action slugs such as `transfer_create`), and the permission matrix. Before starting, the owner should answer D13 (stock-count policy for sales and receipts during a count) and D7 for stock adjustments (who approves, limits). The remaining Stage 1 step is 5.5, the pilot-tablet walkthrough (owner checklist item 8). Update this file and tick PLAN.md checkboxes only for steps that were done and verified.

## 8. Switching back to Codex

Tell Codex: "Continue from the branch `claude/laughing-faraday-3dkwcb`. Read `HANDOFF.md`, `AGENTS.md` and `PLAN.md` first, then `docs/PRD.md`. The backend is in `backend/` (uv, Django); the Flutter app is in `mobile/`. Use the Codex scripts under `scripts/` as before for the Codex cloud. Report what you verify yourself."
