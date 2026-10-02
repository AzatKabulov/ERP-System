# Design System

Status: Based on the user's supplied **Minimalist Modern** reference and adapted for the Flutter ERP. The prototype under `mobile/` builds for web and Android. Browser checks cover phone/tablet layouts, and widget tests cover doubled text size. Physical-device and iOS accessibility checks remain to be done.

## Brand Direction

Clarity through structure, character through deliberate detail.

The application should feel modern, confident, and approachable: an off-white canvas, crisp white surfaces, deep slate text, and concentrated electric-blue accents. Warm display typography adds personality; operational screens remain clear and efficient.

Use whitespace to group information and emphasize actions. Keep inventory, prices, statuses, and totals easy to scan. The style must support a full working day on a tablet, including frequent data entry and barcode scanning.

### Applying the Reference

| Reference element | Application treatment |
| --- | --- |
| Electric-blue gradient | Signature primary actions and limited brand highlights |
| White cards and soft shadows | Dashboard summaries, forms, and detail panels |
| Inverted slate sections | Optional dashboard spotlight or sign-in brand panel |
| Warm serif headlines | Welcome or overview headlines using a font with both required scripts |
| Monospace accents | SKUs, barcodes, and compact reference numbers |
| Section badges | Meaningful status and context chips |
| Asymmetric layouts | Useful master/detail and sale/cart proportions |
| Floating artwork and rotating rings | Reserved for future promotional material; operational screens use restrained feedback |

Use the reference's visual direction with Flutter widgets and themes. Its React, CSS, Tailwind, shadcn/ui, and Framer Motion examples are not the implementation stack.

The initial theme is light. A slate spotlight panel is a component variation, not a commitment to a complete dark theme.

## Color Tokens

Keep colors centralized. Widgets should consume semantic tokens rather than repeat literal color values.

| Token | Value | Purpose |
| --- | --- | --- |
| `background` | `#FAFAFA` | Main application canvas |
| `surface` | `#FFFFFF` | Cards, sheets, dialogs, and form surfaces |
| `surfaceMuted` | `#F1F5F9` | Secondary panels and quiet fills |
| `textPrimary` | `#0F172A` | Main text and operational headings |
| `textSecondary` | `#64748B` | Metadata and secondary descriptions |
| `primary` | `#0052FF` | Main actions, links, selection, and focus |
| `primaryGradientEnd` | `#3568E8` | Accessible lighter endpoint for white-text primary buttons |
| `accentDecorative` | `#4D7CFF` | Original reference endpoint for decoration without small white text |
| `onPrimary` | `#FFFFFF` | Text on primary actions |
| `primaryTint` | `#EFF6FF` | Selected rows, navigation, and blue-tinted context |
| `borderSubtle` | `#E2E8F0` | Decorative card borders and dividers |
| `borderControl` | `#8291A8` | Visible outlines of enabled input controls |
| `focus` | `#0052FF` | Keyboard and scanner-input focus |
| `inverseSurface` | `#0F172A` | Optional spotlight panel |
| `onInverse` | `#FFFFFF` | Text on slate surfaces |

### Status Tokens

| Status | Foreground | Background | Example |
| --- | --- | --- | --- |
| Success | `#166534` | `#F0FDF4` | Delivery received |
| Warning | `#92400E` | `#FFFBEB` | Low stock or review required |
| Error | `#B91C1C` | `#FEF2F2` | Invalid quantity or failed operation |
| Information | `#1D4ED8` | `#EFF6FF` | Goods in transit |
| Neutral | `#475569` | `#F1F5F9` | Draft or inactive record |

Every status includes a readable label, with an icon where helpful. Color alone must never communicate stock state, approval, or failure. Green and red trends require context; an increase in expenses is not automatically a positive result.

### Gradient and Contrast Rules

- Default primary button gradient: `#0052FF` to `#3568E8`, horizontal or diagonal. Use one shared implementation.
- The reference endpoint `#4D7CFF` gives white text approximately **3.72:1** contrast, below the **4.5:1** target for ordinary text. Keep it decorative or pair it with an appropriately contrasting foreground.
- White text on the adopted primary endpoints gives approximately **5.75:1** and **4.89:1** contrast. Verify actual rendered gradients and all interaction states during implementation.
- `textSecondary` on the canvas gives approximately **4.56:1**; do not reduce its opacity for readable metadata.
- `borderControl` on white gives approximately **3.20:1**. `borderSubtle` is for decoration, not the sole visible boundary of an input.
- Do not brighten gradient buttons on hover if that reduces text contrast. Use a state overlay or controlled shadow instead.

