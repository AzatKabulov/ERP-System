# Production readiness — 2026-10-27

The real application is implemented through Phase 9. This review fixes confirmed
defects and adds repeatable acceptance checks; it does **not** certify a production
deployment or physical hardware. The owner's priority is Android tablets, with
the same workflows usable on laptop and phone browsers. A tablet model and shop
size have not yet been selected.

## Defects fixed

| Finding | Result |
| --- | --- |
| Sales barcode lookup summed stock across permitted locations but labelled it “in stock here” | Lookup now passes the selected location, matching text search. A two-location regression checks 10 here versus 100 in total. |
| A delayed stock lookup could add to the cart after switching location | A location generation invalidates old additions and searches, including switching away and back. The current permission is checked before adding. |
| Dashboard comparisons and report presets used the device's date; the trend and headline could cover different locations | The server resolves date presets in the business timezone for reports, exports and activity. Chart days use the returned period. The trend matches the headline's permitted locations, with an all-locations label when applicable. |
| Small, unnamed quantity controls and sales results without a button role | Quantity buttons have actual 48 × 48 touch areas and localized accessible labels; remove/price controls are enlarged. Search results expose their button role. Existing styling is retained. |
| Decorative arrivals consumed compact-tablet navigation work | Below 1000 pixels, data/charts show immediately using the existing phone path. The 820 × 1180 control measured 30.56% less median CPU work and longest tasks 211 → 55 ms. Wider behavior is retained; landscape timing varied. [Protocol and controls](performance/2026-10-27/README.md). |
| Vulnerable locked REST/image libraries | Only Django REST Framework (3.18.1 → 3.18.3) and Pillow (12.3.0 → 13.0.0) were updated. Image opening explicitly permits JPEG, PNG and WebP. The updated lockfile audit reports no known vulnerabilities. This is not a penetration test. |
| Backup/restore selected the first `*_privatefiles` volume on a shared Docker host | Resolve the volume from this Compose project's actual API mount. A missing mount refuses backup/restore before database replacement. |
| Backup files inherited potentially public permissions; corrupt archives were discovered too late | New backups use owner-only permissions. Restore checks gzip/tar integrity before stopping the API or replacing records. |
| A photo could be replaced between the database and private-files snapshots | Backup serializes competing jobs, briefly stops this project's running API, validates both temporary archives and publishes them only after success. Cleanup restarts an API that was running even after a failed dump/archive; an already stopped API stays stopped. This is a scheduled maintenance pause. |
| Deployment health checks disabled TLS verification | Checks retain certificate verification and bound connection/request timeouts. |
| Documentation described the backend as unimplemented; the old full browser test still used removed Purchasing screens | Current architecture status is corrected. A separate current-workflow browser check avoids the removed screens; the old test remains explicitly historical. |

## Evidence

All stock-changing checks use a new disposable PostgreSQL cluster and private-file
directory. The owner's running shop is not reset, seeded, or used for load tests.
The local embedded PostgreSQL is version 18.4; deployment and normal CI target 16.
The CI suite must also pass on its PostgreSQL 16 service before release.

| Check | Evidence |
| --- | --- |
| Backend suite after final fixes | 785 tests pass, including concurrent stock/sales/returns/transfers/counts, role and business isolation, retry safety, uploads, CSV/PDF, report-volume tests and business-day preset boundaries. |
| Flutter | 458 tests pass, with clean analysis/formatting and a successful release web build. Covers decimal money, pending operations, scanning, both languages, large text and responsive layouts, including 768-wide portrait and short landscape tablets, immediate compact-tablet data and retained wide-tablet animation. |
| Store simulation over real HTTP | Receive 50 at cost 60.25; sell 3 at the seller's chosen 110.25; return 1; transfer 10; count remaining store stock as 37; resolve a warranty repair; upload/download a private expense receipt; expense 25.50. Stock reconciles. Gross profit 100.00 and operating result 74.50 match independent arithmetic. |
| Failure/input checks | Malformed filters/dates, negative/zero/nonfinite/fractional piece quantities, unauthenticated reads, another business scope, unauthorized costs/files/reports and edits to a finalized sale are refused. Rejected requests leave stock unchanged. |
| Competing sales | 40 requests, 12 active at a time, compete for 37 units: 37 sales, 3 stock conflicts, no 500, no oversell. Eight simultaneous retries of one key produce one sale. |
| Mixed read load | 120 product/stock/dashboard/report requests, concurrency 12: all succeed. One final Chromium-run sample: p50 46.67 ms, p95 70.64 ms, max 83.42 ms. This small local sample is not production capacity or a long soak test. |
| Current Chromium and WebKit UI | Each engine passes 390 × 844 phone, 768 × 1024 tablet portrait, 1024 × 768 tablet landscape and 1440 × 900 laptop: actual sale, exact price/quantity, confirmed stock, simulated 503/retry, all current modules and Russian/Turkmen. Device timezone is deliberately Pacific/Kiritimati against the Ashgabat shop. No unexpected browser errors; WebKit's exact `WEBGL_polygon_mode` renderer warning is recorded separately. |
| Database/file restore drill | Stop the disposable HTTP server, dump its database, restore into a **second** database, compare every public table's count and content digest (57 tables), restore the private-file directory and compare SHA-256 of every file. Run stock reconciliation again against the restored database. One private receipt file is included. |
| Deployment safety | 11 fake-Docker regressions cover project-specific mounts, corrupt/missing archives, private permissions, snapshot quiescence, concurrent backup exclusion, failure cleanup/restart, an already stopped API and verified TLS. ShellCheck passes. This is not a real Docker restore drill. |

