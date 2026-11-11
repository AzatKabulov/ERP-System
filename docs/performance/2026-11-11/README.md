# Startup, skeleton and back-navigation review

Owner request received 2026-11-10; final verification 2026-11-11. No deployment.
The task began at Azat's `5a465d9` (phone glass optimization), with the earlier
catalog/photo improvements already merged. Azat's later `3363987` and `f67b76c`
documentation commits were fast-forwarded into this checkout before finalizing.
The baseline application's source is identical across these three commits.

## Findings and request map

Before: browser/engine startup → read refresh token → refresh POST → `/me/` GET
→ mount workspace → dashboard GET → first figures → trend GET. The trend's
`late` initializer did not run until the dashboard's builder mounted, so a
seemingly independent future was actually sequential. There was no persisted
access token or home snapshot. Warm reload always paid for refresh, even when
the previous access token was still usable.

After: browser/engine startup → local snapshot/credentials → locked identity
shell; usable saved access → `/me/` and a permitted dashboard prefetch together
→ confirmed workspace with recent cached figures → background fresh figures.
The trend starts when the confirmed dashboard mounts, without waiting for its
figures. With no usable access token, refresh remains a necessary dependency.
Without a snapshot, the normal skeleton and progressive reads remain.

Normal returning-owner startup has three GETs: `/me/`, dashboard, and sales
trend; a refresh POST is conditional on access expiry/absence. Subscription,
membership and permissions already come from `/me/`; there is no extra
subscription endpoint. The logged-out screen's optional `/health/` capability
probe does not block ordinary sign-in. Pending-command recovery may additionally
query each stored operation identity, after confirmed sign-in; it never posts a
stock command automatically. Catalog/category/photo reads happen on navigation,
not in the startup sample. Platform operators, password replacement and initial
shop setup retain their separate server-confirmed entry flows.

The two navigation problems were distinct:

- Named `MaterialPageRoute`s under Navigator 1 did not supply Flutter's real
  multi-entry browser history. Back could revisit the application document and
  its logo instead of popping the existing page.
- Five read/detail pages used `PopScope(canPop: false)` merely to return a
  changed flag, which disabled Cupertino's interactive edge gesture. Transparent
  scaffolds also let the catalog show through their glass during transitions.

Mobile skeleton pulses added continuous paint work behind glass. Azat's phone
blur cap still left backdrop filters on narrow cards/bars. The final phone path
uses the same veil, rim, shadows and colors with zero default/bar blur; wide
glass retains its existing radii. No measured backend query defect was established;
no business query, schema, permission or accounting rule was changed.

## Implementation and files

| Files | Change and purpose |
| --- | --- |
| `mobile/lib/core/api/api_client.dart` | Optional saved access, generation-aware refresh, overlapping GET coalescing, mutation revision, old-account read isolation. A command's actual success/unknown outcome survives logout; no retry is sent as a different account. |
| `mobile/lib/core/session/token_stores.dart`, `startup_snapshot.dart` | Serialized secure storage; origin-scoped access/snapshot, existing refresh credential, version/size/age checks and optional cache writes. |
| `mobile/lib/core/session/session_controller.dart` | Locked identity preview, fresh authorization gate, scoped dashboard prefetch/cache, logout/scope invalidation and late-result guards. |
| `mobile/lib/features/workspace/real_home.dart`, `real_workspace.dart` | Progressive startup, offline retry, resume validation, close old routes on session/scope changes; scope-keyed dashboard. |
| `mobile/lib/features/reports/dashboard_screen.dart`, `reports_repository.dart` | Safe cached-model parsing, saved-time notice, independent eager trend, consume one prefetched dashboard and save validated fresh data. |
| `mobile/lib/features/shared/async_section.dart` | Initial data while the existing refresh/failure behavior runs. |
| `mobile/lib/main.dart`, `mobile/lib/widgets/app_navigation.dart` | Router-backed browser history with the existing Navigator and route callers. In-app pops replace transient history; browser Back keeps the root alive. |
| `mobile/lib/widgets/app_route.dart` | Opaque ambient field per pushed page; default result without blocking native back. |
| Detail screens under `catalog/`, `expenses/`, `returns/`, `transfers/`, `warranties/` | Replace result-only pop vetoes. Dirty form confirmations remain. |
| `mobile/lib/widgets/skeleton.dart`, `glass.dart`, `app_shell.dart` | Still phone skeletons and zero phone backdrop blur, retaining the surface styling and wide blur. |
| `mobile/lib/l10n/app_ru.arb`, `app_tk.arb` | Startup/offline/cache notices. Turkmen remains provisional pending fluent review. |
| `mobile/test/core/startup_test.dart`, feature tests `back_navigation_test.dart`, `loading_skeleton_test.dart`, `reports_test.dart`, `shell_design_test.dart` | Auth/cache/failure races, default results and edge swipe, 100 route cycles, dirty confirmation, no phone skeleton ticker/backdrop filters, retained wide blur and corrupt-cache fallback. |
| `scripts/performance/{startup_benchmark,startup_scenarios,navigation_stress,phone_benchmark}.js` | Reproducible release controls and failure/stress probes using only a marked disposable sample shop. |
| `scripts/qa/store_readiness.py`, `scripts/e2e/{lib,store_day}.js` | Update stale synthetic fixtures/current phone language controls and account for floating tabs in canvas input/click helpers; suppress already-tested onboarding guides. Stock/price/retry/permission assertions remain. A scratch legacy second place exercises retained transfer services; normal shop creation stays one place. The development test server uses a 64-connection accept backlog for the 12 concurrent clients. |
| `docs/{PRD,ARCHITECTURE,DESIGN_SYSTEM}.md`, `HANDOFF.md`, `PLAN.md`, performance README | Record authorized behavior, evidence and limits. |

