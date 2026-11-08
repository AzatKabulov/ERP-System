# Application loading audit — 2026-11-08

Source: `78e82f1`, `feature/premium-design`. Implementation is local on
`feature/skeleton-loading`; no push or deployment is authorized for this task.
This inventory was written before changing loading widgets. Baseline: **526
Flutter tests passed** using pinned Flutter 3.47.6 and the frozen lockfile.

## Architecture and plan

Flutter/Dart, ChangeNotifier and StatefulWidget/FutureBuilder; real HTTP through
ApiClient and feature repositories. No React/Tailwind or new dependency is needed.
Shared widgets live in `mobile/lib/widgets`, async presentation in
`features/shared/async_section.dart`. Light/dark AppPalette, Onest typography,
glass surfaces, pagePadding/ChromeInsets and existing LayoutBuilder breakpoints
are authoritative. Native and web share widgets. Navigation is already available
after authorization and should remain visible while individual sections load.

Implement shared skeleton primitives/composites, then explicit page profiles at
every content-read site below. Keep real Futures, error/empty/retry paths, drafts,
role checks and action indicators. Retain loaded AsyncSection content on refresh
without remounting form children. Bound animation to one lightweight repaint-only
pulse per region, stop it for reduced motion/offstage, and expose one localized
Flutter `SemanticsRole.status`/live-region label rather than every decorative bone.
Use Flutter semantics rather than injecting HTML attributes into the shared app.

## Route-by-route inventory (before implementation)

Each row requires initial/slow-load, success/empty, failure/retry and disposal
checks where the route actually fetches data. Verification is recorded below
after implementation; creating a skeleton alone is not completion.