These are calculated token-pair ratios, not an accessibility certification of the future interface.

## Typography

### Font Direction

- **UI and body:** Inter, weights 400, 500, 600, and 700. Verify the bundled files cover Russian Cyrillic and Turkmen Latin; use a verified Noto Sans fallback if necessary.
- **Display:** Noto Serif, weight 600 or 700, for selective welcome and dashboard headlines. The reference's Calistoga is not adopted because its Cyrillic coverage is unsuitable for the required Russian interface.
- **Identifiers:** JetBrains Mono, weights 400 and 500, after verifying the actual font assets. Use tabular figures for aligned financial and quantity columns.

Bundle appropriately licensed fonts as app assets. Do not depend on runtime font downloads. Verify glyph coverage in receipts and PDFs separately from screen rendering.

### Type Scale

Sizes use Flutter logical pixels; line-height values are multipliers. Respect platform text scaling.

| Role | Size | Weight | Line height | Use |
| --- | --- | --- | --- | --- |
| Display | 32, up to 36 in wide layouts | 600–700 | 1.25 | Optional welcome or overview title |
| Page title | 24 | 600 | 1.30 | Products, inventory, sales, reports |
| Section title | 20 | 600 | 1.35 | Card groups and detail sections |
| Metric | 28–32 | 600–700 | 1.20 | Dashboard totals, with room to wrap |
| Body | 16 | 400 | 1.50 | Descriptions and normal content |
| Control label | 14–16 | 500 | 1.40 | Buttons, fields, tabs, and navigation |
| Table text | 14–16 | 400–500 | 1.40 | Operational lists |
| Metadata | 13–14 | 400–500 | 1.45 | Dates, secondary references |

Use sentence case and natural letter spacing for Russian and Turkmen. Avoid uppercase, widely tracked labels as the default. Never shrink text to force a price, translation, or heading into a fixed box.

## Spacing and Layout

Use the shared spacing scale: **4, 8, 12, 16, 24, 32, 48, 64** logical pixels.

- Page padding: 16 in compact layouts; 24 in medium and expanded layouts.
- Card padding: 16 for operational content; 24 for dashboard summaries.
- Related field spacing: 16; major form groups: 24–32.
- Grid gaps: 16–24.
- Enabled touch targets: at least 48 × 48, including icon buttons and embedded row actions.
- Standard input height: minimum 56; allow growth for scaled text and error messages.
- Interactive rows: minimum 56; use 64 or more when showing two lines.

Layout is based on available content width after navigation, safe areas, and the on-screen keyboard. Do not use the reference's large landing-page section padding in operational screens.

Keep tables, filter bars, and forms aligned. Use asymmetric columns only when they serve a task, such as a wider product list beside a narrower sale summary. Avoid decorative overlap near actionable controls.

## Radius, Borders, and Shadows

| Token | Value | Use |
| --- | --- | --- |
| `radiusSmall` | 8 | Inline containers and compact controls |
| `radiusControl` | 12 | Buttons and fields |
| `radiusCard` | 16 | Cards and panels |
| `radiusDialog` | 20 | Dialogs and sheets |
| `radiusPill` | Fully rounded | Status and filter chips |

Borders are normally 1 logical pixel. Focus uses a clearly visible 2-pixel outline with separation where needed.

Flutter `BoxShadow` starting values:

| Shadow | Color and opacity | Offset | Blur | Use |
| --- | --- | --- | --- | --- |
| Quiet | Slate `#0F172A`, 6% | (0, 2) | 8 | Dashboard cards |
| Raised | Slate `#0F172A`, 10% | (0, 8) | 24 | Dialogs and floating panels |
| Accent | Blue `#0052FF`, 16% | (0, 4) | 12 | Limited primary-action emphasis |

Use borders without shadows for dense lists. Keep dot textures and blue glows confined to an optional brand or spotlight panel, away from text and controls. Avoid expensive backdrop blurs in scrolling data views.

## Application Shell and Navigation

- **Expanded layout:** labeled side navigation, with the selected module highlighted using a blue tint and a clear indicator.
- **Medium layout:** navigation rail with labels where they fit; provide an accessible overflow or drawer for all permitted modules.
- **Compact layout:** the initial prototype uses a labeled menu button and drawer containing all modules. A future primary navigation bar plus More may be added after task-based device review. All permitted modules remain reachable.
- Keep the current store or warehouse visible near the page heading and sales context. Switching locations must handle unsaved work explicitly.
- Provide language selection using `Русский` and `Türkmençe`, with the current choice clear.
- Keep global navigation separate from page-level tabs and filters.
- Show destinations according to permissions, while retaining backend authorization checks.

