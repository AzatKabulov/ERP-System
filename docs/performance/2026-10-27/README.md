# Compact-tablet navigation control — 2026-10-27

The retained change extends immediate data/chart display from phone widths below
768 to compact layouts below 1000. Press feedback remains; wider layouts keep
entrance animation. No data cache, feature, API request or stock behavior changed
in this comparison.

The [summary](tablet-summary.json) contains all three per-build CPU rounds,
bundle/evidence hashes, long-task totals and callback measurements. Raw control
JSON is retained in ignored `local-data/performance/2026-10-27/`.

| Viewport | Median CPU work before → after, five visits | Long tasks over 15 visits | Longest task |
| --- | --- | --- | --- |
| 820 × 1180 | 1451.71 → 1008.10 ms (30.56% less) | 8 → 2 | 211 → 55 ms |
| 1180 × 820, unchanged wide behavior | 1325.29 → 1417.19 ms (6.93% more) | 6 → 8 | 65 → 68 ms |

Protocol: release web, Chromium 155.0.8059.86, 300 synthetic products without
photos, four-times CPU slowdown, semantics enabled, warmed routes. Each round
visits Products, Sales, Stock, Overview, Products, observing 1200 ms after each
input. Three baseline rounds preceded candidate rounds; builds/test suites were
idle during measurements. A broader below-1200 experiment gave mixed landscape
long-task results, so the retained cutoff is below 1000.

The compact-tablet reduction is a local control result. The landscape control's
variation illustrates why this is not a general speedup or significance claim.
Its entrance behavior is unchanged. The median per-visit callback p95 remains
16.8 ms in both builds; callback intervals are not presented-frame FPS. Fixed
observation pauses are not navigation latency. Cold load, product photos, real
Android tablets, the store network and long-session memory remain pilot checks.

Reproduce with `scripts/performance/sample_server.py` and
`scripts/performance/phone_benchmark.js`, as described in that directory's README.
Use `PERF_WIDTH=820 PERF_HEIGHT=1180` or `PERF_WIDTH=1180 PERF_HEIGHT=820` and
different `PERF_OUT` paths. Do not run other builds or tests concurrently.

The retained build also passes the full Flutter suite and a fresh WebKit store
walkthrough in tablet portrait/landscape, with Russian/Turkmen and a device date
different from the business's date. See [production readiness](../../PRODUCTION_READINESS.md)
for functional evidence and limits.
