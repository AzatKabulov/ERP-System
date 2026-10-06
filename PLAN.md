# Delivery Plan

Status: approved roadmap, 2026-10-06. Scope is defined in [docs/PRD.md](docs/PRD.md), the technical design in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md), the visual rules in [docs/DESIGN_SYSTEM.md](docs/DESIGN_SYSTEM.md) and the development rules in [AGENTS.md](AGENTS.md). This plan only orders the work. When it conflicts with those documents, they win; update this plan.

Starting point: a bilingual Flutter interface prototype that runs on demonstration data only (see [HANDOFF.md](HANDOFF.md)).

## How to use this plan

1. Pick the first phase that is not finished. Check its **Before you start** list. Those are your decisions, and the phase cannot be finished without them.
2. Start a new Claude Code or Codex session on this repository and paste:
   > Implement Phase N of PLAN.md (or only step N.M). First read AGENTS.md, HANDOFF.md and PLAN.md. Follow the "Every phase" rules. Run all checks, update HANDOFF.md and tick the finished boxes in PLAN.md, then commit, push and open a pull request.
3. Large phases can be handed over **one numbered step at a time**. Every step ends in a working, mergeable state.
4. Merge the pull request when the automatic checks (CI) are green and you are happy with the summary. Then continue.
5. If a phase reveals a new decision, the agent adds it to the decision list below and stops at that point; it does not guess.

## Every phase (definition of done)

- New behavior has tests: backend tests include permission and cross-business denial; Flutter has unit and widget tests. All existing tests pass and CI is green.
- Every new screen text exists in Russian and Turkmen ARB files. Provisional translations are marked for review.
- Screens show loading, empty, error and success states. Nothing shows success before the server confirms it.
- Money uses decimal arithmetic. Stock changes only through the inventory service, and stock-changing requests carry an operation key so a retry never duplicates them.
- Permissions and business isolation are enforced on the server, not only hidden in the app.
- Docs stay current: ARCHITECTURE status, AGENTS commands, README, HANDOFF and the PLAN checkboxes.
- No secrets, keys or generated builds are committed.

## Phase overview

| Phase | Result | PRD stage | Size |
| --- | --- | --- | --- |
| 0. Preparation | CI on every pull request, Android builds, first decisions recorded | — | M |
| 1. Backend foundation | Django API with businesses, locations, staff roles, sign-in, audit | 1 | XL |
| 2. App foundation and test server | App signs in to a real test server from Turkmenistan; administration screens | 1 | XL |
| 3. Catalog and barcode lookup | Real product catalog; scanning works on the pilot tablet | 1 | L |
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
| D3 | Business currency, decimal places, rounding | Phase 3 | Open |
| D4 | Receipt/invoice format, tax rules, document numbering (confirm with a local accountant) | Phase 5 (provisional); Phase 10 (final) | Open |
| D5 | What each role (owner, manager, sales, warehouse) may see and do | Phase 1 (draft from the PRD is acceptable) | Open |
| D6 | Inventory costing method (for example weighted average) | Phase 4 (data captured); Phase 9 (final) | Open |
| D7 | Who approves discounts, refunds and stock adjustments, and limits | Phases 5–7 | Open |
| D8 | Warranty policies | Phase 8 | Open |
| D9 | Pilot tablet model, scanning method, receipt/label printer | Phase 3 (scanning); Phase 5 (printing) | Open |
| D10 | Default language for new users; default document language | Phase 2 | Open |
| D11 | Backup frequency, retention, acceptable data loss and recovery time | Phase 10 | Open |
| D12 | Android app identifier and distribution channel (Google Play or direct install) | Phase 5 (identifier); Phase 10 (channel) | Open |
| D13 | Stock-count policy for sales and receipts during a count | Phase 6 | Open |
| D14 | Fluent Russian and Turkmen reviewers for terminology | Arranged by Phase 5; review in Phase 10 | Open |
| D15 | Return window and refund eligibility | Phase 7 | Open |