| Route/component | Current behavior | Planned skeleton | Responsive/layout constraints |
| --- | --- | --- | --- |
| Session restore (`workspace/real_home`) | Centered spinner and checking-session label | Session card | No invented role/navigation before authorization; bounded centered content |
| Store overview (`reports/dashboard_screen`) | Generic AsyncSection spinner | Dashboard hero, permitted metric grid and activity | Same compact page padding; actual AdaptiveGrid minimum widths/role-visible counts |
| Overview trend/best sellers/payment split | Missing chart sections until separate Future resolves | Independent chart blocks | Keep headline/metrics usable; wide best-sellers/payment row at 760, stacked below |
| Products, gallery | 32px-padding spinner | Product gallery rows | Actual `(contentWidth + 16) / 186`, clamped 2–5 columns; 16px gaps |
| Products, list | Same spinner | Product rows/table | Compact cards under existing compact breakpoint, wide columns otherwise |
| Product images in catalog/list/sales/picker/detail | Identical box icon for missing and downloading | Fixed-size/aspect image placeholder | Preserve original dimensions/radius; cached photos should not flash |
| Product detail | Existing product passed by caller; photo/reorder async only | Preserve known details | No artificial page loading |
| Product new/edit reference load | Full centered spinner | Product form | Same 720px max width and labels/inputs; scroll safely at phone/large text |
| Product minimum levels (`reorder_levels_screen`) | Generic AsyncSection spinner | Compact settings rows | Inside existing card, no extra nested card |
| Product “to complete” | Generic AsyncSection spinner | Completion cards | Match row fields/actions, wrap on narrow widths |
| Product picker | Spinner in dialog list | Photo/name picker rows | Existing dialog/search remain; bounded list height |
| Category picker | Spinner in bottom sheet | Category rows | Search/create controls preserved; 48px row targets |
| Category/brand/unit create dialogs | Already known form; save busy state | Excluded: retain save state | No content fetch; prevent duplicate save |
| Stock balances | Spinner below search/filters | Stock table/compact rows | Same cost columns only when permitted, same compact header behavior |
| Movement history | Spinner | Movement rows/table | Preserve search/filter and quantity columns |
| Opening stock/adjustment form | Synchronous draft, picker reads separately | Preserve editable form | Action spinner belongs to posting, not page loading |
| Receiving draft | Local persisted entries; per-line resolving/posting indicator | Preserve draft, row indicator | Do not skeletonize counted quantities or submit operation |
| Receiving product form | Linear indicator while catalog/reference metadata resolves | Small reference-field placeholders | Keep editable name/quantity/prices and entered text; online lookup remains independent |
| Sales product search | Spinner replaces results while searching | Sales result rows | Keep cart and search; match 48px photo and row metadata/price |
| Sales history | Spinner in card | Receipt list rows | Static heading/search preserved |
| Sale detail | Generic AsyncSection spinner | Receipt detail | Same card/line geometry and reserved document actions |
| Checkout/customer entry | Existing form/cart data; confirm busy state | Excluded: retain confirm indicator | No fake read or stock success |
| Customer picker | List spinner | Name/contact rows | Keep search and new-customer form |
| Returns list | Spinner | Return rows | Match list cards and badges |
| Return detail | Generic AsyncSection spinner | Return document | Same detail card widths, line section and controls |
| Return form | Sale supplied by caller; synchronous fields | Preserve known form | Action spinner remains |
| Warranty register | Spinner | Sold-warranty rows | Existing status filters and responsive row content |
| Warranty claims list | Spinner | Claim rows | Same card/list dimensions and status badge |
| New warranty sale search | Spinner | Sale search rows | Keep typed search and independent fields |
| New warranty selected-sale read | Generic AsyncSection spinner | Sale-line selector | Inside existing card, no double surface |
| Warranty detail | Generic AsyncSection spinner | Claim facts/events | Same max width and history row layout |
| Transfer list (retained multi-place compatibility route) | Spinner | Transfer rows | Remains hidden for a single shop; no permission/navigation changes |
| Transfer detail | Generic AsyncSection spinner | Document detail | Match origin/destination/line cards and actions |
| Transfer form | Existing synchronous draft; product picker async | Preserve form | Posting indicator retained |
| Counts list | Spinner | Count rows | Keep filters and new-count controls |
| Count detail/edit | Full spinner on read/reload | Count form/table | Match 820px content and editable row height; retain loaded document during refresh |
| Expenses list | Spinner | Expense rows | Preserve summary/filter and amount alignment |
| Expense form categories | Spinner instead of form | Expense form | Same fields/width and existing category failure handling |
| Expense detail | Generic AsyncSection spinner | Expense facts/file | Same max width/card sections |
| Expense attachment preview | Spinner | Fixed aspect media region | PDF action and failed-download retry retained; no collapse while image decodes |
| Reports summary | Generic AsyncSection spinner | Permission-aware metric grid | Same minimumWidth 150, maxColumns 7, gap 12 |
| Reports summary charts | SizedBox.shrink until data; collapse on failure | Independent chart layout | Same two-card arrangement; terminate with error/retry rather than indefinite skeleton |
| Sales report | Generic AsyncSection spinner | Metrics, chart and report rows | Existing compact/table transformations |
| Stock report | Generic AsyncSection spinner | Metrics and stock report rows | Cost fields remain permission gated |
| Return report | Generic AsyncSection spinner | Metrics and return rows | No skeletonization of static tabs/period selector |
| Expense report | Generic AsyncSection spinner | Metrics and expense rows | Same wrapping/grid proportions |
| Activity feed | Spinner | Avatar/action/time rows | Keep search/action filter and pagination |
| Settings account/appearance/language/password | Profile/preferences already available | Preserve known content | No artificial data load; password submit indicator stays |
| Settings shop profile | AsyncSection spinner | Shop form | Inside current SurfaceCard, preserve draft on section refresh |
| Settings shop/location | AsyncSection spinner | One location row | Owner authorization and single-shop policy unchanged |
| Settings staff | AsyncSection spinner | Staff rows | Existing permissions; rows wrap long names |
| Exchange-rate section | AsyncSection spinner | Rate/current/history lines | Inside current card; input/save remains usable |
| First-sign-in shop questionnaire | Center spinner for shop/team data | Setup form | Existing 560px max width; header/Skip remain visible |
| Store support requests | AsyncSection spinner | Ticket cards | Compose form independent; existing messages/status/errors |
| Platform overview | AsyncSection spinner | Platform KPI/gallery | Actual responsive overview grid, no store navigation invented |
| Platform clients/search/filter | AsyncSection spinner | Client cards | Same gallery columns and status/contact rows |
| Platform client detail | Center spinner | Client facts/history/actions | 760px max width; preserve initial data when passed by caller |
| Platform new client package choices | Empty dropdown additions; load errors swallowed | One reference-field placeholder | Rest of form remains editable; explicit retry without resetting fields |
| Platform renewal package choices | No separate loading state; errors reuse general message | One reference-field placeholder | Preview/confirm remain action-level busy states |
| Platform support ticket list | AsyncSection spinner | Ticket cards | Same status filters and compact rows |
| Platform ticket detail | Center spinner | Message thread/details | 680px max width; compose draft retained |
| Platform announcements | AsyncSection spinner | Announcement cards | Static create dialog preserved |
| Platform settings plans | AsyncSection spinner | Editable plan rows | Account/theme sections remain independent |
| Help/guides/onboarding tips | Static/local content | Excluded | Do not hide available instructions or animate fake loading |
| Onboarding completion bar | Real task-completion progress | Excluded | This is completion status, not a data spinner |
| CSV import preview/apply | Spinner while submitted file is processed | Excluded: retain action indicator | User-triggered operation; existing progress/error/result and all-or-nothing server behavior |
| Scanner permission/start/capture | Native camera/action lifecycle | Excluded: retain camera feedback | A content skeleton would conceal camera permission/manual fallback |
| Authentication/sign-in/TOTP/reset | User-triggered action busy states | Excluded: retain action feedback | Preserve secure flow and normal errors |
| Upload/download/print/export/save/review/post | Appropriate short action indicators | Excluded | Never imply completion before confirmation |
| Demo routes (`screens/`) | Synchronous in-memory data | Excluded | No fake network delay; demo progress is business status |

