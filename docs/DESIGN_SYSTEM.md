# Design System

Status: Implemented in the Flutter app. The structure and module list come from the owner's "Premium Minimalist ERP UI" Figma Make mock-up (2026-10-14). On **2026-11-06** the owner asked for a premium, glass look and a dark theme; the surface, colour, depth and motion were redone for that (branch `feature/premium-design`) and the layout was kept. The app builds for web and Android; browser checks cover phone (393), tablet (1024) and desktop (1440) widths in both schemes, and widget tests cover doubled text size and both schemes' contrast. Checks on a physical Android tablet and an iPhone remain to be done.

## Direction

Calm, precise and expensive-looking: a **cool, luminous field** (pale blue-grey in the light scheme, ink-blue in the dark one) with three soft pools of colour behind **frosted glass** panes, deep navy-ink text, **cobalt** for action and selection, and a small set of accents that each have one job. The one deep surface (the spotlight and the sign-in panel) runs navy into cobalt. Motion explains state: things arrive, switches glide, figures count up.

Phone/tablet performance update (2026-10-27): below a 1000-pixel viewport, data and
charts appear immediately. Skip decorative page fades, staggered card arrivals,
counting figures and chart draw-in; keep short press/selection feedback. The
compact-tablet path showed lower navigation work in the local CPU-throttled
control; wider layouts retain their entrance behavior. Palette,
typography, layout and available features stay consistent with the wide interface.

The brand mark (a blue-to-violet square with an "E") is kept and the interface is built around it. No gold or brass anywhere.

Where glass is used, and where it is not:

| Glass (blurred, translucent) | Opaque or near-opaque |
| --- | --- |
| The side navigation, the top bar, the phone's bottom bar | Text fields (a little more solid than the glass they sit on) |
| Cards, sheets, dialogs, menus | Table rows inside a card (the card is the glass) |
| The sign-in form | The spotlight (navy to cobalt) |

Glass never carries small text over a busy backdrop: a dialog or menu uses the denser veil (`glassStrong`). Long lists draw the veil and rim only (no blur per row), which keeps scrolling smooth on a phone.

Not used (by design): decorative gradients elsewhere (gradients appear only on the brand mark, the primary button, the spotlight and the chart fills), gradient text, dot textures, floating or pulsing artwork, looping animation, eyebrow labels above titles.

## Two schemes

Light and dark are two designed palettes, not an inversion. They are the same names with different values (`mobile/lib/theme/app_palette.dart`). The scheme is chosen in **Settings → Appearance**: *As on the phone*, *Light* or *Dark*. **Until the person chooses, the app is light** (owner, 2026-11-06), whatever the phone is set to. The choice is kept on the device (`theme.mode`).

Switching repaints the running app in place: nothing is rebuilt from scratch, so a half-filled cart or form survives. Web and Android chrome (splash, status bar, theme colour) follow the palette.

## Color Tokens

Defined once in `mobile/lib/theme/app_palette.dart` and read through `AppColors` in `app_theme.dart`. Widgets use the names, never literal colors (the only literal `Colors.white` left is text on a cobalt or navy fill).

