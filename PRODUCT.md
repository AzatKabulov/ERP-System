# Product

<!-- impeccable:product-schema 1 -->

## Platform

android

Primary: Android tablets and phones (the APK). The same Flutter code also runs as a web app / PWA, used on iPhones and desktop browsers. One interface language across all of them (confirmed with the owner 2026-11-06: tuned first for an Android tablet at the counter).

## Users

Owners, managers, sellers and warehouse keepers of small shops, first an auto-parts shop in Turkmenistan, sold to more shops by monthly subscription. They work in Russian or Turkmen, on a tablet or phone at the counter, often with a barcode scanner or the camera, in an "old-fashioned market" setting (little internet, little patience for forms). Many are first-time users of any ERP. (From docs/PRD.md and AGENTS.md; the shop owner is also the person who sells the subscription.)

## Product Purpose

Know what is on the shelf, sell it, take it back, honour its warranty, and see the day's money, without accounting complexity. Success: a new shop can receive goods, sell and read its figures without training; stock matches what is on the shelf; one store never sees another's data.

## Positioning

An ERP, not a cash register: short forms, free selling prices, scanning first, FIFO costing, warranty register, two languages (ru/tk) from the ground up, sold as a simple monthly subscription.

## Operating Context

Counter tablet in portrait and landscape, phones, desktop browser; scanning with camera or hand scanner; receipts printed or shared as PDF; sometimes poor connection. Stock-changing actions need internet. Interface languages: Russian and Turkmen (Turkmen text is still a draft awaiting a native-speaker review).

## Capabilities and Constraints

Products and barcodes, stock and receiving, sales and cart, returns, warranties, expenses, reports and dashboard, staff and roles (owner, manager, sales, warehouse), subscriptions with an owner console. Constraints: the redesign must not change behaviour, copy meaning or permissions; both languages must fit with long words and doubled text size; the interface has existing widget keys used by ~460 tests; Flutter 3.47.6 (pinned).

## Brand Commitments

Name "ERP System" (a product name is still undecided). The blue-to-violet brand and the "E" mark (already on users' home screens and in the app) stay as the identity; the palette, surfaces and depth around it are being refined. Font: Onest (bundled). Confirmed by the owner 2026-11-06.

## Evidence on Hand

The running app and its screenshots; docs/DESIGN_SYSTEM.md (the previous "Premium Minimalist" direction), docs/USABILITY.md (the rules and the open problems), the Figma mock-up the owner supplied earlier. No customer testimonials or metrics exist; none may be invented.

## Product Principles

1. Simple beats clever: one main action per screen, nothing the owner did not ask for.
2. A shopkeeper should never need to remember: show choices, say what to do next.
3. Money and stock figures must be trustworthy and legible at a glance.
4. Both languages must work first-class, never as an afterthought.

## Accessibility & Inclusion

Text contrast of at least 4.5:1 in light and dark, touch targets of at least 48 px, no meaning by colour alone, works at doubled text size and with screen readers (docs/USABILITY.md rule 12). Reduced-motion settings are respected.

## Open decisions

Product name; dark theme starts light and is chosen in Settings (owner, 2026-11-06).