## Implemented system

- `mobile/lib/widgets/skeleton.dart`: base/text/avatar/image/button/badge plus
  card/table/form/stats/chart/list composites. `SkeletonRegion` provides one
  localized status, hides decorative descendants, ignores interaction and shares
  one repaint-only pulse among nested composites. No dependency was added.
- `features/shared/loading_skeletons.dart`: explicit catalog, stock, product
  editor, document, dashboard, analytics, platform and ordinary form/list layouts.
  Gallery uses the actual 186px column rule; catalog table uses 60/128/53/53 plus
  the two permitted stock columns; platform overview uses eight metric cards.
- Every production `AsyncSection` requires an explicit `loadingBuilder`. Initial
  reads show that layout, refresh retains the same content subtree and draft
  state, failed refresh keeps the previous result with retry. A generation guard
  prevents an older read overwriting a newer one. No timer controls visibility.
- Background loading stays local: dashboard/report charts, references, unit
  choices, receipt files and photos do not cover available sections or drafts.
  Read retries in product/expense forms now actually start another request.
- Photo cache supports synchronous completed-byte reads, preserves LRU behavior,
  deduplicates requests and rejects stale completions after clearing/replacement.
  Image download/decoding reserves existing dimensions; missing/failed product
  photos retain the established box icon. Thumbnail placeholders are static to
  avoid hundreds of independent animation tickers.
- Local preview HTML now retains the original inline filename when gzip is
  negotiated. WebKit otherwise downloaded `index.html.gz` instead of opening the
  app. This was reproduced with/without compression, fixed in the local server,
  and covered by a regression plus real WebKit navigation. Public deployment
  configuration and API/business rules were not changed.
- Product-count subtitle reserves the real font/text-scaling metrics while
  loading. Browser QA caught and fixed a 28px toolbar shift here. Existing page
  shell and navigation remain available. Action spinners remain action spinners.

## Accessibility and performance decisions

Flutter 3.47.6 is a shared native/web application. Its semantics API has no
`aria-busy` property, so this implementation uses `SemanticsRole.status` with the
localized `loading` label and `ExcludeSemantics` for bones. Flutter emits web
`role="status"` (implicitly a polite live region). The pinned framework rejects
combining this role with `liveRegion: true`; using both is invalid. We therefore
use the role alone, instead of injecting browser DOM attributes that would not
work on native clients. Loaded controls return to the normal semantics tree.
Nested regions announce once, not once per placeholder.

The pulse drives `CustomPainter.repaint`; it does not rebuild or relayout the
widget subtree on each frame, use blur/shaders/saveLayer, or create a ticker per
bone. Reduced motion and disabled `TickerMode` stop animation. Light/dark colors
come from the current AppPalette. Existing glass cards/theme/navigation are
preserved. No API, permission, inventory or money calculation changed.

Unknown response length, product-name wrapping, optional expiry/currency lines,
empty results and permission-dependent response fields cannot promise a global
mathematical zero CLS. We reserve known component geometry and preserve available
content. Flutter's canvas also makes a browser DOM CLS score insufficient for
content movement; toolbar/navigation bounding boxes and widget constraints are
checked directly. Do not describe these checks as physical-tablet FPS evidence.

## Verification record

Final local checks on 2026-11-08:

- Pinned Flutter 3.47.6, unchanged dependency lockfile; no added dependencies.
- `flutter analyze --no-pub`: **no issues**.
- `flutter test --no-pub`: **560 passed** (526 before implementation).
- `dart format` applied to changed Dart files; `git diff --check` clean.
- Local static-file tests: **10 passed** (`apps.common.tests.test_local_web`,
  SimpleTestCase, no database access); Ruff checks/format passed for both changed
  Python files.
- Production web build, `--no-web-resources-cdn`: passed, including Wasm dry run.
  This is the ordinary JavaScript web build; a Wasm release is not claimed.
