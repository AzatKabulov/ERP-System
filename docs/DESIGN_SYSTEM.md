# Design System

Status: Implemented in the Flutter app from the owner's **"Premium Minimalist ERP UI"** Figma Make mock-up (2026-10-14). The mock-up's palette, type, shell, page layout and components were adopted as they are; only names, sections and content were tailored to this product (our own module list, no Purchasing, our fields). It replaces the earlier "Minimalist Modern" blue-gradient direction. The app builds for web and Android; browser checks cover phone (390), tablet (820) and desktop (1440) widths, and widget tests cover doubled text size. Physical-device and iOS accessibility checks remain to be done.

## Direction

Calm, precise and expensive-looking: a warm ivory canvas, white surfaces with hairlines and a very soft two-layer shadow, ink-black text, **one** flat cobalt accent for actions, and a **thin brass** detail used only as decoration (a hairline, the selected-tab marker). One figure per page may sit on an ink "spotlight" surface. Headlines are serif; everything operational is Inter; codes are monospace.

Not used (by design): gradients on buttons, glows, dot textures, floating or pulsing artwork, glass blur in data views.

## Color Tokens

Defined once in `mobile/lib/theme/app_theme.dart` (`AppColors`). Widgets use the names, never literal colors.

| Token | Value | Purpose |
| --- | --- | --- |
| `canvas` | `#F5F2EC` | Page background |
| `surface` / `surfaceSoft` | `#FFFFFF` / `#FAF8F4` | Cards, table headers, quiet fills |
| `ink` | `#0D1311` | Text, the spotlight surface, the avatar |
| `muted` | `#5D6561` | Secondary text |
| `line` / `lineStrong` | `#E4DFD5` / `#CBC4B8` | Card borders and dividers / hover border |
| `control` | `#8E887B` | Outline of an enabled input (about 3.2:1 on white). The mock-up uses `line` here; the darker warm gray keeps fields visible per the accessibility rule |
| `blue` / `blueDark` | `#1740FF` / `#1234D6` | Primary action, links, focus, current tab; darker on hover |
| `tint` | `#EAEEFF` | Soft blue fill (info badge, current phone tab) |
| `brass` | `#B08D57` | Decoration only: hairlines, the current-item marker. Never text or a main action |
| `onInverse` / `onInverseMuted` | `#FFFFFF` / `#B9C0BC` | Text on ink |

Status colors (foreground / soft background): success `#14703B` / `#E8F4EC`, warning `#8C5300` / `#FFF4E0`, error `#B3261E` / `#FDECEA`, info = `blue` / `tint`, neutral `#4B544F` / `#EEEBE4`. Every status has a label and, where useful, an icon. Color alone never carries meaning; trends need context.

## Typography

- **UI and body:** Inter (bundled).
- **Display:** Noto Serif, weight 600, for page titles, the spotlight figure, dialog titles and the sign-in headline. The mock-up's Noto Serif Display is replaced by the bundled Noto Serif, which covers Russian and Turkmen.
- **Identifiers:** JetBrains Mono for SKUs, barcodes and document numbers. All three fonts were checked for Russian and the Turkmen letters.
- Digits in money and quantities are tabular. Numeric table cells are right-aligned.

| Role | Size | Notes |
| --- | --- | --- |
| Spotlight figure | 52 (34 on a phone) | Serif, tight tracking |
| Page title | 28 (24 on a phone) | Serif |
| Dialog title | 24 | Serif |
| Section title | 16 | Inter 600 |
| Metric | 24 | Inter 600, tabular |
| Body | 14 | |
| Label / table text | 13 | |
| Eyebrow, table header | 11–12 | Inter 700, uppercase, wide tracking |
| Metadata | 12 | |

## Spacing, Radius, Shadow

- Spacing scale 4, 8, 16, 24, 32, 40, 48, 64. Page padding 32 (16 on a phone); the page content is centred and limited to 1500.
- Radius: card 14, control 12, dialog 18, badge and chip pill, top-bar controls 10.
- Card shadow: `0 1 2` at 4% plus `0 8 24` at 5% ink. Overlays use a larger, softer shadow.
- Minimum touch target 48 × 48.

## Application Shell

- **Wide and tablet (768 and above):** a white side navigation, 216 wide (196 under 1200): the brand square and name, the modules as 48-pixel items (the current one on a soft neutral fill with a brass marker), and the signed-in person (initials avatar, name, role) with sign-out at the bottom.
- **Phone (under 768):** no side navigation. A bottom bar of four modules (overview, products, sales, stock) with the current one on a soft blue fill, and a menu button that opens a drawer with every module and sign-out. The bar steps aside while the keyboard is open.
- **Top bar:** the page name, then the location, the RU | TM switch and (on wide screens) the role. On a phone the location moves to a second row.
- Show only the modules a role may use; the server stays the authority.
- Page decisions use available width (`LayoutBuilder`), never `MediaQuery` size: a page beside a side navigation is narrower than the window, and the widget tests resize the surface, not the view.

