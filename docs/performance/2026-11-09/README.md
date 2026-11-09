# Flutter Web optimization review — 2026-11-09

The owner authorized implementing applicable improvements from Azat's
`Optimization.txt`. The supplied checklist is largely written for DOM/React
applications. This review uses the actual pinned Flutter 3.47.6 client, Django
API and Caddy configuration. Changes are on `codex/web-performance`; the owner
requested commit and push, with no deployment or app release.

## Findings and changes

1. **The wide catalog table eagerly built every loaded product.** Its single
   `Column` laid out all rows and started all 30 thumbnail downloads on first
   entry, although most rows were offscreen. A `CustomScrollView` now uses a
   builder-backed sliver for table rows, preserving the single glass surface,
   column proportions, row actions and variable row heights. Gallery rows and
   compact list tiles also use builders, so additional loaded pages do not
   construct all offscreen row widgets on each rebuild. Existing pagination,
   search, permissions and loading/empty/error states remain.
   Source: [catalog_screen.dart](../../../mobile/lib/features/catalog/catalog_screen.dart).
2. **The photo cache limited entry count but not retained byte size.** It now
   evicts least recently used entries at either 400 entries or 16 MiB of encoded
   image bytes. A photo larger than the budget is delivered to the requesting
   widget without retaining it or displacing reusable smaller images. Concurrent
   callers still share a download; failed requests remain retryable; clear/logout
   prevents older downloads from repopulating the cache. This budget excludes
   Flutter's decoded image cache, in-flight responses and active widgets; it is
   not a total application RAM limit.
   Source: [photo_cache.dart](../../../mobile/lib/core/files/photo_cache.dart).

## Release-browser control

Three fresh Chrome 156 contexts per bundle, 1440 × 1000, Russian/light/list,
CDP CPU slowdown 4×. The same disposable PostgreSQL sample shop has 300 products
and generated 320 × 240 test pictures. Authentication and engine startup happen
before capture. Capture covers entering Products and an identical 1800 ms wait;
it records photo requests and CDP `TaskDuration` deltas. Screenshots and scrolling
occur after that window. Each run then scrolls, requires an HTTP 200 response for
offset 30, and verifies more photos arrive. Builds and tests were idle during
accepted captures. Baseline and candidate were captured as consecutive blocks,
not a randomized or statistically powered experiment.

| Initial catalog visit | Baseline | Optimized |
| --- | ---: | ---: |
| Photo requests, every run | 30 | 14 |
| Median main-thread task work | 512.4 ms | 428.2 ms |
| Task work minimum–maximum | 510.4–525.6 ms | 419.6–440.0 ms |

The deterministic result is **53.3% fewer initial thumbnail requests** at this
viewport. The observed CPU-work median was 16.4% lower in this small synthetic
control. These are not navigation latency, presented-frame FPS, cold-start time
or production/iPhone benchmarks. No network throttling was applied; this does
not establish performance from Turkmenistan. Other sizes and text scales build
different numbers of nearby rows. Scrolling still fetches later photos normally.

Raw counts, timings and exact bundle hashes are in [baseline.json](baseline.json)
and [candidate.json](candidate.json). Screenshots, full test logs and both build
archives are git-ignored under `local-data/web-performance-2026-11-09/`.
Reproduction: [scripts/performance/README.md](../../../scripts/performance/README.md).

## Checklist applicability

This is a scoped source review and targeted implementation, not a claim that
every experimental browser API or every supplied numeric threshold was audited.

| Supplied layer | Findings and disposition |
| --- | --- |
| Architecture/bundling | Flutter release JS/CanvasKit and existing tree shaking. React hydration, islands, JSX and npm `sideEffects` rules do not map to these widgets. No framework migration or package upgrade. Wasm compatibility dry-run passed during build; an actual Wasm renderer rollout requires its own browser/plugin checks. |
| Service workers | The pinned release emits a cleanup worker that unregisters itself. Workbox navigation preload, static routing and HTML-stream composition are not existing application paths to tune. No new API caching or background stock replay was added. |
| Network delivery | `infra/Caddyfile` already enables zstd/gzip and revalidates unversioned entry bundles with `no-cache`. Assets should not receive blanket year-long immutable caching under reusable URLs. Live HTTP/3 negotiation, cold-start waterfalls and browser-cache migration were not measured here. |
| Main thread/lifetimes | The eager table was reproduced and fixed. Search already debounces; API requests already time out; scanner and motion lifetimes have existing cleanup. No unmeasured scheduler/polyfill or pooling layer was introduced. |
| Workers/shared memory | No measured parsing/computation hotspot in this workload warrants a new worker pool. COOP/COEP, SharedArrayBuffer and OffscreenCanvas need renderer/integration evidence before changing server headers. |
| Rendering | Lazy table, gallery and compact list builders implemented. Existing responsive layout, cards, themes and reduced-motion behavior retained. Glass rendering cost on physical hardware remains unmeasured. CSS-only virtualization and `<picture>` rules do not directly optimize Flutter's painted product widgets. |
| Storage | The server remains authoritative; preferences retain settings, drafts and operation identities. IndexedDB/OPFS/relaxed durability would be a separate storage design, not a prerequisite for these fixes. |
| iOS/memory/telemetry | Encoded-photo retention now has a byte cap and race/eviction tests. Physical WebKit memory, installed-PWA recovery, RUM and performance CI budgets remain unverified/unimplemented; this change does not certify them. |

## Verification

- A new wide-table regression failed against the old code, observing 30 initial
  photo downloads. Final RU/TK cases explicitly set both preferences and profile
  language, assert the translated page title, verify later rows load, and open
  the last product's detail. Both pass.
- Five byte-budget tests cover LRU eviction, oversized images, out-of-order
  completion, clear during a pending download and released byte allowances.
  Existing tests cover sharing requests, failed downloads and entry-count limits.
- **574 Flutter tests pass** after the final builder change; the two language
  regressions were also rerun after explicitly setting the profile language.
  Existing cases cover pagination, gallery/list layouts, empty/search/error/permission behavior, long names,
  doubled text, pictures, stock/expiry displays and scanning fallback.
- Flutter analysis and formatting pass; the pinned release web build succeeds.
  The Python fixture passes Ruff check/format; the browser script passes Node's
  syntax check.
- Release-browser responsive checks passed at 390, 1024 and 1440 widths in both
  themes across Russian and Turkmen. The extra cases cover phone gallery/list,
  tablet gallery/table and desktop table; every case scrolls and loads the next
  page without browser warnings/errors. Initial/next-page screenshots were
  inspected, including the two phone layouts and dark Turkmen table. Raw results:
  [responsive.json](responsive.json). These desktop viewport checks do not replace
  physical-device acceptance.
- Backend business code, schema and dependencies did not change. Backend tests,
  the stock/money E2E suite and physical-device checks were not rerun for this
  catalog-rendering/cache change. Android/iOS runtime performance is unverified.

## Next measurements

1. On the owner's actual phone/tablet and shop connection, capture cold and warm
   startup separately from scrolling and input response; record model/browser.
2. Profile the retained glass effects on that device before reducing blur or
   changing the agreed design.
3. Measure long-session memory and large stock/sales lists, then extend lazy
   rendering only where an eager list or excessive retention is demonstrated.
4. Evaluate Wasm, asset versioning/cache policy and privacy-safe performance
   budgets as independent changes with before/after and integration evidence.

No change here enables offline sales or weakens authorization, tenant isolation,
private-file access or the restart-safe operation runner.