---

## Phase 0. Preparation

Goal: every change is checked automatically, Android builds work, and the first decisions are written down.

Before you start: none. (Step 0.2 needs one environment setting from you.)

- [ ] 0.1 Merge the onboarding branch (`claude/laughing-faraday-3dkwcb`) into `main` through a pull request.
- [ ] 0.2 You: allow `dl.google.com` in the Claude Code cloud environment's network settings. Agent: extend `scripts/setup_claude_cloud.sh` with the Android steps from `scripts/setup_cloud.sh` and verify `flutter build apk --debug`.
- [ ] 0.3 GitHub Actions CI for `mobile/`: format check, analyze, tests, web build and debug APK, on every pull request and on `main`. You: in GitHub settings, require CI to pass before merging into `main`.
- [ ] 0.4 Decision kickoff: you answer D3, D5, D9 and D10 at least provisionally, and name candidate hosts for D2. The agent records the answers in the PRD/ARCHITECTURE and in the table above.

Done when: CI is green on `main`; a debug APK is built by CI; the decisions table is updated.

## Phase 1. Backend foundation

Goal: a tested Django API that knows businesses, locations, staff, roles and sessions, with strict business isolation from day one.

Before you start: D1 (confirmed), D5 (draft).

- [ ] 1.1 Scaffold `backend/`: pinned Python and dependencies in a lockfile, Django (current LTS), DRF, psycopg 3, settings from environment variables (a `.env.example` only, never real secrets), `/api/v1/health/`, a linter/formatter, a test runner and an OpenAPI schema. Set up PostgreSQL for the cloud session and for CI. Record the chosen tools and versions in ARCHITECTURE.md and replace "Planned Backend Commands" in AGENTS.md with the real commands.
- [ ] 1.2 Shared building blocks: custom user model (create it before the first migration), UUID public IDs, UTC timestamps, structured error responses (code, parameters, field errors, request ID), request-ID middleware, an audit event record, and an idempotency record (operation key, scope, request fingerprint, stored result) for later stock commands.
- [ ] 1.3 Businesses and access: business, location (store or warehouse), membership (user ↔ business with role) and permitted locations. Implement the D5 permission matrix in code. Reusable business-scoped queries and permission classes ensure a client-supplied business ID never grants access. Restrict Django admin to operators; it is used to create a pilot business.
- [ ] 1.4 Sign-in: login, short-lived access tokens with rotating, revocable refresh tokens (a maintained library, no custom protocol), logout, a login rate limit, a `/me` endpoint returning memberships and permissions, and password change. Staff accounts are created by owners or managers; there is no public sign-up.
- [ ] 1.5 Backend CI job: lint, `check`, missing-migration check and tests against PostgreSQL.

Done when: CI is green; tests prove cross-business, wrong-role and wrong-location requests are denied, refresh tokens rotate and revoke, and login is rate-limited.

## Phase 2. App foundation and test server

Goal: the real app signs in to a real test server, reachable from Turkmenistan, in both languages. The demo stays available only as a separate demo build.

Before you start: D2 (provisional host), D10.

- [ ] 2.1 Staging server on the provisional host: container image, HTTPS, its own database and secrets, deployment from `main`, a health check, and a command to create a test business with sample staff. You: open the health address on the pilot tablet or phone **from the shop's own internet connection** and report the result. If it is slow or blocked, revisit D2 now.
- [ ] 2.2 Flutter core (`mobile/lib/core/`, the structure in ARCHITECTURE "Proposed Additions"):
  - an API client with base URL set at build time, timeouts, token refresh and structured errors translated through ARB
  - secure session storage (Android Keystore)
  - a clear "no connection" state; stock-changing actions are disabled while offline, and any cached data is marked as possibly stale