## Components

### Buttons

- Primary: accessible blue gradient, white text, 12-pixel radius, minimum 48-pixel height.
- Secondary: white or muted surface, visible outline, slate text.
- Text or ghost: restrained text action with a full touch target.
- Destructive: error styling with a specific label explaining the action.
- Use one dominant primary action per task area. Labels name the action, such as receiving a delivery or completing a sale.
- Submission shows progress and prevents accidental duplicate taps. Preserve entered work on failure.

### Fields, Search, and Scanning

- Persistent labels; placeholders supplement rather than replace them.
- Put helper and validation text directly beneath the field. Explain how to correct an error.
- Product search supports names, SKU, and barcode entry. Give scanning a labeled action and keep manual lookup available.
- Keep scanner or keyboard focus deliberate and visible. Receiving a scan must not unexpectedly submit a form, finalize a sale, or move stock.
- Numeric fields make units and currency clear. Validation and parsing must support the selected locale.

### Cards, Metrics, and Charts

- White cards, subtle borders, restrained shadows, and consistent title/value placement.
- Financial cards show currency, period, and location context. A missing value is not displayed as zero.
- Give one important overview card a slate treatment where appropriate. Avoid turning every card into a gradient feature.
- Charts show labels, units, and an accessible summary or table. Trends describe their comparison period.

### Tables and Lists

- Keep names left-aligned and quantities and money consistently aligned with tabular figures.
- Use clear column headings, a quiet header surface, row separators, and a visible selected state.
- Support search, relevant filters, sorting, and pagination or incremental loading appropriate to the data source.
- In compact layouts, show prioritized fields in cards or list rows and expose full details on selection.
- Where a wide comparison table remains necessary, provide intentional horizontal scrolling without trapping page navigation.
- Row actions have labeled controls or an accessible menu; important actions are not available only through a swipe or hover.

### Status Chips and Feedback

- Pills use the semantic status foreground and background, an explicit label, and optional icon.
- Information badges never imply a record has been saved or synchronized unless that state is verified.
- Routine confirmations may use a snackbar with a relevant next action. Persistent failures use an inline message or banner with retry where appropriate.
- Approval-required states explain the next step without granting unauthorized actions.

### Dialogs and Sheets

- Use dialogs for short confirmations and decisions; use full pages or roomy sheets for long forms.
- Refund and stock-adjustment confirmations show the affected items, quantities, location, and financial or stock consequence.
- Support keyboard focus, back navigation, and explicit cancellation. Preserve drafts appropriately and do not hide required fields behind the keyboard.
- Never rely solely on a dialog to enforce a business policy or permission.

## Screen Patterns

| Area | Visual and interaction pattern |
| --- | --- |
| Dashboard | Context filters, responsive metric grid, low-stock list, recent activity |
| Products | Search and scan toolbar, product list, detail/edit panel |
| Inventory | Visible location, balances and movement history, clear receiving/transfer/count actions |
| Purchasing | Order list with statuses, line-item details, received and outstanding quantities |
| Sales | Product lookup beside a cart and totals when space permits; distinct finalize action |
| Returns | Original-sale context, eligible quantities, item condition, refund summary |
| Physical counts | Location and count context, count-entry rows, variance review before adjustment |
| Reordering | Suggested quantities and stock context, review and purchase-order action |
| Expenses | Filterable expense list, short entry form, receipt attachment preview |
| Warranties | Original-sale context, entitlement summary, claim history and resolution |
| Reports | Date/location filters, labeled totals, table or chart, permitted export action |
| Administration | Grouped settings for business, locations, roles, language, import/export, and recovery |

Imports show preview, errors, and a clear apply step. Recovery screens communicate the administrator's intended action and remain separate from ordinary stock operations. Exact approval and recovery policies come from the PRD and later architecture decisions.

## Interaction States

| State | Required behavior |
| --- | --- |
| Default | Clear label, stable geometry, readable contrast |
| Hover | Optional pointer feedback without movement of dense rows |
| Focus | Visible outline and sensible traversal; not dependent on hover |
| Pressed | Brief tint or state overlay; small scale feedback only where it does not move nearby controls |
| Disabled | Clear unavailable state and a reason when needed; no hidden active hit area |
| Loading | Relevant progress indicator or stable skeleton; retain context |
| Empty | Explain the absence of records and offer a permitted next action |
| Error | Specific localized message, retained input, and a suitable recovery action |
| Success | Confirm the completed backend operation and show updated state |
| Offline or stale | Persistent understandable indication; stock-changing actions unavailable in the initial version |

