# Performance improvements — 2026-10-22

Measured against the local test server and its existing sample shop, using the pinned Flutter 3.47.6 release web build. No stock-changing workflow or database schema changed.

## What changed and why

| Before | After | Why |
| --- | --- | --- |
| A completed `Reveal` removed its opacity/transform wrappers | The element tree stays stable; the curve is owned and disposed once | Removing the wrappers remounted stateful children. The dashboard loaded twice and recreated its content. Fully opaque `Opacity` does not need an opacity compositing layer. |
| One catalog child laid out the entire gallery, including all 30 photos | Each responsive row is a separate lazy scroll child | Offscreen rows no longer need an immediate layout or photo download. Cards still stretch to equal heights within each row, including long translations and scaled text. |
| Page reveals took 420 ms, number animations 900 ms and charts 1100 ms | These arrivals use the shared 260 ms duration | Frequent navigation reaches its final visible state sooner while preserving the easing and reduced-motion support. |
| The local server sent web resources uncompressed | The launcher prepares gzip files once and the server negotiates them | Wi-Fi clients download fewer bytes without recompressing a large file on every request. Original content types, revalidation and traversal checks remain in place. Newer original files always take precedence over stale compressed files. |

These changes address duplicate work and slow visual completion. API calls were already fast in this local workload, so no database indexes or business-data cache were added. The production Caddy configuration already enables compression; the new static-file handling is for the local launcher.

## Measurements

Chromium, viewport 390 × 844, CPU slowed by a factor of four through DevTools. Pages and pictures were warmed before measurement. The workload visits Products → Sales → Stock → Overview → Products, waiting 1300 ms after each click. Authentication is outside the measured interval. These are synthetic desktop measurements, not an iPhone or pilot-network benchmark.

| Measurement | Before | After |
| --- | ---: | ---: |
| Main-thread tasks longer than 50 ms | 26 | 15 |
| Total time in those tasks | 3350 ms | 2159 ms |
| Longest task | 581 ms | 259 ms |
| 95th percentile animation-frame callback interval | 35 ms | 25 ms |
| Frame callback intervals longer than 33 ms | 51 | 34 |
| API requests in the navigation workload | 9 | 8 |
| Dashboard requests on one overview visit | 2 | 1 |
| API request timings in the warm run | 18–36 ms | 15–38 ms |

Callback intervals help detect main-thread scheduling stalls; they are not a measurement of GPU frame presentation or an FPS guarantee. The workload includes fixed pauses, so its total elapsed time is not a page-load or navigation-latency metric. Timing results vary with host load.

Public-resource bytes, measured from response headers with gzip accepted:

| Resource | Uncompressed | Compressed | Reduction |
| --- | ---: | ---: | ---: |
| `main.dart.js` | 4,184,502 | 1,170,853 | 72% |
| Chromium CanvasKit Wasm | 5,428,806 | 2,062,566 | 62% |

This is encoded transfer size, not a claim about JavaScript parse cost or end-to-end load time. Other browsers may choose a different CanvasKit variant.

## Validation and reproduction

- All **407 Flutter tests pass**; Flutter analysis and the focused formatting check pass.
- The remount and eager-photo regression tests failed before the fix, then passed. The gallery test starts with 30 photos, requires fewer than 15 initial downloads on a phone viewport, and verifies that scrolling builds and downloads later rows. The existing responsive, large-text and localization tests remain enabled.
- **Nine local-server tests pass**: gzip negotiation and decoding, original content type, conditional requests, gzip refusal, missing and stale sidecars, timestamp preservation, path traversal denial and unchanged APK downloads. These tests use temporary public files and do not access business records.
- The web build succeeds; the optimized build is served locally, login still opens the workspace, and the health endpoint returns `ok`.
- No new platform plugins or backend business behavior changed. Android builds, physical iPhone/Android runs and the stock/money end-to-end suite were not rerun for this performance change.

To repeat the rendering benchmark, open the local website in an isolated Chromium Playwright CLI session, resize to 390 × 844, enable Flutter accessibility and sign in in Russian. Run `playwright-cli -s=<session> run-code --filename scripts/e2e/performance.js` once to warm the pages, then again to measure. It reports timing and endpoint names without credentials, tokens or response bodies. Do not benchmark while builds or tests are consuming the same machine.

The comparison catches a meaningful improvement but still shows remaining long tasks. Continue profiling on the actual pilot tablet/iPhone and network before promising a frame-rate or startup-time target.