- [ ] 2.3 Sign-in screen, session restore, logout (clears private cached data), business and location selection with explicit handling of unsaved work, and navigation matching the user's permissions. Keep the existing `ChangeNotifier` approach and theme widgets (`mobile/lib/widgets/common.dart`).
- [ ] 2.4 Demo separation: `DemoStore` and the demo banner exist only in a demo build flag (used for the web preview). Normal builds start at sign-in and can never show demo data as real.
- [ ] 2.5 Administration screens: business profile, locations, staff accounts, roles and permitted locations, and interface/document language preferences.
- [ ] 2.6 Tests: API client (mocked server), sign-in states (wrong password, expired session, server unreachable) and permission-based navigation, in both languages.

Done when: a staff member signs in to staging from the pilot tablet (or emulator) in Russian and Turkmen, sees only their business, and an owner can add a location and a staff member.

## Phase 3. Catalog and barcode lookup

Goal: the real product catalog, searchable by name, SKU or barcode, with at least one scanning method proven on the pilot tablet.

Before you start: D3; D9 (tablet and scanning method).

- [ ] 3.1 Catalog API:
  - products, categories, brands and units (with quantity precision per unit)
  - several barcodes per product; barcodes and SKUs unique within a business
  - decimal selling price and purchase cost (cost visible only to permitted roles), default warranty terms, and minimum/target stock per product and location
  - archive instead of delete, and an audit entry for every change
  - search that handles Cyrillic and Turkmen letters without transliteration, with pagination
- [ ] 3.2 Catalog screens on the API: list, search, detail, create, edit and archive. Include validation, empty and error states, long names, and financial fields per permission. Reuse the existing products screen layout (`mobile/lib/screens/products.dart`).
- [ ] 3.3 Barcode lookup: an API endpoint; manual entry fallback (reuse the existing barcode dialog); keyboard-type (USB/Bluetooth) scanner input with deliberate focus, so that a scan never completes a sale or moves stock by itself; and camera scanning (choose and validate a plugin on the D9 tablet). Do not claim support for untested hardware.

Done when: an owner manages the catalog in both languages, and a barcode scanned or typed on the pilot tablet finds the right product. HANDOFF records which scanning methods were verified on which device.

## Phase 4. Stock ledger, purchasing and receiving

Goal: real stock per location, changed only through recorded movements; purchase orders with partial deliveries.

Before you start: D6 (at least the data to keep), D7 (who approves opening stock and adjustments).

- [ ] 4.1 Stock ledger:
  - unchangeable stock movements, and balances per product, location and condition (sellable, damaged, awaiting inspection, in transit)
  - one inventory service as the only writer, using PostgreSQL row locks taken in a consistent order and a "no negative sellable stock" constraint
  - a reconciliation check comparing balances with the ledger
- [ ] 4.2 Opening stock: initial quantities entered as approved adjustments with a reason and the responsible user (needed to onboard a store).
- [ ] 4.3 Purchasing:
  - suppliers, and purchase orders through draft, ordered, partially received, received and cancelled
  - deliveries with the actual received quantities and remaining quantities
  - stock increases only on receipt; receipt cost kept for valuation
  - posting the same receipt twice is impossible (operation key)
- [ ] 4.4 Screens: stock per location and movement history; suppliers; create and edit purchase orders; receive full or partial deliveries, keeping the same operation key when retrying after a timeout.
- [ ] 4.5 Tests: partial and repeated deliveries, duplicate and concurrent receipt requests, permissions, and a reconciliation difference of zero.

Done when: PRD flow 2 (purchase order → partial receipt → final receipt) works end to end and balances always match the ledger.

## Phase 5. Sales, payments and receipts (completes Stage 1)

Goal: real sales that cannot oversell or duplicate, with receipts and invoices in either language.

Before you start: D3, D4 (provisional), D7 (discount limits), D9 (printer, if any), D12 (app identifier), D14 (reviewers arranged).