No runtime dependency or lockfile change. No subscription/XP/question/leaderboard
features from the generic checklist were added to this inventory ERP.

## Security and consistency

Access tokens and the bounded snapshot use the existing platform secure store
(native Keychain/Keystore; existing WebCrypto on secure web origins). Local JWT
decoding only selects the fast path; it does not verify authority. Backend token
signature/session-version checks remain mandatory. The initial preview has no
private figures or enabled business navigation/actions. A fresh `/me/` must
confirm access first. Read-only/suspended subscriptions and password-change or
operator accounts cannot revive the saved private overview.

The private snapshot is eligible only for the exact confirmed origin, user,
membership, business, role, sorted permissions/locations, subscription state/end
date, operator/password-change state. Overview TTL is ten minutes; identity TTL
24 hours; maximum encoded size 64 KiB. Bad JSON, bad models, unknown versions,
future dates, missing/expired entries and storage errors fall back safely. Email,
platform information and announcements are omitted from the saved profile.
Logout/server/account switches clear storage and memory. Generations isolate
overlapping restores, reads and refreshes. Financial/stock commands keep their
idempotency keys and real outcome; they are never authorized by cached data.
The existing JWT policy remains: password changes/resets and account
deactivation invalidate access on the backend immediately; blacklisting an
individual refresh token takes effect on refresh, while an already issued
access token remains subject to its short lifetime. The client does not invent
a stronger per-device revocation guarantee than the server provides.

## Measurements

Final raw controls and comparison are recorded alongside this review. They use
release builds, pinned Flutter 3.47.6, Chrome with an iPhone UA/390 × 844 viewport,
the same local 300-product PostgreSQL fixture and gzip preparation. Three fresh
contexts per variant/scenario; added API latency is 0 or 600 ms per request.
The zero-delay warm reload keeps normal HTTP caching. Playwright routing
disables HTTP cache in the 600-ms control; static assets still come from fast
loopback, with the same treatment for both bundles. Builds/tests are idle during
timing. This is API latency injection, not a mobile bandwidth, unstable-radio
or physical-GPU benchmark.

The first-shell boundary is identity/skeleton semantics; it can be locked.
Verified-home requires business navigation after the profile check. Home-data
requires money text and may use a fresh-enough authorized snapshot. The
interaction probe clicks Products and observes its destination; it is not
universal TTI. API wall time and summed request duration are separate because
parallel waits overlap. Cold timing uses an empty browser context and observes
sign-in; warm timing starts at reload in the same context with a saved secure
session. Each raw run identifies its HTTP-cache behavior.

Median observed times (milliseconds):

| Boundary | 0 ms API, before → after | +600 ms API, before → after |
| --- | ---: | ---: |
| First home shell (may be locked) | 245 → 172 | 1476 → 185 |
| Server-confirmed business navigation | 251 → 267 | 1486 → 854 |
| First permitted overview figures | 280 → 275 | 2145 → 872 |
| Reload through Products interaction | 370 → 356 | 2233 → 957 |
| Startup API wall span, through trend | 127 → 118 | 2605 → 1303 |
| Sum of startup request durations (overlapping) | 55 → 129 | 2500 → 1932 |
| Startup request count | 4 → 3 | 4 → 3 |

