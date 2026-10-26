# Reproducible navigation experiment

For the later phone-layout control, use `phone_benchmark.js` with
`ERP_E2E_DISPOSABLE=true`, `E2E_WEB_URL`, `PERF_OUT` (output JSON file),
`PLAYWRIGHT_MODULE` and `CHROMIUM_PATH`. It uses local sample-role login, warms
routes, then records three five-navigation cycles at 390 × 844 / CPU 4× using
CDP main-thread work, long tasks and callback gaps. Keep builds/tests idle during
capture. It does not measure physical-phone FPS or cold startup. Results and
limitations: [2026-10-26](../../docs/performance/2026-10-26/README.md).

Use only a disposable synthetic shop. The tools refuse unmarked nonempty data folders;
they do not use the ordinary `local-data/` database. Authentication happens before tracing.
No package or runtime instrumentation is added to the application.

Requires the pinned Flutter and backend environments, Python 3.13 for the sample server,
Node, Playwright and a Chromium executable. Follow the repository's local setup first.

1. Build each source variant with the same pinned toolchain:

   ```sh
   cd mobile
   flutter build web --release --no-web-resources-cdn --no-pub --dart-define=LOCAL_HTTP_TESTING=true
   ```

   Save each build as a separate tar archive containing a single `web/` directory.
   Do not use a diagnostic `--profile --source-maps` build for release comparisons.

2. From the repository root, start a fresh synthetic server in another terminal:

   ```sh
   uv run --project backend --with pixeltable-pgserver==0.6.0 python scripts/performance/sample_server.py \
     --data local-data/performance/new-run/server --web mobile/build/web --port 8001
   ```

3. Configure local executable paths and run the alternating blocks. The runner reads the
   generated sample password from the marked folder and supplies it through the environment.
   Never put a real shop's credentials into these commands.

   ```sh
   export E2E_WEB_URL=http://127.0.0.1:8001/
   export NODE_BINARY=/path/to/node
   export PLAYWRIGHT_MODULE=/path/to/node_modules/playwright
   export CHROMIUM_PATH=/path/to/chromium
   python3 scripts/performance/run_blocks.py \
     --data local-data/performance/new-run/server \
     --baseline /path/to/baseline-web.tar.gz --candidate /path/to/candidate-web.tar.gz \
     --out local-data/performance/new-run/blocks --iterations 6
   python3 scripts/performance/compare_blocks.py local-data/performance/new-run/blocks \
     > local-data/performance/new-run/comparison.json
   ```

The default order is baseline, candidate, baseline, candidate. Each block has a fresh
browser; its first route visit is reported separately from subsequent warm visits.
Keep other builds, tests and heavy applications idle during measurement. Use `--no-trace`
for a separately labeled instrumentation-overhead control, never mix it into traced runs.
Stop the sample server with Ctrl+C when finished.

For the small warm-navigation control, `phone_benchmark.js` also accepts
`PERF_WIDTH` and `PERF_HEIGHT` (defaults 390 × 844). Use the same marked 300-product
fixture, set `ERP_E2E_DISPOSABLE=true`, `E2E_WEB_URL` and a separate `PERF_OUT` JSON
path for each build/viewport, then run it with Node. It reports three warm rounds,
four-times CPU slowdown, bundle hash and callback/CPU metrics. Keep builds and
other test suites idle. These controls do not establish device FPS or cold-load
performance.

The benchmark records destination semantics and an actual search-field focus probe.
These are operational readiness boundaries, not pixel presentation or universal TTI.
The fixed two-second observation window is not navigation latency. `callbackWorkMs500`
sums animation callbacks **starting** within 500 ms of input; it is not FPS or dropped
frames. CPU sample weights are inclusive, deduplicated per function per sample, and
cannot be added across functions. Repeated generic/minified names can combine functions.

Raw traces can be decompressed and opened in Chrome's Performance panel. The analyzer
recomputes timings from their `erp.navigation.*` marks. Before sharing any new artifacts,
inspect them for credentials and customer data; only synthetic data belongs in the repo.
See [the recorded experiment](../../docs/performance/2026-10-23/README.md).