| Token | Light | Dark | Purpose |
| --- | --- | --- | --- |
| `canvas` / `canvasEdge` | `#EEF1F8` / `#E4E9F5` | `#090C16` / `#060810` | Page field, top to bottom |
| `surface` / `surfaceSoft` / `surfaceMuted` | `#FFFFFF` / `#F6F8FC` / `#E7EBF4` | `#131829` / `#0F1322` / `#1B2136` | Opaque fills: fields, table headers, quiet fills |
| `ink` | `#0B1020` | `#EDF0FA` | Text |
| `muted` / `neutral` | `#556079` / `#3C455C` | `#9AA3BC` / `#C3CADF` | Secondary text / strong secondary text |
| `line` / `lineStrong` | `#DCE1ED` / `#C3CADB` | `#252C45` / `#353F61` | Hairlines / hover border |
| `control` | `#858EA6` | `#6C7794` | Outline of an enabled input (at least 3:1) |
| `blue` / `blueDark` | `#1740FF` / `#1234D6` | `#8197FF` / `#6C86FF` | Action text, links, focus, current item |
| `blueFill` / `blueFillDeep` | `#2F57FF` / `#1740FF` | `#4765FA` / `#3552F0` | Primary button fill (white text on it) |
| `tint` | `#E6EBFF` | `#1B2552` | Soft cobalt fill |
| `violet` / `violetTint` / `violetText` | `#6A4DFF` / `#EDE9FF` / `#4A32C9` | `#9B86FF` / `#262058` / `#B7A8FF` | Profit, warranties, customers; second chart series |
| `emerald` / `emeraldTint` | `#0FA36B` / `#DFF4EB` | `#2FD39A` / `#0F2F28` | Money in, stock value |
| `amber` / `amberTint` | `#F5A300` / `#FFF0CC` | `#FFB93D` / `#3A2E12` | Attention: low stock, to complete |
| `rose` / `roseTint` | `#E5484D` / `#FFE7E8` | `#FF6E72` / `#3A1B20` | Money out, returns |
| `success` / `warning` / `danger` (+ `…Tint`) | `#14703B` / `#8C5300` / `#B3261E` | `#5BDB9B` / `#F7B955` / `#FF8A84` | Status text on its own tint |
| `glass` / `glassStrong` | white 72% / white 88% | `#161C33` 62% / `#121730` 88% | Veil of a pane / of a pane that carries text |
| `glassEdge` / `glassHighlight` | white 60% / white | white 20% / white 40% | The rim: bright at the top, fading |
| `shadow`, `scrim` | `#111A3B`, ink 42% | black, `#050711` 60% | Shadow colour, veil behind a dialog |
| `orbBlue` / `orbViolet` / `orbTeal` | cobalt, violet, teal at ~13–20% | the same, a little stronger | The three pools of colour behind the glass |
| `navy` / `navyMid` | `#0A1030` / `#14226B` | (same) | The deep surface and the end of the brand gradient |

The strong shade of an accent is for icons, chart marks and tiles; text uses the status colours, which meet 4.5:1 on their tint. Colour is never the only carrier: each use also has a label or an icon.

`test/features/theme_test.dart` computes the contrast of both schemes: ink, muted and neutral text at least 4.5:1 on every surface (canvas, glass over canvas, opaque surfaces); cobalt and each status colour on their tint at least 4.5:1; white on the primary button at least 4.5:1; the field outline at least 3:1 on its surface.

## Typography

- **One family: Onest** (bundled, variable weight 100-900, SIL Open Font License). It reads clearly at small sizes in Russian and Turkmen (checked for the letters ä ç ň ö ş ü ý ž and for ё and №) and has figures that line up in columns.
- **Headings and figures:** the same family, weight 700, slightly tight tracking.
- **Identifiers** (SKUs, barcodes, document numbers): Onest with tabular figures, muted.
- Digits in money and quantities are tabular. Numeric table cells are right-aligned.
- No eyebrow labels above titles, no gradient text. A table header or caption is set in sentence case or small caps-height uppercase only where it labels a column.

| Role | Size | Notes |
| --- | --- | --- |
| Spotlight figure | 50 (36 on a phone) | 700, tight tracking, counts up |
| Page title | 34 (28 on a phone) | 700 |
| Dialog title | 24 | 700 |
| Card title | 17 | 700 |
| Metric | 26 | 700, tabular |
| Body | 15 | |
| Label / table text | 13-14 | |
| Table header, caption | 11-12 | 700 |

## Spacing, Radius, Depth

- Spacing scale 4, 8, 16, 24, 32, 40, 48, 64. Page gutter 32 (16 on a phone); content is centred and limited to 1500. Pages scroll **beneath** the floating bars: `pagePadding(context, compact:)` adds the bars' height to the top and bottom padding (`ChromeInsets`), so nothing is hidden at rest.
- Radius (`AppRadius`): small 8, control 14, card 16, dialog 22; the side navigation 24; badges and chips are pills.
- Depth (`AppShadows`): `card` (two layers), `cardHover`, `float` (bars, sheets), `overlay` (dialogs). Declared once; a surface is never given two shadows. In the dark scheme shadows are deeper and the rim carries the edge.
- Minimum touch target 48 × 48.

