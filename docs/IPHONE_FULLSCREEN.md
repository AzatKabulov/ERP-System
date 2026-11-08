# iPhone fullscreen PWA preview — 2026-11-08

Implementation on `feature/premium-design`. Initial verification ran locally
before publication was authorized. The owner subsequently requested commit, push
and deployment of `/fs/` only, then cancelled deployment and requested **push
only**. The normal site must stay unchanged. The public
`/fs/` URL has **not** received this implementation yet; server SSH access is
required to publish it. Earlier skeleton-loading work is preserved in its own commit.

## Audit: four separate questions

1. **Launch geometry.** The deployed `/fs/` HTML has black-translucent,
   viewport-fit=cover, `erpFullScreen=true` and a viewport repair observer, as the
   prompt describes. This prototype is absent from the latest GitHub commit
   (`78e82f1`); its original Dart source was not available in that commit. The
   ordinary live page also differs from the repository's current index metadata.
   This change preserves the repository's normal `web/index.html` and manifest.
   A separate reproducible artifact chooses the fullscreen metadata at install
   time, rather than trying to switch status-bar style with the runtime theme.
2. **Drawing versus controls.** AmbientField and the AppShell top glass already
   start at y=0; the sign-in page's outer SafeArea moved the *whole* deep-blue
   brand background below the inset. In `/fs/`, its background now starts at zero
   and only its text/controls receive safe padding. The application MediaQuery
   carries browser safe areas above Navigator, covering pushed pages, dialogs
   and sheets as well as the initial page. AppBar backgrounds are transparent
   in the preview, allowing the existing scene to continue underneath.
3. **Opaque top strips.** No new HTML status-bar rectangle, copied color,
   duplicated canvas, CSS transform or body top padding is used. HTML/body/splash
   colors remain startup/overscroll fallbacks; the splash is removed after the
   first Flutter frame. Flutter's canvas covers the viewport at (0,0). A light
   theme has a translucent readability veil that fades *past* the safe boundary;
   it composites the actual scene, including scrolling content. It is not an
   opaque swatch or a hard-edged strip. Dark theme removes this light-theme veil.
   Intentional camera/black-screen surfaces retain their own dark background.
4. **Runtime theme.** Dart repaints the same full-size scene when theme changes;
   the preview does not depend on mutating iOS status-bar metadata at runtime.
   Its apple status style stays black-translucent. The existing scheme function
   still updates startup/HTML/theme-color fallbacks, which are not a replacement
   for drawing the scene beneath the clock. Widget and browser checks exercise
   both themes and switching while open.