The scanner's separate live-camera lifecycle and HTTP photo-decoding regressions
are documented in HANDOFF.md. A browser build or simulated camera does not prove
focus, permissions, native photo capture, printing or sharing on a physical tablet.

## Release blockers and next actions

| Priority | What remains | Acceptance evidence |
| --- | --- | --- |
| P0 | Separate staging/production host, real domain and verified HTTPS; local role picker and HTTP testing build stay out of production | Production configuration review, authenticated workflow through the deployed proxy, certificate/header test and successful `check --deploy`. No development server for real shop data. |
| P0 | Scheduled protected off-machine backups; agreed retention, recovery time and acceptable data loss | Restore the **actual deployment's** database and private files on a second host, then check records, downloads and reconciliation. The local drill here proves the app data can restore, not the Docker scripts, remote storage or schedule. |
| P0 | Validate coordinated backup on the real deployment | The script now quiesces this project's API across both snapshots. Prove graceful shutdown, concurrent upload/replace handling, startup after a failed dump and successful restore with actual Docker volumes. Verify the maintenance pause fits shop operations; there is no zero-downtime backup claim. |
| P0 | Physical Android tablet acceptance | Receive, manually enter, scan repeatedly, deny/reallow camera, rotate, use the keyboard, background/resume, sell, return, transfer/count, print/share and recover a lost response on the selected tablet and shop Wi-Fi. |
| P0 | Real-store pilot and language review | Owner/warehouse/sales staff complete a store day in Russian and Turkmen; a fluent reviewer checks provisional Turkmen and printed documents. Pilot opening stock reconciles. |
| P1 | Recovery email, monitoring, alerting and operational ownership | Deliver a real reset code; prove expiry/throttling; alert on API/DB failures, disk space, failed backups and reconciliation differences without logging customer payloads/tokens. |
| P1 | Release signing and distribution | Owner's signing key, final identifier, signed Android build installed on the tablet, upgrade verified. Local Android SDK/hardware is unavailable; CI APK compilation is separate evidence. Native iOS still needs host/signing/TestFlight setup. |
| P1 | Representative size, network and long-session performance | Repeat catalog/search/scanning/navigation under the chosen tablet, shop network, realistic catalog and staff count; measure cold load, interaction delays, memory after repeated scans/navigation and tail API latency. Synthetic desktop CPU throttling is not device FPS. |
| P2 | Simplify legacy server-only Purchasing paths | PLAN 9.10 remains open. Do not remove historical records or migrate financial relations as an incidental cleanup. Current app tests avoid removed Purchasing UI. |

Avoid adding unrelated ERP features before these gates pass. Current stock,
receiving, sales and recovery workflows matter more than expanding the menu.

## Reproduce

From the repository root, using Python 3.13 and the pinned lockfile:

```sh
uv run --project backend --with pixeltable-pgserver==0.6.0 \
  python scripts/qa/store_readiness.py --output /tmp/store-readiness.json
uv run --project backend python scripts/qa/test_deploy_safety.py -v
```

The runner always creates a new temporary cluster; it accepts no existing database
or business identifier. Credentials are random and never written to its result.
Do not run test suites concurrently (docs/START_HERE.md).

To include browser acceptance, first build the release web app, install Playwright
and its test browser, set `PLAYWRIGHT_MODULE` and `CHROMIUM_PATH`, and pass
`--browser-script scripts/e2e/store_day.js --node /path/to/node`. `E2E_OUT` chooses
a local screenshot directory. `E2E_BROWSER=webkit` selects installed Playwright
WebKit; this is Safari-engine coverage, not a physical iPhone test. Current
Chromium results/screenshots are local under `/tmp/erp-readiness-chromium`;
WebKit equivalents are under `/tmp/erp-readiness-webkit`.

The backend CI job now also runs the disposable store/load/restore check and the
fake-Docker safety tests. CI results apply only after that commit's run completes.

Security and recovery criteria follow the [Django deployment checklist](https://docs.djangoproject.com/en/5.2/howto/deployment/checklist/)
and [PostgreSQL backup documentation](https://www.postgresql.org/docs/16/backup.html).
Dependency changes address the security releases documented by
[Django REST Framework](https://www.django-rest-framework.org/community/release-notes/#3182)
and [Pillow](https://pillow.readthedocs.io/en/stable/releasenotes/13.0.0.html).