## Application Shell

- **Tablet and computer (768 and above):** a floating glass side navigation (224 wide, 204 under 1200, 12 from the edges, radius 24): the brand mark and name, the modules as 48-pixel items (the current one on a soft cobalt wash), and the signed-in person with sign-out at the bottom. The top bar is one pane of glass with a hairline along its lower edge (no box): the page name, the shop, the RU | TM switch, help and the role.
- **Phone (under 768):** a floating glass bottom bar with four modules (overview, products, sales, stock) and **More**, which opens a sheet with expenses, warranties, reports, settings, help and sign-out. The bar's labels grow with the system text size up to 1.3×, as Material's do. A slim top row has the shop and help; the language is set once, in Settings. The bar steps aside while the keyboard is open.
- Show only the modules a role may use; the server stays the authority.
- Page decisions use available width (`LayoutBuilder`), never `MediaQuery` size: a page beside a side navigation is narrower than the window, and the widget tests resize the surface, not the view.

## Shared Primitives

In `mobile/lib/widgets/` (tokens in `app_theme.dart`). Screens use these, not one-off styling.

| Primitive | Use |
| --- | --- |
| `GlassSurface` (`glass.dart`) | A pane of frosted glass: blur, veil, lit rim, shadow. `strong` for text over busy content; `rim: false` for a bar that runs edge to edge; `blur: 0` for a card in a long list |
| `AmbientField` | The field behind every screen: the page colour with three soft pools. Screens' own backgrounds are transparent |
| `PageHead` | Title, subtitle and the page's actions (below the title on a narrow page; up to 80% of the width on a wide one, the main action last, at the right) |
| `SurfaceCard` | A card of glass; with `onTap` it is a button that rises 2 px with a cobalt-tinted edge on hover and sinks when pressed |
| `PrimaryButton` | The main action: a cobalt gradient with a soft glow, deeper on hover, press scale 0.98, a separated focus ring. Secondary actions are the theme's outlined button, quiet ones the text button |
| `StatusPill` | Soft tone badge with icon and label |
| `MetricCard`, `AdaptiveGrid` | Label and a coloured icon tile, the figure and a note; the grid picks the column count that leaves the last row fullest (six cards sit 3 + 3) |
| `SpotlightCard` | The navy-to-cobalt surface with soft glows: one per page, for the figure that matters most |
| `Glyph`, `BrandMark` | An icon on a soft square (list rows); the brand square |
| `AppSegmented`, `AppTabs` | The soft segmented switch (gallery \| list, theme); tabs for a page's sections (they fade at the edge when they scroll) |
| `TopbarControl`, `FilterSelect` | Selector boxes and drop-down filters |
| `NoticeBanner` | Info, warning, error and success strips |
| `EmptyState` | Calm line icon in a circle, one sentence, a next step |
| `FadeUp` / `Reveal` | Content arriving: a fade with a short rise, staggered by `index`, skipped when reduced motion is on |

Material chips are themed to the design: a pill with a hairline; the selected chip turns cobalt. Inputs are 48+ high with radius 14, a slightly more solid fill than the glass behind them in both schemes, and a cobalt focus outline. Dialogs and sheets are glass with radius 22, a bold title and the denser veil. A list row's "add" control is a round tonal button at the end of the row.

## Screen Patterns

| Area | Pattern |
| --- | --- |
| Overview | Greeting; the first-run checklist while it is unfinished; today's sales on the spotlight; the other figures as metric cards; best sellers and payment split; recent activity |
| Products | Page head with the main action; search with scan; gallery \| list; filters as chips. The list is a table; the gallery is cards with the picture |
| Stock | Page head with the receiving actions (scan receiving is the main one); tabs for balances, history, counts; search and condition chips; a table (product, place, condition badge, quantity, value) |
| Sales | A workbench: product search and results in one card beside the cart card; large total and the payment choice |
| Expenses, Warranties | Page head with the add action, filter chips, one card of rows with a glyph and a badge |
| Reports | Page head, period chips and place filter, tabs, metric cards; the sales tab also draws revenue by day from the report's own rows |
| Settings | Tabs (account, shop, staff); cards per area; **Appearance** (theme) and language |