- New `loading_skeleton_test.dart`: RU/TK status semantics, nested decorative
  exclusion, reduced motion, repaint without widget rebuilds, light/dark at
  390/800/1280/1920px with 1.6 text scaling, gallery columns/widths, intrinsic
  dialogs, bounded scrolling pickers, slow read, nullable/empty success, initial
  failure/retry, refresh/draft identity, stale requests and cache-clear races.
- New `loading_routes_test.dart`: actual repository HTTP requests held with
  Completers at four viewport sizes in both themes; shell remains present,
  skeleton lasts until completion and disappears afterward. Covers store and
  platform navigation, report/inventory/warranty/settings tabs, cached claims,
  independent charts, package choices and editable drafts, real form retries,
  and receipt failure/retry without losing expense facts.
- Existing regressions cover catalog/edit/scan, intake/manual intake, stock and
  counts/transfers, sales/customers/returns/warranties, expenses/files, reports,
  settings/setup/support, platform actions, themes, localization and permissions.

### Final route checklist

`D` = real delayed HTTP navigation test at phone/tablet/laptop/desktop sizes;
store paths run in both themes. `R` = existing route regressions plus shared
loading lifecycle tests. `L` = responsive profile/primitive matrix at all four
sizes in both themes. `B` = real browser evidence, recorded separately below.
These codes distinguish route coverage from browser/device coverage; `R/L` is
not a claim that a human opened every detail page on physical hardware.

| Route / component | Desktop/laptop | Mobile/tablet | Loading integration and verification | Status |
| --- | --- | --- | --- | --- |
| Session restore | L | L | Real session state, bounded session card; R | Integrated |
| Store overview | D/L | D/L | Role-aware hero/metrics, real dashboard read; D/R | Integrated |
| Overview trend/best sellers/payments | D/L | D/L | Independent pending/error/retry; available metrics retained | Integrated |
| Catalog gallery | D/L/B | D/L/B | Real products request, exact columns, reserved count subtitle | Integrated |
| Catalog list | L | L | Actual wide column ratios/stock rights; compact image rows; R | Integrated |
| Product thumbnails/full images | L | L | Download/decode bounds, sync cache, missing/failure fallback; R | Integrated |
| Product detail | L | L | Known product stays visible; photo/reorder read locally; R | Integrated |
| Product new/edit | L | L | Editor geometry, wrapping refs/textarea/manual prices, failure/retry; R | Integrated |
| Reorder levels | L | L | Inline settings rows, real AsyncSection read; R | Integrated |
| Products to complete | L | L | Completion rows, real AsyncSection read; R | Integrated |
| Product picker | L | L | Bounded image/name list, search remains; R | Integrated |
| Category picker | L | L | Bounded category rows, search/create remains; R | Integrated |
| Stock balances | D/L | D/L | Real stock request, cost columns only when permitted; D/R | Integrated |
| Movements | D/L | D/L | Real history read; filters remain; D/R | Integrated |
| Receiving product references | L | L | Unit slot placeholder; entered name/quantity/prices retained; R | Integrated |
| Receiving online suggestion | R | R | Existing localized independent lookup status; editable fields remain | Preserved |
| Sales product search | L | L | Image/name/price rows; cart independent; R | Integrated |
| Sales history | L | L | Receipt list, initial pending only; R | Integrated |
| Sale detail | L | L | Document/lines via explicit AsyncSection layout; R | Integrated |
| Customer picker | L | L | Bounded name/contact rows; search/add independent; R | Integrated |
| Returns list | L | L | Initial rows only, existing filter/empty/error retained; R | Integrated |
| Return detail | L | L | Document facts/lines, error/retry; R | Integrated |
| Warranty register | D/L | D/L | Real register read, filters remain; D/R | Integrated |
| Warranty claims | D/L | D/L | Cached tab has no artificial skeleton; filter triggers real read | Integrated |
| New warranty search | L | L | Sale-search rows during actual lookup; R | Integrated |
| New warranty selected sale | L | L | Inline sale lines; R | Integrated |
| Warranty detail | L | L | Claim facts/events, real read; R | Integrated |
| Compatibility transfer list | D/L | D/L | Still gated by existing multi-location permissions; D/R | Integrated |
| Transfer detail | L | L | Document facts/lines; R | Integrated |
| Counts list | D/L | D/L | Real count-list read; D/R | Integrated |
| Count detail/edit | L | L | Form/table initial state, loaded document retained on refresh; R | Integrated |
| Expenses list | D/L | D/L | Real expenses read, filters/totals remain; D/R | Integrated |
| Expense form | L | L | Categories pending/failure/retry; R | Integrated |
| Expense detail | L | L | Real facts read; R | Integrated |
| Receipt image/file | L | L | Fixed media box through download/decode; independent error/retry; R | Integrated |
| Reports summary | D/L | D/L | Real summary request; metrics grid; D/R | Integrated |
| Summary charts | L | L | Separate Future, explicit pending/error/retry; R | Integrated |
| Sales report | D/L | D/L | Metrics/chart/rows; D/R | Integrated |
| Stock report | D/L | D/L | Metrics and stock rows; cost rights unchanged; D/R | Integrated |
| Returns report | D/L | D/L | Metrics/return rows; D/R | Integrated |
| Expenses report | D/L | D/L | Metrics/expense rows; D/R | Integrated |
| Activity feed | D/L | D/L | Pending rows append to retained feed; D/R | Integrated |
| Settings shop profile | D/L | D/L | Form read, same subtree during refresh; D/R | Integrated |
| Settings shop/location | D/L | D/L | Inline location row, existing authorization; D/R | Integrated |
| Settings staff | D/L | D/L | Inline staff rows; D/R | Integrated |
| Exchange-rate section | L | L | Inline current/history rows; save action unchanged; R | Integrated |
| Setup questionnaire | L | L | 560px form, header/Skip remain; R | Integrated |
| Store support | L | L | Ticket read independent of compose form; R | Integrated |
| Platform overview | D/L | D/L | Actual eight-card grid plus income/new-client slots; D/R | Integrated |
| Platform clients/filter/search | D/L | D/L | Actual clients request; D/R | Integrated |
| Platform client detail | L | L | 760px details; supplied initial data stays available; R | Integrated |
| Platform new-client plans | D/L | D/L | Only reference field waits; draft preserved; explicit retry | Integrated |
| Platform renewal plans | L | L | Only reference field waits; preview/confirm remain actions; R | Integrated |
| Platform ticket list | D/L | D/L | Real support read; D/R | Integrated |
| Platform ticket detail | L | L | 680px detail/message layout; compose stays available; R | Integrated |
| Platform announcements | D/L | D/L | Real announcement read; D/R | Integrated |
| Platform plan settings | L | L | Editable plan rows independent of account/theme sections; R | Integrated |
| Settings account/theme/language/password | R | R | Profile/preferences already available; save indicators retained | Excluded: no initial read |
| Known-data checkout/return/transfer/stock forms | R | R | Existing drafts remain; pickers read independently | Excluded: no initial read |
| Receiving draft/posting | R | R | Local persisted quantities preserved, row/action progress retained | Excluded: action state |
| Create-reference dialogs | R | R | Available form; create/save busy indicator retained | Excluded: action state |
| CSV preview/apply | R | R | File-processing action indicator retained | Excluded: action state |
| Authentication/TOTP/reset/save/upload/download/print/export | R | R | Existing operation indicators retained | Excluded: action state |
| Camera startup/permission/capture | R | R | Existing camera feedback/manual fallback retained | Excluded: camera state |
| Guides/help/onboarding completion/demo routes | R | R | Static/local content and real completion progress remain | Excluded: no data wait |

