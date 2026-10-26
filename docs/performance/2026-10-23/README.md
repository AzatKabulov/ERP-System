# Navigation experiment — 2026-10-23

**Result: the proposed repaint boundary failed the acceptance criterion and was removed.**
This pass does not establish a new application speedup. The performance work is incomplete;
the scanner/receiving updates remain intact. The reproducible tools and raw evidence are
retained so the next developer can continue from measurements.

## Scope and acceptance

One interaction: Overview → Products gallery. Preserve the content, design, 260 ms
transition, accessibility, API requests and data freshness. Before the final repeat,
the acceptance target was at least 20% less work in the confirmed bottleneck under
matched conditions. No latency metric met that threshold in the final comparison.

The original observation of roughly 15 FPS was not reproduced as a measured frame rate.
Browser callbacks and semantics do not establish GPU presentation timing.

## Raw material and method

- Release Flutter 3.47.6 web build; Chrome headless; Apple M5; macOS arm64;
  820 × 1000 viewport; DevTools CPU throttle 4; accessibility semantics enabled.
  Exact browser version and hardware metadata are in each `blocks/*/samples.json`.
- Separate local PostgreSQL sample shop: 300 deterministic products, 30 per API page,
  long Cyrillic/Turkmen names, no product photos or stock. Loopback network, no network
  throttling. This is not representative of a slow shop network or an image-heavy catalog.
- Four sequential fresh-browser blocks: baseline, candidate, baseline, candidate;
  six route visits per block. Two first-route samples and ten warm samples per variant.
  First-route means the first Products visit after login, not a cold application start.
  Builds/tests were kept outside the measured run.
- Raw CDP traces, user timing marks, trusted mouse input, MutationObserver semantics,
  PerformanceObserver long tasks and request timing. Authentication precedes capture;
  no request bodies, credentials or authorization headers are intentionally recorded.
- Feedback: destination search input enters the semantics tree. Useful content:
  `PERF-0000` enters that tree. Readiness probe: a subsequent trusted mouse click
  successfully focuses search. The probe includes automation scheduling overhead.
- Main-thread work: total duration of animation callbacks starting in the first 500 ms
  after the input mark. A callback may end after that boundary. This captures layout,
  painting and other callback work; it does not isolate GPU cost or presented frames.

`baseline-source-manifest.json` identifies the exact source, including the pre-existing
uncommitted scanner updates; the old HEAD alone does not reproduce that state. The final
mobile source matches that manifest because the candidate was discarded. The experimental
patch was only `_PageEnter`'s `SlideTransition.child`: replace `widget.child` with
`RepaintBoundary(child: widget.child)` in `mobile/lib/widgets/app_shell.dart`.
Each block records its served JavaScript SHA-256; each variant has exactly one hash.

## Findings and competing explanation

The raw release traces show substantial animation callback work around destination
construction. In the initial warm diagnostic trace, a callback ran for about 48 ms
before the product request was dispatched; another ran for about 64 ms around product
arrival. The category and product requests themselves took approximately 5 and 9 ms.
This rules out slow local API responses as the main explanation for that interaction,
under these conditions. It says nothing about remote production latency.

A separate, non-comparable diagnostic profile build exposed framework symbols in
layout/build and painting stacks, including `RenderSliverList.performLayout`,
`RenderIntrinsicHeight.performLayout`, `buildScope` and `PaintingContext`.
Those overlapping sampled stacks locate work; they do not establish that one widget
causes all of it. A repaint boundary tested the narrower hypothesis that repeated
painting during the unchanged page transition was a material cause. The controlled
release result below did not support shipping that change.

## Final comparison

Warm medians, with interquartile ranges in parentheses; milliseconds. Ten warm samples
per variant are too few for reliable tail-latency claims. Overlapping ranges and block
variation preclude treating a small median difference as a dependable improvement.

| Metric | Baseline | Candidate | Median reduction |
| --- | ---: | ---: | ---: |
| Destination feedback | 84.85 (83.88–87.75) | 86.55 (84.23–89.10) | −2.0% |
| Useful content | 173.80 (171.15–178.42) | 165.70 (161.92–183.58) | 4.7% |
| Successful focus probe | 303.00 (291.25–316.15) | 305.15 (275.72–315.37) | −0.7% |
| Callback work, first 500 ms | 305.17 (300.32–315.34) | 307.14 (293.30–316.02) | −0.6% |
| Longest callback | 60.19 (53.11–68.82) | 54.83 (53.02–64.06) | 8.9% |

First-route observations and all request timings remain in `comparison.json` and the
individual samples. They are not pooled into warm statistics. Both variants requested
categories and products on navigation; no data cache or request suppression was added.
The initial final-run attempt timed out during browser startup before any valid sample;
only the complete retry appears here. Earlier exploratory/profile/pilot measurements
are excluded from the final comparison.

## Independent verification and limits

The shared `blocks/` contain four sample files. The 24 compressed raw Chrome
traces are retained locally at
`local-data/performance/2026-10-23/local-traces/blocks/`, with the same block/file
names, and in the original local Git history. Automatic approval review rejected
their public upload because code-push authorization did not clearly include raw
profiling artifacts. They are not included in the public source branch.
The owner subsequently approved source-only publication directly to `main`;
the original local branch still retains every trace.
`artifact-sha256.json` retains their hashes. Recompute the table from the shared
sample files at repository root:

```sh
python3 scripts/performance/compare_blocks.py docs/performance/2026-10-23/blocks
```

Decompress a locally retained trace and import it into Chrome's Performance panel to inspect the work
around the named navigation marks, independently of this report. The complete rerun
procedure is in [scripts/performance/README.md](../../../scripts/performance/README.md).
Local artifacts were checked against the sample password and a JWT pattern.
A later scan of all 24 traces found only loopback URL hosts, no authentication
URLs, and no JWT, authorization/cookie header, private-key or password-value
patterns. These checks do not replace approval for publishing the raw artifacts.

No new optimization is installed on the owner's running app. Physical Android/iOS,
GPU frame presentation, memory stability, reduced tracing overhead, other user journeys,
photo-heavy datasets and slow-network behavior were not measured in this experiment.
The next justified step is a layout-focused experiment, with the same acceptance rule,
on the actual target tablet as well as web. Avoid changing intrinsic card sizing until
long translations and scaled text remain correct.

Final sharing checks: all **428 Flutter tests passed**, Flutter analysis was clean,
targeted Python Ruff checks/formatting and JavaScript syntax checks passed. Recomputing
the comparison reproduced the saved JSON exactly, and all 28 raw-artifact hashes matched.
The existing scanner/receiving backend and browser acceptance results are recorded in
`HANDOFF.md`; those earlier checks were not rerun as part of this rendering experiment.