Imports show a preview, errors and a clear apply step. Recovery screens stay separate from ordinary stock operations.

## Interaction States

| State | Behavior |
| --- | --- |
| Hover | Subtle: a stronger border, a row tint, a darker primary button. No movement of dense rows |
| Pressed | Brief overlay; the primary button scales to 0.98 |
| Focus | A visible outline or ring, never dependent on hover |
| Disabled | The primary button fades to about 40%; other controls use the muted fill |
| Loading, empty, error | A progress indicator that keeps the page; a calm empty state with a next step; a specific message with retry |
| Offline or pending | A persistent banner; success is shown only after the server confirms |

Failed requests never produce success colors, changed totals or misleading receipts.

## Motion

Defined in `mobile/lib/widgets/motion.dart` (`AppMotion`, `Reveal`, `CountUp`, `PressScale`). Durations: 140 ms feedback, 240 ms a change of state, 420 ms an arrival; easing is a confident exponential ease-out. Everything honours the system's "remove animations" setting: with it on, content simply appears.

- Below a 768-pixel viewport (owner, 2026-10-26) data and charts appear immediately: no page fades, staggered arrivals, counting figures or chart draw-in; short press and selection feedback stays.
- A page change plays only the new page (a fade and a 1.5% rise); the old page is gone at once, so nothing overlaps and nothing waits.
- Groups arrive one after another (`Reveal`, at most 8 steps of 55 ms).
- The switch (`AppSegmented`) has a thumb that glides; tabs, navigation items and the bottom bar fade their colours; chips and cards respond to hover and press.
- The spotlight figure counts up once; charts draw themselves once; the line chart names the day under the pointer or finger.
- Dialogs scale in from 94%; empty states pop in.
- A change of scheme repaints at once; there is no looping or ambient animation anywhere.

Widget tests run with reduced motion on (see `RealRig.launch`); `test/features/motion_test.dart` covers the animated paths.

## Charts

In `mobile/lib/widgets/charts.dart`: `AreaChart` (a line with a gradient fill, interactive), `BarList` (horizontal bars with the figure on the row), `DonutChart` (shares of a whole, round ends with a clear gap). They draw from the data the reports already return; nothing is invented. Tooltips invert the scheme (dark on light, light on dark).

## Russian and Turkmen

- All user-facing text comes from the localization files (`AGENTS.md`). The RU | TM switch is in the top bar on wide screens, in Settings on a phone, and on the sign-in page.
- Verify `Ёё` and `Ää Çç Ňň Öö Şş Üü Ýý Žž` in every font and in documents. Product names and identifiers keep their stored spelling.
- Interface language and receipt language are independent. The currency is configured, never inferred from the language.
- Translation and terminology review by fluent speakers is still required.

## Accessibility

- Text at least 4.5:1 on its surface in both schemes (tested). Enabled input outlines at least 3:1 (`control`); the card hairline `line` is decoration.
- Touch targets at least 48 × 48. Test text scaling to 200%; layouts reflow or scroll.
- Semantics for icon actions, selected tabs and segments, quantities and form errors; decorative marks are excluded.
- Do not rely on color, animation, hover or gestures alone; every action is reachable by tap and keyboard.
- Glass keeps its contrast because text sits on a veil that is dense enough over the field's soft pools; a pane that carries small text uses the denser veil.

## Review Checklist

- Check every new or changed screen against the rules in [USABILITY.md](USABILITY.md).
- Look at it in **both schemes** and at phone, tablet and desktop widths; nothing white in the dark scheme, nothing unreadable in the light one.
- Both languages, long names, large totals, portrait and landscape, doubled text.
- Loading, empty, error, disabled, offline and success states without losing drafts.
- Real scanning hardware and printed or PDF output on the chosen devices.
- A new colour goes into both palettes and into the contrast test.

This document describes the intended frontend. Compliance is shown by the implemented widgets, the tests and device checks, not by the tokens alone.