Skeletons must not imply actual records exist. Failed requests must not produce success colors, changed stock totals, or misleading receipts.

## Motion

- Press and focus feedback: approximately 100–150 ms.
- Panels, selection transitions, and dialogs: approximately 180–240 ms using ease-out curves.
- Keep scroll performance smooth on the selected Android tablet. Avoid recurring animation in tables, metric values, or scanning controls.
- Honor platform reduced-motion settings. Disable decorative motion and shorten nonessential transitions.
- Use Flutter's implicit animations for simple transitions; introduce an animation package only for a demonstrated need.
- Rotating rings, floating hero artwork, and constant pulsing are not part of the initial operational interface. A status indicator must reflect an actual state rather than simulate live activity.

## Responsive Rules

Starting breakpoints use available Flutter logical width and may be adjusted after testing:

| Width | Layout |
| --- | --- |
| Under 600 | Compact: stacked forms, simplified lists, menu and drawer |
| 600–839 | Medium: rail or drawer, adaptive one/two-column panels |
| 840 and above | Expanded: labeled navigation and suitable master/detail layouts |

Dashboard grids adapt to card content, usually one or two columns in compact layouts and up to four with sufficient width. Prefer wrapping to shrinking values.

Sales uses product/cart panels only when both retain usable width. In compact layouts, the cart is a clearly reachable page or panel with item count and totals. A checkout action must remain reachable without covering fields or validation messages.

Use safe areas and keyboard insets. Preserve drafts, selection, and scroll position where appropriate across rotation and layout changes. Test tablet portrait, landscape, and iPad split-view widths.

## Russian and Turkmen Requirements

- All user-facing system labels and feedback use the localization resources required by `AGENTS.md`.
- Test complete Russian and Turkmen screens, not just translated headings. Do not force English-length widths on navigation, buttons, or fields.
- Verify `Ёё` and Turkmen characters including `Ää`, `Çç`, `Ňň`, `Öö`, `Şş`, `Üü`, `Ýý`, and `Žž` in bundled fonts and document output.
- Product names and identifiers retain their stored spelling when the interface language changes.
- Interface language and receipt/invoice language are independent settings. Use the configured currency; do not infer it from the selected language.
- Translation and business terminology review by fluent speakers remains required before release.

## Accessibility

- Target at least 4.5:1 contrast for ordinary text, 3:1 for eligible large text, and 3:1 for meaningful non-text controls against adjacent surfaces.
- Use at least 48 × 48 logical-pixel touch targets on both platforms. Keep adjacent controls sufficiently separated.
- Test substantial text scaling, including approximately 200%, without clipped actions or inaccessible content. Let layouts reflow or scroll.
- Provide Flutter semantics for icon actions, quantities, selected states, chart summaries, and form errors. Exclude decorative graphics from screen-reader navigation.
- Test TalkBack on Android and VoiceOver before the Apple release, along with keyboard/scanner focus and navigation.
- Do not require color perception, animation, hover, or gestures without an alternative to complete a task.
- Announce important validation or completion feedback appropriately without repeatedly reading the entire screen.

## Flutter Implementation Guidance

- Centralize the semantic palette in `ThemeData`/`ColorScheme` and additional tokens in typed `ThemeExtension` values where needed. Use one shared `TextTheme` and component theme set.
- Implement the primary gradient in a reusable button that preserves Material feedback, semantics, focus, disabled states, and minimum target size.
- Build shared primitives for page headers, location selection, search/scan fields, status chips, metric cards, table/list rows, form sections, error panels, and empty states.
- Use `LayoutBuilder` and available constraints for responsive decisions. Do not lock orientation or disable text scaling to make layouts fit.
- Keep widgets independent of direct database access and stock calculations. UI composition follows the future architecture document; the backend remains authoritative.
- Bundle fonts and asset licenses. Use a consistent icon family with accessible labels rather than mixing styles.
- Use realistic fixtures clearly identified as demonstration data in any prototype. Prototype sales, stock, or backups must never be presented as working backend operations.

## Review Checklist

- Compare dashboard, products, inventory, and sales against this specification before expanding to the other modules.
- Check both languages, long names, large totals, portrait and landscape, narrow layouts, and scaled text.
- Exercise loading, empty, error, disabled, offline, and success states without losing drafts.
- Measure the final control and text contrast, including gradients and interaction overlays.
- Test scrolling, focus, actual scanning hardware, and representative printed/PDF output on the chosen devices.
- Verify that all agreed features remain discoverable and permission restrictions remain clear.

This document defines the intended frontend direction. Compliance must be demonstrated by the implemented widgets, accessibility checks, and device validation rather than inferred from these tokens alone.