- [ ] 5.1 Sales API:
  - optional customer records (walk-in sales need none)
  - a sale command protected by an operation key: it rechecks stock and prices under locks, applies discount permissions, and calculates final decimal totals with the D3 rounding and D4 tax settings
  - recorded payments (method and amount; no payment gateway), and sale numbering per D4
  - snapshots of price, discount, tax and **warranty terms** on each sale line, which Phase 8 depends on
  - stock decreased through the inventory service, an audit entry, and an operation-status endpoint for unknown outcomes
- [ ] 5.2 PostgreSQL concurrency tests: two tablets selling the last unit; a retry with the same key returns the same sale; the same key with a different request is rejected.
- [ ] 5.3 Sales screen on the API:
  - product search and scanning, and a cart that does not reserve stock
  - confirmation before checkout, and a single submission
  - after a timeout, query the status or retry with the **same** key
  - success shown only after the server confirms; the cart is kept when the language changes (an existing test covers this)
- [ ] 5.4 Receipts and invoices: generated on the server as PDFs with embedded fonts covering Russian and Turkmen, with business details. Document language is chosen separately from interface language. Downloads are permission-checked, and the file can be shared or printed through the device. A dedicated printer integration happens only once the D9 printer is chosen and tested.
- [ ] 5.5 Stage 1 checkpoint: install a test build on the pilot tablet connected to staging and walk through PRD flows 1–3 in both languages. Fix the issues found and record the results in HANDOFF.

Done when: the Stage 1 parts of the PRD acceptance criteria pass on the pilot tablet: no duplicate or oversold sales, stock matches movements, and both languages work.

## Phase 6. Transfers and stock counts

Goal: goods move between locations with a visible in-transit state; physical counts produce approved, explained adjustments.

Before you start: D7 (adjustment approval), D13.

- [ ] 6.1 Transfers:
  - dispatch removes goods from the source's available stock and puts them in transit; receipt adds the actually received quantity at the destination
  - discrepancies need a reason, and cancellation is an explicit step
  - states run draft → dispatched → received or partially received or cancelled, with location permissions
  - screens for all of this, replacing the demo's instant transfer
- [ ] 6.2 Stock counts:
  - a count per location (full or partial) with a recorded baseline; entries by scan or hand
  - detection of sales or receipts during the count, handled per D13
  - a variance review, then an adjustment submitted for approval and posted through the ledger
  - count-entry and review screens designed for the tablet
- [ ] 6.3 Tests: goods never available in two places at once, a count running while sales happen, and approval permissions.

Done when: PRD flows 4 (transfer) and 5 (count) work end to end on the tablet.

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
- [ ] 7.4 Screens replacing the demo refund dialog. Tests for partial returns, concurrent returns of the same sale, and refund rounding.
- [ ] 7.5 Stage 2 checkpoint on the pilot tablet; record the results in HANDOFF.

Done when: PRD flow 6 (return) works, and a reorder suggestion becomes a purchase order.

## Phase 8. Expenses, warranties, import and export

Goal: expense tracking with receipt photos, warranty claims based on what was sold, and safe CSV import and export.

Before you start: D8; a list of expense categories.

- [ ] 8.1 Private file storage: local in development, a private storage service on the servers. Validate file type and size; downloads are permission-checked and short-lived.
- [ ] 8.2 Expenses: categories, decimal amount, date, location, description, optional receipt attachment, filters and summaries.
- [ ] 8.3 Warranties:
  - eligibility from the sale-line snapshot taken in Phase 5
  - claims with status history and an outcome (repair, replacement, refund or rejection)
  - replacements move stock through the ledger
  - screens replacing the sample cards
- [ ] 8.4 CSV import and export:
  - product import: upload, validation preview (errors and duplicate identifiers), then apply in transactional batches that can be safely retried; importing never changes stock
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

Anything listed under "Out of Scope" in the PRD stays out unless the owner changes the PRD.
