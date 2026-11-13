# Usability and security review — 2026-11-11

Local work on `codex/usability-and-security`, based on `a6118a7` (the fetched main).
No commit, push, deployment, shared database modification or dependency upgrade.
Pre-existing local Android helpers and the existing HANDOFF changes were preserved.

## Changes

| Request / finding | Result |
| --- | --- |
| Gradient disappears during navigation | Flutter's `FadeForwardsPageTransitionsBuilder` uses `ColorScheme.surface` behind fading routes. It now uses a transparent backdrop, exposing the persistent ambient gradient. Native iOS keeps Cupertino gestures. Raster tests sample intermediate push/pop frames in both schemes; the opaque ambient canvas of pushed pages is retained. |
| Compact tablet pages remain expensive to draw | Shared glass below 1100 logical pixels keeps its veil, rim and shadow without backdrop blur. Wide glass retains blur. This applies across store and platform pages. Tests explicitly cover 768, 820 and 1024 widths and the wide path. This removes the filter workload; it is not a measured device FPS claim. |
| Too many boxes on the platform overview | Replace ten individual metric boxes with a client-state ring, tappable status rows and one quiet income/new-clients panel. Keep client filters, payments and attention actions. Trial and expiring counts overlap active clients: the ring excludes those extra counts and the visible explanation prevents adding them twice. Attention clients use a vertical list on phones, without a fixed-height horizontal card that clips larger text. |
| Forms are difficult to scan | Shared fields reserve a 52-pixel minimum and allow multiline errors/help. Product, expense, transfer and return forms use the reusable flat `FormSection`; product details, prices and additional information are grouped separately. Receiving puts the optional photo above the name and uses one field column in narrow dialogs rather than squeezing three money fields beside each other. Existing validation, permissions, optional prices and warranty/expiry behavior are retained. |
| New client can lose entered details or a pending result | Dirty forms ask before leaving; cancelling preserves the text. Back is blocked while creation is in flight, and leaving the result still returns the created client to the list. |
| First-use instructions | Shorter RU/TK instructions explain finding a product, optional barcode/photo, scanning versus adding to the cart, checking price/quantity, and manual receiving. Delayed tips do not open over a pushed form. A long tip can scroll within its available space. Skip, Back, Next and replay remain. |
| Navigation terminology | The shop module is **Касса / Kassa**. Reports, recorded sales, return references and stock-movement names retain their accounting meanings. |
| Password-free role selection in production | The test-login view refuses it outside `DJANGO_ENV=development`, even if the public test flag was accidentally enabled. A deployment security check reports `erp.E001` for this combination. Explicit local/development testing remains available. |
| Replacing an operator authenticator leaves old API sessions alive | Key replacement and revocation occur in a transaction. Increment the session version and blacklist refresh tokens so old access and refresh tokens stop working immediately. A regression checks both requests are refused. |

## Executed verification

| Check | Result |
| --- | --- |
| Full Flutter suite | **620 passed**. Includes intermediate-frame gradient pixels, tablet filter policy, client-form cancellation, receiving photo/name geometry and existing role, barcode, retry, form, localization and layout checks. |
| Flutter analysis / formatting | Clean; 212 files checked without formatting changes. |
| Full backend suite | **950 passed**, using a fresh, disposable PostgreSQL cluster. Includes cross-business/role denial, stock races, replay safety, private files, platform access and the new security regressions. |
| Backend lint / formatting | Clean using `backend/pyproject.toml`. |
| Release web / Android debug APK | Built; Android APK signature verified. Native hardware is not acceptance-tested by compilation. |
| Real HTTP store simulation | Receive 50 at 60.25, sell 3 at 110.25, return 1, transfer 10, count remaining store stock as 37, resolve a warranty, upload/download an expense receipt and post expense 25.50. FIFO profit and operating result reconcile. Malformed inputs, unauthorized costs/files/reports and finalized-record edits are rejected without stock changes. |
| Concurrency | 40 competing sale requests for 37 units: 37 successes, 3 stock conflicts, no oversell. Eight concurrent retries create one sale. All 120 mixed reads at concurrency 12 succeed. Local read p50 48.11 ms, p95 78.40 ms; these are fixture timings, not deployed capacity or phone responsiveness measurements. |
| Store browser acceptance | Chromium, 390×844, 768×1024, 1024×768 and 1440×900. Actual sales, exact totals/remaining stock, injected read failure and retry, all main modules and RU/TK. Device timezone differs from the shop. |
| Platform browser acceptance | Chromium, 390/820/1440 widths, light and dark. Overview loads and document width fits. Real screenshots of the empty state were inspected; populated counts/filter actions are covered by widget fixtures. |
| Restore drill | Restore the disposable database into a second database: all 66 public table digests/counts match; private-file hashes and stock reconciliation match. No active shop was restored or reset. |
| Dependency audit | `pip-audit`: 24 locked backend packages, no known advisories at the time of this run. No automatic dependency changes. |
| Static security scan | Bandit over backend applications/configuration: one low-severity hardcoded password in the test-fixture helper `apps/common/testing.py`, reviewed as test data. No production secret was substituted for it or exposed. |
| Secret signatures | No private-key/GitHub-token/AWS-access-key signature matches in tracked working-tree text or added lines across 175 locally available commits. This limited pattern scan is not proof that every possible secret format is absent. |

The scratch database is PostgreSQL 18.4; deployment/CI target PostgreSQL 16.
CI was not triggered by this local work. The existing store/browser acceptance
runner remains reproducible; `scripts/e2e/usability.js` adds the platform review
and requires the runner's explicit disposable-environment marker.

Summary evidence: [qa/usability-2026-11-11/results.json](qa/usability-2026-11-11/results.json).
Full logs and screenshots are local under `/tmp/erp-usability-*`; they contain
synthetic shop data, not exported customer records. The latest local APK is
`local-data/android-builds/erp-2026-11-11-usability-debug.apk` with a checksum beside it.

## Before production acceptance

- These changes are local. The publicly reachable test server was previously
  observed advertising password-free shop and platform roles. This work does
  **not** disable its running configuration. Before real customer data, deploy
  with `ERP_PUBLIC_TEST_LOGIN=false` and revoke existing test-issued sessions;
  old tokens cannot be retroactively identified by the new guard alone.
- This is an engineering review, not an independent penetration test. The
  backend advisory scan does not audit Android native dependencies, the host,
  network/proxy configuration or every Flutter package. Operational production
  blockers remain in [PRODUCTION_READINESS.md](PRODUCTION_READINESS.md).
- Real Android tablet/phone smoothness, camera permissions/focus, barcode
  decoding, printing/sharing and iPhone back gestures still need device tests.
  Debug APK/emulator or browser timings do not establish 60 FPS.
- A fluent Turkmen reviewer and actual shop staff still need to confirm wording
  and first-use understanding. Simplified instructions are not user-study evidence.
- This pass changes shared behavior across the application and reorganizes the
  named forms. It does not claim every individual dialog has been independently
  redesigned or every possible store/network failure has been exhausted.

Audit references: [Django deployment checklist](https://docs.djangoproject.com/en/dev/howto/deployment/checklist/),
[PyPA pip-audit](https://github.com/pypa/pip-audit).