The high-latency shell boundary is about **8× sooner**, figures about **2.5×**;
this is not a tenfold improvement of every startup boundary. The cold empty-cache
sign-in median is **377 → 393 ms** across six contexts: no cold-download gain is
demonstrated. Fast-network profile readiness and summed request time are mixed;
the parallel reads overlap and do not reduce every individual request's observed
duration. These small local samples do not establish statistical significance.
The role chooser's health capability/font settling happens outside the timed
boundaries; it is only synthetic fixture setup.

In the separate 4× CPU warm phone-layout control (three five-navigation rounds),
median main-thread task work fell **941.50 → 810.49 ms** (about 14%). Recorded
long tasks were **1 → 0**; the median per-window callback-gap p95 stayed
**16.8 → 16.8 ms**. Callback scheduling is not presented-frame FPS, and the
small control does not establish a universal speedup or hardware acceptance.

Raw controls: [startup before](startup-before.json), [startup after](startup-after.json),
[navigation before](navigation-before.json), [navigation after](navigation-after.json),
[computed comparison](comparison.json). Each release is identified by SHA-256.
The after bundle is `191fd53ed58ce1e3f17f14c5c804ceecef4052a90f5e3d3652a23e83c1b0ea7d`.

## Testing

- **611 Flutter tests passed**, including auth/cache isolation, revoked/expired
  credentials, refresh throttling, duplicate reads, late account/session work,
  command outcomes during logout, blocked subscriptions, malformed cache,
  iOS edge drag, default pop results, dirty confirmation and 100 route cycles.
  The actual phone-sized test view asserts no backdrop filters/tickers, while
  wide glass retains blur.
- Full Flutter analysis/formatting, localization generation and the release web
  build passed with the pinned SDK. JavaScript syntax and the changed Python
  probe's pinned Ruff lint/format checks passed. No tests/assertions were disabled.
- Real API/PostgreSQL browser sale, exact seller price/stock result, read
  failure/retry and module navigation passed in RU/TK at **390 × 844,
  768 × 1024, 1024 × 768 and 1440 × 900**. The phone was repeated on the final
  zero-blur build; wider rendering is unchanged by that final paint adjustment.
  [Browser results](store-browser.json).
- In a fresh isolated PostgreSQL **18.4** database, 40 sales racing for 37 units
  produced exactly **37 successes / 3 stock conflicts**, with no oversell.
  Eight copies of one operation key produced one sale. **120** mixed reads at
  concurrency **12** succeeded (final phone drill p50 **55.45 ms**, p95
  **82.99 ms**, maximum **101.46 ms**). These are local development-server
  observations, not production capacity figures.
- Receiving/retry, return/refund, legacy transfer/expiry, count, FIFO profit,
  expenses, access isolation and RU/TK PDF Unicode checks passed. A separate
  restored database matched all **66** public tables and its private-file hash;
  stock reconciliation passed before and after restore. No existing database,
  private files or production server was used. [Drill summary](store-readiness.json).
- Final Chromium/WebKit API-offline controls passed: locked identity shell,
  no cached money, retry/reconnect, revoked-session sign-out and a subsequent
  offline relaunch without the old identity. This is not a fully offline web
  installation test.
- Each engine passed **20 browser-back + five mixed in-app/browser-back**
  cycles with **zero document loads, zero authentication requests and no page
  errors**. Chromium used light, WebKit dark; screenshots of the final product
  detail show its own opaque background/photo without catalog bleed-through.
  Median observed Back semantics were 46 ms / 13 ms respectively; these are
  not animation-completion or physical-touch timings. [Chromium](back-chromium.json),
  [WebKit](back-webkit.json), [Chromium failure controls](failures-chromium.json),
  [WebKit failure controls](failures-webkit.json).

## Remaining limits

- An uncached first web visit still downloads/initializes Flutter JS, CanvasKit,
  fonts and other assets; this work does not create an offline static PWA shell.
- Private data intentionally waits for fresh access confirmation. Expired
  access still needs refresh; a missing snapshot cannot display previous data.
- The tenfold startup/60 FPS targets are not guaranteed. Desktop timing and
  callback-gap observations cannot establish presented frames on an iPhone.
- WebKit is a real browser engine, but installed Safari/PWA edge gestures,
  system snapshots, device memory and slow shop Wi-Fi need physical acceptance.
  Scanner/printer hardware and native iOS builds are not validated here.
- Forward/reloaded transient URLs return to the root rather than reconstructing
  stale private screens. Existing dirty-form confirmations deliberately block
  automatic dismissal.
- No production server/load timing or deployment was performed. Local load and
  restore checks use PostgreSQL 18.4; CI uses PostgreSQL 16.
