# Phone UI polish — 2026-11-12

Local changes based on the owner's screenshots, retaining the previous uncommitted
usability/security work. No commit, push or deployment. The configured API and
stock/payment rules are unchanged.

| Screenshot / request | Result |
| --- | --- |
| Monthly sales card does not match its neighbors | Shared peer metrics reserve matching label, amount and optional-note space. Large amounts stay on one line without changing the card height; large system text reduces the dashboard's column count. |
| Quantity `2` sits above the stepper center | Explicit input-line sizing/padding fixes the actual glyph position, with a 48-pixel minimum target and room for larger text. Price input also aligns vertically; the total keeps currency on the same line. |
| Navigation press shading looks wrong | One selection marker animates between fixed touch targets. Ink splash, press highlighting and changing item shadows are removed. Drag along the bar to preview and release to select. Reselecting More still opens its menu. |
| Text shows through the bottom navigation | Its surface is opaque in both schemes. A single quiet outer shadow remains. |
| Store header uses too much space | On phones, remove the separate header and greeting. Keep native/PWA safe insets; store context and help remain in More. Tablet/desktop wide headers retain their selectors. |
| Raw product cards and photos | Square `contain` photos preserve the whole product, with neutral framing; names allow three lines, missing images have a localized caption. Detail images open an authenticated, cached viewer with pinch zoom up to 4× and an accessible close action. |
| Abrupt transitions | Short page fades/slides, a sliding navigation marker, photo reveal, smooth sheets and an animated confirmation check. Reduced-motion settings disable decorative timing; compact chart/count-up animations remain disabled. |
| Large permanent sale confirmation box | A half-sheet contains the confirmed sale, total, print, share and New sale. Dismissing it leaves a compact receipt link. New sale starts an empty cart without forcing the keyboard open during dismissal. Document failures stay visible inside the sheet. |
| Sound and vibration | Dispatch once after `SaleCompleted`, never for a request merely submitted, rejected or unknown. Flutter haptics plus an original preloaded Android two-note chime; web uses a brief synthesized chime prepared from the explicit confirmation tap. No new package, remote audio download or Apple sound recording. Audio failures cannot change a committed sale. |
| Receiving actions are scattered | Scan and Manual are adjacent primary choices; less frequent stock actions remain in More beside the heading. They stack when necessary for larger system text. |

## Evidence

- **627 Flutter tests pass**, including rendered quantity alignment, peer metric
  heights with very different totals, drag selection, confirmed feedback once,
  unknown-result silence and photo viewer controls. Existing doubled-text,
  dark-theme, safe-area, scanner, permission, retry and back-navigation checks pass.
- Flutter analysis and formatting are clean. Release web and Android debug builds
  pass; APK signature matches the previous local test builds.
- Real HTTP store/load/restore checks pass on disposable PostgreSQL. Earlier browser
  flows pass at 390×844, 768×1024, 1024×768 and 1440×900. The final artifact was
  rechecked at 390×844 and 820×1180, including sale/stock, receipt sheet, one sound
  request, read retry, photo upload/viewer, navigation and RU/TK. The fixture's
  device timezone differs from the shop's timezone. Restore reconciles afterward.
- Android API 36 ARM64 emulator: update installation, native launch, phone-sized
  touch swipe to Cash desk and More menu pass. This device check submits no shop
  transactions. Its display configuration was restored and the emulator stopped.
- Audible output, physical haptics, camera behavior and real-device frame timing
  are not certified. The emulator is muted. A direct debugger audio probe lacked
  an expression compilation service and is not counted as a passing sound test.
  Existing backend production-release blockers remain unchanged.

Summary: [results.json](qa/phone-polish-2026-11-12/results.json).
The screenshots below contain generated/disposable QA data; no customer images
were copied into the repository. Local runtime logs are `/tmp/erp-premium-*`.

| Overview | Confirmed receipt |
| --- | --- |
| ![Aligned overview](qa/phone-polish-2026-11-12/390-dashboard.png) | ![Receipt sheet](qa/phone-polish-2026-11-12/390-sale.png) |

Other captures: [cart](qa/phone-polish-2026-11-12/390-cart.png),
[stock actions](qa/phone-polish-2026-11-12/390-stock.png),
[catalog](qa/phone-polish-2026-11-12/390-catalog.png),
[photo viewer](qa/phone-polish-2026-11-12/390-photo-viewer.png).

For browser reproduction, use the existing disposable `store_readiness.py` runner
with `--browser-script scripts/e2e/store_day.js`. Set `PLAYWRIGHT_MODULE`,
`CHROMIUM_PATH`, `E2E_OUT`, and optionally `E2E_PHOTO_FIXTURE` to the checked-in
`qa/phone-polish-2026-11-12/photo-fixture.png` (relative to this document).
No existing shop/database is accepted as an input by that runner.

## Device review

Install `local-data/android-builds/erp-2026-11-12-premium-debug.apk` over the previous
same-key local test APK. Check light/dark appearance, large text, drag and taps on
the bar, photos/zoom, scan/manual receiving, quantity entry and the receipt sheet
using a test product. Confirm the sound and vibration feel appropriate with the
device's own audio/haptic settings; completing a sale writes to its configured API.
This remains a debug build, not a store release.

Platform reference: [Flutter haptic feedback](https://api.flutter.dev/flutter/services/HapticFeedback/mediumImpact.html).


QA screenshots remain local on the owner's Mac and are not published to GitHub.
An automatic privacy review rejected screenshot upload because it could expose
shop/customer data; source and synthetic test-result reports are shared without
those images. The small generated photo-input fixture contains no shop data.