### Browser evidence

**16/16 passed**: Chromium and Playwright WebKit, each at 390×844, 800×1100,
1280×900 and 1920×1080 in both themes. `scripts/e2e/loading.js` used the production
web build, real API and a separate disposable PostgreSQL database on port 8001.
A real product response was held pending, not replaced with a fake response.

Every case verified one localized loading status, completion with actual product
content, unchanged search-toolbar/navigation bounding boxes (0px shift), no
horizontal document overflow and no browser console/page errors. Before/after
screenshots were visually reviewed for phone and desktop layouts. Unknown-length
lists may still change their total scroll extent when the response arrives.

The animated Chromium 1280px light case also sampled 60 animation-frame intervals.
This is a short headless diagnostic, not a performance guarantee for hardware.
The unit test separately verifies that animation does not rebuild content.

Machine-readable results are in `docs/qa/skeleton-browser-results.json`.
Screenshots from this local run are in `/tmp/erp-skeleton-browser/`; rerun the
script to regenerate them. No ordinary shop data, public site, GitHub branch or
deployment was modified by the check.

### Limits

Physical Android tablets/iPhone/iPad, native accessibility services and an Android
APK build are not verified in this environment (Android SDK is absent; this
checkout has Android/web hosts). Browser viewport tests are not physical devices.
No global zero-CLS, fixed FPS, native release or production deployment is claimed.
All application content-read sites in the original inventory are integrated;
remaining hardware validation is explicit. No commit, push or deployment was
performed for this task.