Apple documents the distinction between [black and black-translucent](https://developer.apple.com/library/archive/documentation/AppleApplications/Reference/SafariHTMLRef/Articles/MetaTags.html).
WebKit explains [viewport-fit=cover and selectively insetting controls](https://webkit.org/blog/7929/designing-websites-for-iphone-x/).
An ordinary Safari tab keeps Safari's own UI; it does not establish the installed
PWA's status-bar behavior.

## Implementation

- `core/web/web_chrome_*.dart`: opt-in flag, four safe-inset reads and a removable
  viewport-change listener; native/ordinary documents return the existing path.
- `widgets/pwa_viewport.dart`: merges CSS and native viewPadding with `max`, not
  addition; subtracts keyboard viewInsets for usable padding. View size, origin,
  scale and input coordinates are never changed. Its scope is above Navigator.
- `main.dart`: subscribes to inset changes and applies the preview-only wrapper,
  transparent AppBar theme and pointer-transparent readability veil. Normal mode
  retains its existing theme and MediaQuery.
- `app_shell.dart`, `glass.dart`, sign-in: paint to the edge and inset controls;
  retain normal layout when the flag is absent/false. Landscape side insets are
  accounted for. Global AmbientField still fills the drawing surface.
- `scripts/pwa/fullscreen.js`: runs only for `window.erpFullScreen===true`;
  restores cover when Flutter removes/replaces/changes viewport metadata. The
  observer is idempotent; resize work is coalesced into animation frames, without
  a periodic polling timer, touch cancellation or DOM position/size patches.
  Safe areas update on resize, orientation, visibility, visualViewport events and
  return from background. Diagnostics never intercept input.
- The green diagnostic now shows the actual `flutter-view` rectangle **and** the
  `flt-glass-pane` size. In pinned Flutter, the latter is only a platform-view
  host and can legitimately be 0×0; it is not the application viewport.
- `scripts/build_fullscreen_preview.py`: creates `mobile/build/web-fs` from an
  already built normal web app, sets launch-time metadata and `/fs/` manifest
  identity/scope/start URL, and injects the bridge. The normal artifact remains
  byte-for-byte untouched. Legacy caching-worker names/hashes are isolated;
  pinned Flutter's non-caching cleanup worker is preserved. Unrelated existing
  output directories are refused. No command deploys this artifact.
- The local test server can serve an optional artifact folder at `/fs/`; `/`
  continues to serve the ordinary build. Public hosting configuration is untouched.

## Build and checks

```sh
cd mobile
flutter analyze
flutter test
flutter build web --release --no-web-resources-cdn
cd ..
python3 scripts/build_fullscreen_preview.py
```

Pinned SDK: Flutter 3.47.6. No dependency/lockfile change.

- Analyzer: no issues. Full Flutter suite: **567 passed**, including all existing
  tests and seven fullscreen-specific tests. The pre-skeleton baseline was 526;
  no existing tests were removed.
- Fullscreen widget checks: unchanged normal path; ambient/top-bar y=0;
  safe top/bottom tap targets; sign-in background reaching the top while its
  controls inset; no doubled native padding; keyboard/landscape calculations;
  inherited geometry for pushed pages, dialogs and sheets; pointer-transparent
  veil; rendered pixels change when the scene beneath the veil changes.
- Release web build passed, including the SDK's Wasm dry run. This is the normal
  JavaScript release, not a claimed standalone Wasm release.
- Artifact builder: three isolated tests passed, including byte-for-byte normal
  build preservation, launch-time opt-in, manifest identity, legacy worker
  isolation, safe rebuild and refusal to erase unrelated output.
- Local static-file tests: ten passed, no database access; Python lint/format
  and JavaScript syntax checks cover the changed helpers.

Browser run: **six cases passed** — four fullscreen cases (Chromium/WebKit ×
light/dark) plus the ordinary host in both engines. Fullscreen cases checked a
393×852 CSS-pixel viewport at DPR 3, (0,0) drawing origin, cover repair after an
actual viewport-meta mutation, unchanged black-translucent style after theme
switching, top Help/Back and bottom navigation touch targets, and live rotation
to 852×393 with changed left/right/bottom insets. The normal-host cases verified
that the flag/diagnostics remain off. No browser page/console errors occurred.

The top 59px screenshot changed after scrolling the **real dashboard**, proving
that it composites changing Flutter content rather than a fixed color. Chromium
used wheel scrolling; mobile WebKit does not expose a Playwright wheel API, so
its scroll used a browser pointer-touch gesture through Flutter's input binding.
Navigation taps used Playwright's touchscreen API in both engines. Neither path
establishes physical iPhone touch latency or native status-bar compositing.

Machine-readable results: `docs/qa/fullscreen-browser-results.json`.
Screenshots with the green diagnostic are in `/tmp/erp-fullscreen-browser/`,
including sign-in and completed runtime theme switches. These are browser
simulations, not screenshots from a physical iPhone. Theme screenshots wait for
the existing Material transition to complete.

The test requires a separate disposable localhost server, never a real shop:

```sh
ERP_E2E_DISPOSABLE=true E2E_WEB_URL=http://127.0.0.1:8001/ node scripts/e2e/fullscreen.js
```

Set PLAYWRIGHT_MODULE and CHROMIUM_PATH for the installed toolchain. Insets are
**simulated** (portrait 59/0/34/0, landscape 0/59/21/59) in browser tests; no claim
is made that an iPhone reports those exact values. The bridge reads the device's
actual CSS environment values in normal use.

## Required real-iPhone acceptance check

The public address below still serves the old implementation. These steps apply
**after a separately authorized update of `/fs/` only**, not before. Do not enable
fullscreen on `/` until the owner confirms this check.

1. Delete the old **ERP fullscreen test** Home Screen icon. Leave the ordinary
   ERP icon alone. Open https://erp.kemalysh.dev/fs/ in Safari and reload.
2. Share → Add to Home Screen. Launch from the new icon, not from a Safari tab.
   The green line must say `standalone`; keep it visible in screenshots.
3. Check sign-in: navy brand paint reaches behind clock/Dynamic Island, with no
   white strip or seam. Text/buttons remain below the cutout.
4. Sign in and scroll the overview and a long list so different surfaces pass
   beneath the top glass. The clock area must show that same moving scene with
   the continuous light-theme readability tint, never a separately fixed swatch.
5. Settings → Appearance: Light → Dark → Light. Check top, page and background
   together, then close and reopen the installed app in each theme.
6. Tap Help/Back near the top, each bottom navigation tab, a dialog control and a
   bottom-sheet row. Every tap must hit its visible target once, without an offset
   or a delayed tap. Open/close the keyboard and repeat near top/bottom.
7. Rotate portrait/landscape, return from background and repeat scrolling/taps.
   Check that the diagnostic view starts at 0,0 and fits the viewport, `scrollY`
   stays 0 for the outer document, and safe insets change appropriately.
8. Check a shop role, platform-owner pages (with the normal operator account),
   a pushed detail page, dialog and bottom sheet. No hidden controls or top seams.
   Send one screenshot on sign-in and one after scrolling/theme switching, with
   the green numbers visible, if anything differs.

## Unverified limits

No physical iPhone, actual Dynamic Island/status-bar compositing, installed-PWA
launch snapshot, physical keyboard interaction or physical touch latency was
available here. Browser viewport tests and synthetic insets are not device tests.
Screenshots from the local browser deliberately show no invented iOS clock/icons.
White system clock readability and the final tint strength require the owner's
installed-iPhone confirmation. No public `/fs/` update or normal-site update was performed during local
verification. Publication requires the separately authorized deployment step.
