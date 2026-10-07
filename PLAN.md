# Delivery Plan

Status: approved roadmap, 2026-10-06; revised the same day after Codex's review and the owner's answers (see "Revision history" at the end). Scope is defined in [docs/PRD.md](docs/PRD.md), the technical design in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md), the visual rules in [docs/DESIGN_SYSTEM.md](docs/DESIGN_SYSTEM.md) and the development rules in [AGENTS.md](AGENTS.md). This plan only orders the work. When it conflicts with those documents, they win; update this plan.

Starting point: a bilingual Flutter interface prototype that runs on demonstration data only (see [HANDOFF.md](HANDOFF.md)).

**Progress (2026-10-07): Phases 1, 2, 3, 4, 5 and 6 are implemented and verified** (Phase 5 was simplified the same day after the owner's feedback: free prices, cash or card only, one plain receipt, no invoice, no tax) (backend, app, CI, and a real-browser run against the real backend; HANDOFF section 4 has the evidence). Still open and needing the owner: step 0.1/0.2, 0.3's branch protection, 2.1 (a deployed staging server), 3.3 (camera scan on the pilot tablet) and 5.5 (the pilot-tablet walkthrough, which also covers printing and sharing receipts on the device, transfers and counts). Phase 7 (returns, refunds and reordering) is next.

## How to use this plan

1. Pick the first phase that is not finished. Check its **Before you start** list. Those are your decisions, and the phase cannot be finished without them.
2. Start a new Claude Code or Codex session on this repository and paste:
   > Implement Phase N of PLAN.md (or only step N.M). First read AGENTS.md, HANDOFF.md and PLAN.md. Follow the "Every phase" rules. Run all checks, update HANDOFF.md and tick the finished boxes in PLAN.md, then commit, push and open a pull request.
3. Large phases can be handed over **one numbered step at a time**. Every step ends in a working, mergeable state.
4. Merge the pull request when the automatic checks (CI) are green and you are happy with the summary. Then continue.
5. If a phase reveals a new decision, the agent adds it to the decision list below and pauses **only the work that depends on it**; it does not guess, and it continues every independent step meanwhile.

## Every phase (definition of done)

- New behavior has tests: backend tests include permission and cross-business denial; Flutter has unit and widget tests. All existing tests pass and CI is green.
- Every new screen text exists in Russian and Turkmen ARB files. Provisional translations are marked for review.
- Screens show loading, empty, error and success states. Nothing shows success before the server confirms it.
- Money uses decimal arithmetic. Stock changes only through the inventory service, and stock-changing requests carry an operation key so a retry never duplicates them.
- Stock-changing actions (receiving, sales, transfers, refunds, adjustments) are **restart-safe**. Before sending, the app saves a pending-operation record (operation key, action, payload) on the device and keeps it until the server confirms. After a timeout, a crash or a restart, the app asks the server for the outcome of that key and retries only with the **same** key, so one action can never become two. Each such workflow has a test for "server committed, answer lost, app restarted, exactly one record".
- Permissions and business isolation are enforced on the server, not only hidden in the app.
- Docs stay current: ARCHITECTURE status, AGENTS commands, README, HANDOFF and the PLAN checkboxes.
- No secrets, keys or generated builds are committed.

## Phase overview

| Phase | Result | PRD stage | Size |
| --- | --- | --- | --- |
| 0. Preparation | CI on every pull request, Android builds, first decisions recorded | — | M |
| 1. Backend foundation | Django API with businesses, locations, staff roles, sign-in, audit | 1 | XL |
| 2. App foundation and test server | App signs in to a real test server from Turkmenistan; administration screens | 1 | XL |
| 3. Catalog and barcode lookup | Real product catalog; camera scanning works on the pilot tablet | 1 | L |
| 4. Stock ledger, purchasing and receiving | Real stock per location; purchase orders with partial deliveries | 1 | XL |
| 5. Sales, payments and receipts | Real sales with safe retries; receipts/invoices in both languages; **Stage 1 complete** | 1 | XL |
| 6. Transfers and stock counts | Dispatch, in-transit and receipt between locations; counts with approval | 2 | L |
| 7. Returns, refunds and reordering | Linked returns, refunds, exchanges, supplier returns, reorder list; **Stage 2 complete** | 2 | L |
| 8. Expenses, warranties, import/export | Expenses with receipts, warranty claims, CSV catalog import and exports | 3 | L |
| 9. Reports, dashboard, activity history | Real reports and dashboard, audit review | 3 | L |
| 10. Production and pilot | Live server, verified backups, release build, pilot store running; **Stage 3 complete** | 3 | XL |
| 11. Apple release | iPad and iPhone apps; **Stage 4 complete** | 4 | L |

## Owner decisions

Agents must not invent these (AGENTS.md "Boundaries"). Record each answer in the PRD or ARCHITECTURE document named, then mark it here.

| ID | Decision | Needed before | Status |
| --- | --- | --- | --- |
| D1 | Backend technology | Phase 1 | **Confirmed 2026-10-06: Django + DRF + PostgreSQL** |
| D2 | Hosting provider and region, reachable from the pilot store's internet in Turkmenistan | Phase 2 (test server, provisional); Phase 10 (final) | Open |
| D3 | Business currency, decimal places, rounding | Phase 3 | **Decided 2026-10-06:** business currency TMT (2 decimals, rounded half up). A product's selling price may be stated in TMT or USD and is converted to TMT at an owner/manager-entered rate that is saved on each sale. Costs, totals, payments and reports are TMT only. Recorded as a scope change in the PRD. |
| D4 | Receipt/invoice format, tax rules, document numbering | Phase 5 | **Closed 2026-10-07 (owner):** no tax, no invoices, no legal format. One simple receipt; sales are numbered `S-000001...` per business as a plain reference |
| D5 | What each role (owner, manager, sales, warehouse) may see and do | Phase 1 (draft from the PRD is acceptable) | **Provisional draft implemented** (`backend/apps/businesses/permissions.py`, table in ARCHITECTURE); owner review pending |
| D6 | Inventory costing method | Needed before Phase 4 | **Decided 2026-10-06: FIFO.** Each purchase keeps its own unit cost and the oldest stock is used first when selling. Opening stock records a unit cost with every quantity. |
| D7 | Who approves discounts, refunds and stock adjustments, and limits | Phases 5–7 | **Discounts moot, 2026-10-07:** prices are not fixed, so any seller sets any price (no discount concept, no limit). Refunds and adjustments: open |
| D8a | Warranty terms stored on products and copied onto each sale | Phase 3 | **Decided 2026-10-06:** a period in months (0 = no warranty) plus free-text conditions per product |
| D8b | Warranty claim policies: who is eligible, outcomes, approvals | Phase 8 | Open |
| D9 | Pilot tablet model, scanning method, receipt/label printer | Phase 3 (scanning); Phase 5 (printing) | **Scanning method decided 2026-10-06: tablet camera.** The receipt is a PDF that the tablet prints or shares through its own dialogs; no printer is integrated. Tablet model and printer still open |
| D10 | Default language for new users; default document language | Phase 2 | Provisional: Russian (current prototype behavior); please confirm |
| D11 | Backup frequency, retention, acceptable data loss and recovery time | Phase 10 | Open |
| D12 | Android app identifier and distribution channel (Google Play or direct install) | Phase 5 (identifier); Phase 10 (channel) | Open |
| D13 | Stock-count policy for sales and receipts during a count | Phase 6 | **Provisional 2026-10-07:** sales and receipts continue during a count; moved lines are flagged and approval adjusts on top of the current stock |
| D14 | Fluent Russian and Turkmen reviewers for terminology | Arranged by Phase 5; review in Phase 10 | Open |
| D15 | Return window and refund eligibility | Phase 7 | Open |
| D16 | Email provider (any SMTP service) for password-recovery codes, tested from Turkmenistan | Before real staff use staging (Phase 2 owner step) | Open. Password recovery by emailed code was decided 2026-10-06 |

---

## Phase 0. Preparation

Goal: every change is checked automatically, Android builds work, and the first decisions are written down.

Before you start: none. (Step 0.2 needs one environment setting from you.)

- [ ] 0.1 Merge the onboarding branch (`claude/laughing-faraday-3dkwcb`) into `main` through a pull request. *Open (owner): this session works on the single assigned branch and opens no pull request unless asked.*
- [ ] 0.2 You: allow `dl.google.com` in the Claude Code cloud environment's network settings. Agent: extend `scripts/setup_claude_cloud.sh` with the Android steps from `scripts/setup_cloud.sh` and verify `flutter build apk --debug`. *Open (owner): the cloud environment still blocks `dl.google.com`. Android is built and verified in GitHub Actions instead.*
- [x] 0.3 GitHub Actions CI for `mobile/`: format check, analyze, tests, web build and debug APK, on every pull request and on `main`. You: in GitHub settings, require CI to pass before merging into `main`. **Done and green on every push; still owner:** require the CI checks in GitHub branch protection for `main`.
- [ ] 0.4 Decision kickoff: you answer D3, D5, D9 and D10 at least provisionally, and name candidate hosts for D2. The agent records the answers in the PRD/ARCHITECTURE and in the table above. *Recorded so far: D3, D6, D8a, D9, D16 decided; D5 and D10 provisional. D2 (host candidates) still open.*

Done when: CI is green on `main`; a debug APK is built by CI; the decisions table is updated.

## Phase 1. Backend foundation

Goal: a tested Django API that knows businesses, locations, staff, roles and sessions, with strict business isolation from day one.

Before you start: D1 (confirmed), D5 (draft).

- [x] 1.1 Scaffold `backend/`: pinned Python and dependencies in a lockfile, Django (current LTS), DRF, psycopg 3, settings from environment variables (a `.env.example` only, never real secrets), `/api/v1/health/`, a linter/formatter, a test runner and an OpenAPI schema. Set up PostgreSQL for the cloud session and for CI. Record the chosen tools and versions in ARCHITECTURE.md and replace "Planned Backend Commands" in AGENTS.md with the real commands.
- [x] 1.2 Shared building blocks: custom user model (create it before the first migration), UUID public IDs, UTC timestamps, structured error responses (code, parameters, field errors, request ID), request-ID middleware, an audit event record, and an idempotency record (operation key, scope, request fingerprint, stored result) for later stock commands.
- [x] 1.3 Businesses and access: business, location (store or warehouse), membership (user ↔ business with role) and permitted locations. Implement the D5 permission matrix in code. Reusable business-scoped queries and permission classes ensure a client-supplied business ID never grants access. Restrict Django admin to operators; it is used to create a pilot business.
- [x] 1.4 Sign-in: login, short-lived access tokens with rotating, revocable refresh tokens (a maintained library, no custom protocol), logout, a login rate limit, a `/me` endpoint returning memberships and permissions, and password change. Staff accounts are created by owners or managers; there is no public sign-up. **Password recovery (D16):** an emailed one-time code that expires in 30 minutes, works once, has limited attempts and is rate-limited, gives the same answer whether or not the account exists, and is written in the user's language. It is sent through any SMTP service chosen under D16.
- [x] 1.5 Backend CI job: lint, `check`, missing-migration check and tests against PostgreSQL.

Done when: CI is green; tests prove cross-business, wrong-role and wrong-location requests are denied, refresh tokens rotate and revoke, and login is rate-limited.

## Phase 2. App foundation and test server

Goal: the real app signs in to a real test server, reachable from Turkmenistan, in both languages. The demo stays available only as a separate demo build.

Before you start: D2 (provisional host), D10.

- [ ] 2.1 Staging server on the provisional host: container image, HTTPS, its own database and secrets, deployment from `main`, a health check, and a command to create a test business with sample staff. You: open the health address on the pilot tablet or phone **from the shop's own internet connection** and report the result. If it is slow or blocked, revisit D2 now. *Deployment files are done and the image builds in CI (`backend/Dockerfile`, `infra/`); deploying and testing from the shop's connection remain owner steps.*
- [x] 2.2 Flutter core (`mobile/lib/core/`, the structure in ARCHITECTURE "Proposed Additions"):
  - an API client with base URL set at build time, timeouts, token refresh and structured errors translated through ARB
  - secure session storage (Android Keystore)
  - a clear "no connection" state; stock-changing actions are disabled while offline, and any cached data is marked as possibly stale
  - a **pending-operation store and runner** implementing the restart-safe rule in "Every phase": saved before sending, cleared only on a definite server answer, resolved after a restart by asking the server for the outcome of the same key; "outcome unknown" operations are listed with *Retry (same key)* and *Discard*
- [x] 2.3 Sign-in screen, session restore, logout (clears private cached data), business and location selection with explicit handling of unsaved work, and navigation matching the user's permissions. Keep the existing `ChangeNotifier` approach and theme widgets (`mobile/lib/widgets/common.dart`).
- [x] 2.4 Demo separation: `DemoStore` and the demo banner exist only in a demo build flag (used for the web preview). Normal builds start at sign-in and can never show demo data as real.
- [x] 2.5 Administration screens: business profile, locations, staff accounts, roles and permitted locations, and interface/document language preferences.
- [x] 2.6 Tests: API client (mocked server), sign-in states (wrong password, expired session, server unreachable) and permission-based navigation, in both languages.

Done when: a staff member signs in to staging from the pilot tablet (or emulator) in Russian and Turkmen, sees only their business, and an owner can add a location and a staff member.

## Phase 3. Catalog and barcode lookup

Goal: the real product catalog, searchable by name, SKU or barcode, with at least one scanning method proven on the pilot tablet.

Before you start: D3 (decided), D8a (decided), D9 (camera decided; the pilot tablet is needed for the device test in step 3.3).

- [x] 3.1 Catalog API:
  - products, categories, brands and units (with quantity precision per unit)
  - several barcodes per product; barcodes and SKUs unique within a business
  - decimal selling price stated in TMT or USD (D3), with an owner/manager-entered USD→TMT exchange rate kept as history, and an optional default purchase cost in TMT (visible only to permitted roles)
  - warranty terms per product (D8a: months, 0 = none, plus free-text conditions), which Phase 5 copies onto each sale
  - minimum/target stock per product and location
  - archive instead of delete, and an audit entry for every change
  - search that handles Cyrillic and Turkmen letters without transliteration, with pagination
- [x] 3.2 Catalog screens on the API: list, search, detail, create, edit and archive. Include validation, empty and error states, long names, and financial fields per permission. Reuse the existing products screen layout (`mobile/lib/screens/products.dart`).
- [ ] 3.3 Barcode lookup with **one agreed method first: the tablet camera** (D9). A read-only lookup endpoint; a camera scan screen with torch, permission-denied and no-camera states; and manual entry as a fallback. A scan only fills a field: it never completes a sale or moves stock by itself. Typed entry does **not** satisfy the scanning acceptance check. USB/Bluetooth scanners are an optional later step once the owner chooses one and it is tested. Do not claim support for untested hardware. *Implemented (camera screen, torch, permission-denied and no-camera states, manual fallback, fake-scanner tests); awaiting the real-tablet check, see the checklist in HANDOFF.*

Done when: an owner manages the catalog in both languages, and a barcode scanned **with the pilot tablet's camera** finds the right product (a typed code alone does not count). HANDOFF records the device, Android version, barcode types, lighting and speed that were checked. Until that device check is done, step 3.3 stays unticked.

## Phase 4. Stock ledger, purchasing and receiving

Goal: real stock per location, changed only through recorded movements; purchase orders with partial deliveries.

Before you start: D6 (decided: FIFO), D7 (who approves adjustments; until answered, opening stock and adjustments are posted by owner or manager with a mandatory reason, as a provisional rule).

- [x] 4.1 Stock ledger:
  - unchangeable stock movements, and balances per product, location and condition (sellable, damaged, awaiting inspection, in transit)
  - FIFO cost layers (D6): every receipt or opening-stock line creates a layer with its own unit cost; selling or writing off uses the oldest layer first, so each movement records its exact cost
  - one inventory service as the only writer, using PostgreSQL row locks taken in a consistent order and a "no negative sellable stock" constraint
  - a reconciliation check comparing balances, movements and cost layers
- [x] 4.2 Opening stock and adjustments: initial quantities are entered **together with their unit cost** (otherwise historical stock value and profit would need rework), with a reason and the responsible user; stock write-offs and corrections need a mandatory reason. Both are protected by an operation key.
- [x] 4.3 Purchasing:
  - suppliers, and purchase orders through draft, ordered, partially received, received and cancelled
  - deliveries with the actual received quantities and remaining quantities
  - stock increases only on receipt; receipt cost kept for valuation
  - posting the same receipt twice is impossible (operation key)
- [x] 4.4 Screens: stock per location and movement history; opening stock and adjustments; suppliers; create and edit purchase orders; receive full or partial deliveries through the restart-safe pending-operation runner, keeping the same operation key after a timeout, crash or restart, with an "outcome unknown" banner.
- [x] 4.5 Tests: partial and repeated deliveries, duplicate and concurrent receipt requests, FIFO costs across several layers, two simultaneous outflows of the last unit, direct attempts to make a balance negative or edit a movement, the restart scenario (server committed, answer lost, app restarted, exactly one delivery), permissions, and a reconciliation difference of zero.

Done when: PRD flow 2 (purchase order → partial receipt → final receipt) works end to end and balances always match the ledger.

## Phase 5. Sales, payments and receipts (completes Stage 1)

Goal: real sales that cannot oversell or duplicate, with receipts and invoices in either language.

Before you start: D3, D4 (provisional), D7 (discount limits), D9 (printer, if any), D12 (app identifier), D14 (reviewers arranged).

- [x] 5.1 Sales API (done 2026-10-07, simplified after the owner's feedback):
  - optional customer records (walk-in sales need none)
  - a sale command protected by an operation key: it takes the goods out under locks and records **the unit price the seller set on every line** (any amount from zero up; the catalog price stays on the line for reference), with half-up 2-decimal totals
  - one payment label per sale: cash or card (no amounts, no change, no split payments, no debt)
  - sale numbering `S-000001` per business, gapless
  - snapshots of price charged, catalog price and **warranty terms** on each sale line, which Phase 8 depends on
  - stock decreased through the inventory service (FIFO cost per line), an audit entry, and the operation-status endpoint for unknown outcomes
- [x] 5.2 PostgreSQL concurrency tests: two tablets selling the last unit; twelve concurrent sales of five units never oversell and leave no gap in the numbers; eight concurrent copies of one sale give one sale; a retry with the same key returns the same sale; the same key with a different request is rejected.
- [x] 5.3 Sales screen on the API:
  - product search and scanning, and a cart that does not reserve stock; a price box on every line (starts with the catalog price, editable)
  - a short last step (lines, total, Cash or Card) and a single submission
  - after a timeout, crash or restart, the saved pending-operation record is resolved by asking the server for that key's outcome, or retried with the **same** key (tests: sale committed, answer lost, tablet restarted, exactly one sale; a 5xx before commit resent with the same key; the same in a real browser against the real backend)
  - success shown only after the server confirms; the cart is kept when the language changes
- [x] 5.4 Receipt: one simple 80 mm PDF made by the server with embedded DejaVu Sans fonts covering Russian and Turkmen (business name, address, phone, lines with the price charged, total, how it was paid; never a cost). Its language is the business's document-language setting. Downloads are permission-checked; the app hands the file to the device's print and share dialogs (`printing` package). *Not verified:* the print and share dialogs on a real tablet and any real printer (step 5.5). No invoice, tax or legal format: owner decision.
- [ ] 5.5 Stage 1 checkpoint: install a test build on the pilot tablet connected to staging and walk through PRD flows 1–3 in both languages, including printing or sharing a receipt. Fix the issues found and record the results in HANDOFF. **Owner step: needs the tablet and a staging server.**

Done when: the Stage 1 parts of the PRD acceptance criteria pass on the pilot tablet: no duplicate or oversold sales, stock matches movements, and both languages work.

## Phase 6. Transfers and stock counts

Goal: goods move between locations with a visible in-transit state; physical counts produce approved, explained adjustments.

Before you start: D7 (adjustment approval), D13.

- [x] 6.1 Transfers (done 2026-10-07; kept simple at the owner's request):
  - dispatch removes the goods from the source's sellable stock and puts them in transit at the destination with their FIFO cost layers; receipt moves what arrived into the destination's sellable stock; goods in transit cannot be sold
  - receiving less than was sent needs a reason and the missing goods are written off (one receipt per transfer; no repeated partial receipts); cancellation is an explicit step with a reason and sends everything back
  - states: in transit, received, received with some missing, cancelled (there is no separate draft: sending creates and dispatches in one step); sending needs access to the source, receiving access to the destination, cancelling access to the source
  - screens for all of this (stock page > Transfers); dispatch, receive and cancel use the same restart-safe pending-operation records
- [x] 6.2 Stock counts (done 2026-10-07):
  - a count per location, full or partial, with the system quantities noted when it starts as the baseline; entries by hand or by search/scan; products not on the list can be added
  - **D13 (provisional): sales and receipts continue during a count; nothing is frozen.** Lines whose sellable stock moved since the start are flagged; approval posts (counted - baseline) on top of the current stock, so what happened meanwhile is kept, and is refused (409) if the goods were sold meanwhile
  - a variance review, then approval by an owner or manager with an explanation, posted as adjustments through the ledger (**provisional D7**: only owner and manager approve; goods found that the system did not know about cost the latest layer's cost); count-entry and review screens for the tablet
- [x] 6.3 Tests: goods never available in two places (in-transit goods cannot be sold), two tablets sending the last unit, a transfer racing a sale, receive racing cancel, opposite transfers and a cancel racing a dispatch (which deadlocks without the per-business lock, proven by removing it), a count running while sales happen, approval permissions, and the restart scenario for dispatch, receive and approval (app and server).

Done when: PRD flows 4 (transfer) and 5 (count) work end to end on the tablet. (Verified through a real browser against the real backend; the tablet check is part of the pilot walkthrough, step 5.5.)

## Phase 7. Returns, refunds and reordering (completes Stage 2)

Goal: returns linked to the original sale, correct refunds and stock, and a reviewed reorder list.

Before you start: D7 (refund approval), D15.

- [ ] 7.1 Customer returns:
  - find the original sale; lock and enforce the remaining returnable quantities
  - record the reason and the condition of each item (sellable, damaged, awaiting inspection, plus a later inspection outcome); only sellable goods return to available stock
  - refund amount follows the original discounts and taxes, and the refund is recorded
  - approvals; exchanges as a linked return plus a new sale
- [ ] 7.2 Supplier returns, recorded separately and linked to the supplier and the delivery.
- [ ] 7.3 Reorder suggestions from the minimum and target levels, counting outstanding purchase orders. Staff review the list and create a draft purchase order (no automatic ordering).
- [ ] 7.4 Screens replacing the demo refund dialog, using the restart-safe pending-operation records (a refund must never be issued twice after a restart). Tests for partial returns, concurrent returns of the same sale, refund rounding, and the lost-answer restart scenario.
- [ ] 7.5 Stage 2 checkpoint on the pilot tablet; record the results in HANDOFF.

Done when: PRD flow 6 (return) works, and a reorder suggestion becomes a purchase order.

## Phase 8. Expenses, warranties, import and export

Goal: expense tracking with receipt photos, warranty claims based on what was sold, and safe CSV import and export.

Before you start: D8b (claim policies; the warranty terms themselves were captured in Phases 3 and 5); a list of expense categories.

- [ ] 8.1 Private file storage: local in development, a private storage service on the servers. Validate file type and size; downloads are permission-checked and short-lived.
- [ ] 8.2 Expenses: categories, decimal amount, date, location, description, optional receipt attachment, filters and summaries.
- [ ] 8.3 Warranties:
  - eligibility from the sale-line snapshot taken in Phase 5
  - claims with status history and an outcome (repair, replacement, refund or rejection)
  - replacements move stock through the ledger
  - screens replacing the sample cards
- [ ] 8.4 CSV import and export:
  - product import: upload, validation preview (errors and duplicate identifiers), then apply **all-or-nothing in one transaction**. Files above a row/size limit are rejected with a request to split them, so there are never half-applied or resumable batches. Importing never changes stock. Test: a failure on a late row, after earlier rows were already processed, leaves no change at all
  - catalog export keeping Russian and Turkmen text, with spreadsheet-formula protection and permission checks

Done when: PRD flow 7 (warranty) works; a valid catalog imports and an invalid one shows its errors without partial changes.

## Phase 9. Reports, dashboard and activity history

Goal: owners and managers see real, permission-filtered figures.

Before you start: D6 (final costing method).

- [ ] 9.1 Reports API: sales, stock movement, low stock, inventory value (per D6; estimates labelled), purchasing, returns and expenses, filtered by date and location. Revenue, gross profit, expenses and net profit stay separate measures. Financial fields are filtered on the server.
- [ ] 9.2 Report screens and CSV exports (protected and permission-checked).
- [ ] 9.3 Dashboard on the API (replacing the demo figures): sales totals, inventory value, low stock, reorder suggestions and recent activity, each according to permissions.
- [ ] 9.4 Read-only activity history with filters for owners and managers.
- [ ] 9.5 Performance: indexes and pagination, checked with realistic data volumes.

Done when: PRD flow 8 (owner review) works and figures match the underlying records in tests.

## Phase 10. Production and pilot (completes Stage 3)

Goal: a live system the pilot store can rely on, with proven recovery.

Before you start: D2 (final), D4 (final, legally confirmed), D11, D12, D14.

- [ ] 10.1 Production server, separate from staging: HTTPS, its own secrets and database, deployment with migration review, health checks, and monitoring and error reports with customer data removed.
- [ ] 10.2 Backups: scheduled database and file backups to separate protected storage with the D11 retention. **Restore drill** into a separate environment, checking representative records and attachments. Write a recovery runbook.
- [ ] 10.3 Security review: isolation and role tests, dependency and secret scans, release builds without debug or demo features.
- [ ] 10.4 Language review: fluent reviewers check every screen and document in Russian and Turkmen. Fix the findings and check glyphs in PDFs, large text sizes and TalkBack on the tablet.
- [ ] 10.5 Android release: final app identifier, release signing keys kept outside the repository, versioning, and the D12 distribution channel.
- [ ] 10.6 Pilot onboarding: create the business, locations and staff; import the catalog; enter opening stock; write a short user guide in Russian and Turkmen; agree how problems are reported.
- [ ] 10.7 Pilot run: measure the PRD success metrics and check every PRD acceptance criterion. Collect feedback into a follow-up list.

Done when: the PRD acceptance criteria pass at the pilot store and a backup restore has been verified.

## Phase 11. Apple release (Stage 4)

Goal: the same app on iPad and iPhone.

Before you start: an Apple Developer account, test iPad and iPhone, and a macOS machine or a cloud build service.

- [ ] 11.1 Generate the iOS project, set the bundle identifier and configure signing.
- [ ] 11.2 Apple checks: Keychain session storage; camera scanning with permission texts in both languages; iPad layouts including split view; iPhone compact layouts; VoiceOver; sharing and printing documents.
- [ ] 11.3 TestFlight beta, then the store release.

Done when: the PRD checks that passed on Android pass on iPad and iPhone.

## Main risks

| Risk | How the plan handles it |
| --- | --- |
| The server is slow or unreachable from Turkmenistan | Test from the pilot store's connection in Phase 2, before most of the work |
| A scanner or printer does not work | Choose the pilot hardware early (D9) and verify it in Phases 3 and 5 |
| Receipts or taxes do not meet local law | Provisional in Phase 5; confirmed with an accountant before the pilot (D4) |
| Poor Turkmen or Russian wording | Reviewers arranged by Phase 5; full review in Phase 10 |
| Data loss | Backups plus a real restore drill in Phase 10 |
| The cloud development environment cannot build Android | CI builds the APK (Phase 0) |
| A tablet closes after the server accepted an action but before the answer arrived, and a retry doubles it | Pending-operation records saved on the device and same-key retries ("Every phase" rule), tested per workflow |

Anything listed under "Out of Scope" in the PRD stays out unless the owner changes the PRD.

## Revision history

- 2026-10-06: first version.
- 2026-10-06, after Codex's review and the owner's answers:
  - restart-safe pending operations added to "Every phase" and to steps 2.2, 4.4, 5.3, 6.1 and 7.4;
  - costing decided early (D6: FIFO) and opening stock now carries unit costs (4.1, 4.2);
  - warranty terms defined before products and sales use them (D8a in Phase 3; claims remain D8b in Phase 8);
  - scanning narrowed to one agreed method, the tablet camera, with a real-device acceptance check (D9, step 3.3);
  - CSV import apply is all-or-nothing (step 8.4);
  - password recovery by emailed code added (step 1.4, D16);
  - agents pause only decision-dependent work ("How to use" item 5);
  - currency decision D3 recorded: TMT business currency, selling prices may be stated in TMT or USD.
- 2026-10-06, implementation: Phases 1-4 built autonomously while the owner was away. Assumptions made without the owner (listed for review in the session's final message and in HANDOFF): FIFO reading of D6; USD only for selling prices; opening stock once per product and location; over-receipt refused; receipt cost equals the order line cost; opening stock and adjustments by owner/manager only (provisional D7); PO numbers `PO-0001`.
- 2026-10-07, Phase 5 built after the owner's answers (discounts: anyone who can sell; tax: none for now; payments: mainly cash or card). Assumptions made without the owner, for review: receipt numbers `S-000001`; prices always come from the catalog on the server (no manual price override at the desk); one cart line per product; a completed sale is immutable (returns and corrections arrive in Phase 7); cost and profit are shown only to owner and manager; the cart reserves no stock, so another tablet may sell the goods first (the server then refuses and names the product); a sale of zero total (everything discounted) needs no payment; cash overpayment is change, card or transfer overpayment is refused; Turkmen document wording is a draft.
- 2026-10-07, Phase 5 simplified after the owner's review: prices are not fixed (the seller sets every price), it is an ERP and not a cash register (no cash received, change, split payments or bank transfer; only a Cash/Card label), one plain receipt (no invoice, no tax, no legal format, no language chooser), selling is in-store and online only, customers stay optional. The earlier discount, price-changed, USD-conversion-at-sale and payment-amount code was removed (migrations `sales/0003`, `businesses/0005`). Assumptions to review: the receipt language is the business setting; address and phone stay on the receipt; `S-000001` numbering stays; the Turkmen receipt wording is a draft.
- 2026-10-07, Phase 6 built (transfers and stock counts) with the owner's "keep it simple" in mind. Assumptions made without the owner, for review: no separate draft state for transfers (sending dispatches at once); one receipt per transfer, anything missing is written off with a reason; the sender cancels (the destination cannot); sales and receipts are not frozen during a count (D13); only owner and manager approve a count (D7) and everyone with count access sees the system quantities while counting; surplus found in a count is costed at the latest layer's cost; one advisory lock per business serialises transfer and approval postings.