## Shared Primitives

In `mobile/lib/widgets/common.dart` (tokens in `app_theme.dart`). Screens use these, not one-off styling.

| Primitive | Use |
| --- | --- |
| `PageHead` | Eyebrow, serif title, subtitle and the page's actions (below the title on a narrow page) |
| `SurfaceCard` | White card, hairline, soft shadow; with `onTap` it is a button (stronger border on hover) |
| `PrimaryButton` | The main action: flat cobalt, darker on hover, press scale 0.98, a separated focus ring. Secondary actions are the theme's outlined button, quiet ones the text button |
| `StatusPill` | Soft tone badge with icon and label |
| `MetricCard` | Label on top, the figure and a note below |
| `SpotlightCard` | The ink surface with a brass hairline: one per page, for the figure that matters most |
| `Glyph`, `BrandMark` | An icon on a soft square (list rows); the brand square |
| `Eyebrow` | Small uppercase label |
| `AppSegmented`, `AppTabs` | The soft segmented switch (RU \| TM, gallery \| list); underlined tabs for a page's sections |
| `TopbarControl`, `FilterSelect` | Selector boxes and drop-down filters |
| `NoticeBanner` | Info, warning, error and success strips |
| `EmptyState` | Calm line icon in a circle, one sentence, a hint |
| `FadeUp` | A page's content arriving: 180 ms fade with a 4 px rise, skipped when reduced motion is on |

Material chips are themed to the design: a pill with a hairline; the selected chip gets an ink outline and a brass line along its bottom edge. Inputs are 48+ high with 12 radius and a cobalt focus outline. Dialogs use radius 18 and a serif title.

## Screen Patterns

| Area | Pattern |
| --- | --- |
| Overview | Page head with the greeting; today's sales on the ink spotlight; the other figures as metric cards; recent activity as a card of rows with a glyph, the action, and who and when |
| Products | Page head with import, export, "to complete" and Add product; search with scan, category chips, gallery \| list switch. The list is a table (article in mono, name with barcode, category and brand, price); the gallery is cards with the picture |
| Stock | Page head with the receiving actions; search and location chips; a table (product, location, condition badge, quantity, value) |
| Sales | Page head with history and returns; a workbench: product search and results in one card beside the cart card; large total and the payment choice |
| Expenses, Warranties | Page head with the add action, filter chips, one card of rows with a glyph and a badge |
| Reports | Page head, period chips and location filter, underlined tabs, metric cards; the sales tab also draws revenue by day as a thin cobalt line from the report's own rows |
| Settings | Page head and cards per area |

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

100–180 ms for hover, press and the page's arrival (ease-out). No recurring animation in tables, figures or scanning controls. Reduced motion removes the arrival fade.

## Russian and Turkmen

- All user-facing text comes from the localization files (`AGENTS.md`). The RU | TM switch is in the top bar and on the sign-in page.
- Uppercase eyebrows and table headers are used as in the mock-up (Turkmen has no dotted capital İ, so plain uppercase is correct).
- Verify `Ёё` and `Ää Çç Ňň Öö Şş Üü Ýý Žž` in every font and in documents. Product names and identifiers keep their stored spelling.
- Interface language and receipt language are independent. The currency is configured, never inferred from the language.
- Translation and terminology review by fluent speakers is still required.

## Accessibility

- Text at least 4.5:1 on its surface; the muted text on the canvas is about 5.4:1. Brass is never used for text.
- Enabled input outlines are at least 3:1 (`control`); the card hairline `line` is decoration.
- Touch targets at least 48 × 48. Test text scaling to 200%; layouts reflow or scroll.
- Semantics for icon actions, selected tabs and segments, quantities and form errors; decorative marks are excluded.
- Do not rely on color, animation, hover or gestures alone; every action is reachable by tap and keyboard.

## Review Checklist

- Compare Overview, Products, Stock, Sales and Reports with the mock-up at phone, tablet and desktop widths.
- Both languages, long names, large totals, portrait and landscape, doubled text.
- Loading, empty, error, disabled, offline and success states without losing drafts.
- Real scanning hardware and printed or PDF output on the chosen devices.

This document describes the intended frontend. Compliance is shown by the implemented widgets, the tests and device checks, not by the tokens alone.
