# Phone web navigation follow-up — 2026-10-26

Narrow screens now show data immediately instead of simultaneously fading/sliding
the page, staggering cards, counting figures and drawing charts. Press/selection
feedback, desktop presentation and business requests remain. The rejected
repaint-boundary experiment was not reintroduced.

The final release used **13.0% less main-thread work** in this synthetic workload.
This is a CPU-work reduction, not phone FPS, scroll smoothness or cold-load speed.
The actual reported phone slowdown has not been reproduced on its device/browser.

| Five-navigation cycle | Baseline | Final |
| --- | ---: | ---: |
| Median main-thread work | 1001.6 ms | 871.0 ms |
| Minimum–maximum | 973.6–1075.5 ms | 779.8–874.3 ms |
| Cycles | 6 | 3 |

The accompanying JSON files contain exact bundle hashes, each visit's raw CDP
TaskDuration/LayoutDuration/ScriptDuration deltas, long tasks and animation-frame
callback gaps. `comparison.json` contains the arithmetic. Callbacks are not GPU
presentation frames. Baseline and final navigation windows did not reproduce a
sustained 10-FPS symptom: callback-gap p95 was around 16.8 ms and no task exceeded
50 ms. This limits conclusions about the owner's phone.

## Method and exclusions

- Flutter 3.47.6 release JS/CanvasKit, `--no-web-resources-cdn`,
  `LOCAL_HTTP_TESTING=true`; no application instrumentation.
- Desktop Chrome 155 on the Mac host, 390 × 844 viewport, CDP CPU slowdown 4×,
  accessibility enabled. This does not reproduce phone GPU/thermals, Safari or
  mobile network behavior.
- Separate marked PostgreSQL sample shop on port 8002: 300 deterministic
  products, 30 per page, no photos. No customer records or finalized sales.
- Login and route warmup precede capture. Three cycles visit Products, Sales,
  Stock, Overview, Products; each visit uses the same 1200-ms observation wait.
  Sum CDP TaskDuration deltas across five visits. The wait is not navigation
  latency. No builds or test runs overlapped accepted measurements.
- Two accepted baseline blocks bracketed intermediate candidate blocks. The
  final block was rerun after bundling the scanner. The intermediate candidate
  suggested 21.6% less CPU work; the final result above supersedes that estimate.
  Small local samples provide no statistical confidence or hardware guarantee.
- An initial baseline lacked CPU metrics and overlapped a build: excluded. A
  failed archive switch left a candidate active; its bundle hash identified it
  and it was not counted as a baseline. No assertions were weakened.

Reproduce using `scripts/performance/phone_benchmark.js` and the disposable server
from `scripts/performance/sample_server.py`. Set `ERP_E2E_DISPOSABLE=true`,
`E2E_WEB_URL`, `PERF_OUT`, `PLAYWRIGHT_MODULE` and `CHROMIUM_PATH`. Local sample-role
login avoids recording credentials. Compare saved release bundles against the
same fixture and keep other builds/tests idle. The tooling README explains safe
bundle switching, restricted to marked disposable servers.

## Scanner and physical acceptance

The existing zxing-wasm fallback is bundled instead of fetched from jsDelivr;
integrity, checksums and licenses are in `mobile/web/scanner/`. Phone-width browser
checks force the fallback and block other origins, require decoded EAN-13 and
ended camera tracks, and find catalog/sales results without adding to the cart.
The complete manual receiving form passed against real API/PostgreSQL at phone
width, including quantity, warranty and expiry.

Phone camera access requires trusted HTTPS. The private-Wi-Fi helper and public
CA installation are documented in `docs/LOCAL_TEST.md`; LAN HTTP cannot grant
camera access. Actual phone permissions, focus, keyboard resizing, touch
scrolling, file sharing and FPS remain physical-device acceptance work. Record
phone model, browser, URL and findings before claiming hardware equivalence.
