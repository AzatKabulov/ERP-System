# Product Requirements Document

Status: Initial draft based on the agreed product idea. Requirements describe intended behavior, not features already implemented.

## Product Overview

Product: ERP System (working name)

An inventory-focused ERP for shops and wholesalers that buy, store, and sell physical products. Car parts stores are the first target market, while the core workflows should support other inventory-based businesses.

Launch market: Turkmenistan. Russian and Turkmen are required application languages from the first Android release, with the same language support carried forward to iPad and iPhone.

Goal: Give business owners and staff one reliable place to manage products, stock, purchasing, sales, returns, expenses, and warranties across stores and warehouses.

The application will use Flutter. Android tablets are the first release target, followed by iPad and iPhone. Layouts should accommodate smaller screens without requiring a separate application.

## Problem

Businesses often manage inventory using spreadsheets, paper records, or disconnected applications. This makes it difficult to know what is available, locate products, reconcile stock differences, identify purchasing needs, and understand business activity.

When several staff members or locations handle the same products, unrecorded movements and inconsistent information can cause overselling, unnecessary purchases, lost stock, and mistakes in returns or warranties.

## Target Users

- Business owners: oversee operations, expenses, inventory value, reports, and staff access.
- Store managers: manage purchases, stock, transfers, and operational approvals.
- Sales staff: find products, record sales, issue receipts, and handle authorized returns.
- Warehouse staff: receive deliveries, locate products, transfer goods, and count stock.

Each business owns its records. Access to another business's data must be denied, including through search, reports, imports, exports, and document downloads.

## Languages and Localization

- Provide complete Russian (`ru`) and Turkmen (`tk`, modern Latin script) interfaces, including sign-in, navigation, forms, validation, errors, notifications, reports, and accessibility labels.
- Let each user select a language and remember the selection between sessions. Show language choices as `Русский` and `Türkmençe`. Changing language must preserve business data and work in progress.
- Receipts, invoices, and generated report headings must support either language. Document language must be selectable independently of the staff member's interface language.
- Support Russian Cyrillic and Turkmen characters in entry, storage, search, imports, exports, and generated documents. Fonts must render these characters correctly on devices and in printed or PDF documents.
- Localize system text without automatically translating user-entered product names, customer names, supplier details, or identifiers. A shared catalog remains the same when the interface language changes.
- Format dates, numbers, and monetary values consistently with the selected locale and configured business currency. Interface language must not change stored amounts, currency, rounding rules, or timestamps.
- Review business terminology and translations with fluent Russian and Turkmen speakers before the pilot release. English-only system text is not acceptable in either supported interface.

## Core Features

### Dashboard

Show sales totals, inventory value, low-stock alerts, reorder suggestions, and recent activity. Users can filter permitted information by location and date. Financial information is visible only to authorized roles.

### Products and Barcode Scanning

Manage names, SKUs, barcodes, categories, brands, units, purchase costs, selling prices, and warranty terms. Support product lookup by text or barcode during sales, receiving, and stock counts.

The first Android release must support at least one agreed scanning method on a real tablet. The agreed first method is the tablet camera (decided 2026-10-06), always with manual entry as a fallback. Typed entry alone does not satisfy the scanning acceptance check. External scanner support is tested separately once a device is chosen; support for arbitrary scanners is not assumed.

### Inventory, Stores, and Warehouses

Track stock separately for each location, with optional shelf or bin information. Record receiving, sales, returns, transfers, and approved adjustments as identifiable stock movements.

Transfers distinguish goods dispatched, in transit, and received. Goods must not appear available at both locations during a transfer.

### Purchasing and Reordering

Manage suppliers and purchase orders. Record partial deliveries and outstanding quantities. Stock increases when goods are received, not when an order is created.

Suggest replenishment using configurable minimum and target stock levels per product and location. Show relevant outstanding purchases. Staff review suggestions before creating purchase orders; automatic ordering is outside the initial scope.

### Physical Stock Counts

Allow staff to count stock by location, compare counts with system quantities, review differences, and submit adjustments for approval. Preserve the count results and adjustment reasons. Handle movements made during a count explicitly so concurrent sales or receiving do not produce unexplained corrections.

### Sales, Customers, and Documents

Record customer details when applicable, selected products, quantities, prices, discounts, and payment method. Support walk-in sales without requiring a customer account.

Complete sales against available stock at the selected location. Produce receipts and invoices with business details and configurable tax information. The initial version records payments; it does not process card payments through a gateway.

### Returns and Refunds

Link customer returns to original sales and enforce the remaining returnable quantities. Record return reasons and refund amounts, including partial returns.

Classify returned goods as sellable, damaged, or awaiting inspection. Only sellable goods become available stock. Support exchanges through linked return and sale records, and record supplier returns separately.

### Expenses

Record expense category, amount, date, location, description, and optional receipt attachment. Support filtering and expense summaries. Expense tracking does not constitute a full accounting system.

### Warranty Tracking

Save the applicable warranty terms with the sale so later product changes do not alter the original entitlement. Track claims, eligibility, status, and repair or replacement outcomes. Record any resulting inventory movement.

### Import and Export

Provide CSV import and export for product catalogs, plus CSV export for relevant reports. Imports must preview validation errors and duplicate identifiers before applying changes. An invalid import must not leave unexplained partial updates. Exported data must respect permissions.

### Permissions and Activity History

Provide owner, manager, sales, and warehouse roles with documented permissions. Enforce permissions on the backend, including financial information, discounts, refunds, imports, and stock adjustments.

Record who performed important actions, when they occurred, and the affected records. Ordinary users must not edit or delete activity history through the application.

### Reports

Provide sales, stock movement, low-stock, inventory value, purchasing, returns, and expense reports. Allow date and location filtering where applicable.

Define inventory valuation and product costing consistently before reporting gross margins. Label estimated values clearly. Sales revenue, gross profit, expenses, and net profit must not be presented as interchangeable measures.

### Backup and Recovery

Provide scheduled backups of business records and uploaded documents, with protected access and defined retention. Verify recovery by restoring a backup into a separate environment and checking representative records and attachments.

Restoration is a controlled administrator operation. CSV exports alone do not satisfy the backup requirement.

## Key User Flows

1. Business setup: an owner configures the business, locations, staff access, and initial product catalog.
2. Purchase to receipt: staff create a purchase order, receive an actual delivery, and verify the updated stock and outstanding quantities.
3. Sale: a cashier scans or searches for products, reviews quantities and prices, completes the sale, and issues a receipt. Stock decreases once.
4. Transfer: staff dispatch goods from one location and confirm their arrival at another, retaining the complete transfer history.
5. Stock count: staff record physical quantities, review discrepancies, and an authorized user approves explained adjustments.
6. Return: staff find an original sale, record eligible returned items and their condition, and record the refund and appropriate stock changes.
7. Warranty: staff find the original sale, check entitlement, open a claim, and record the resolution.
8. Owner review: an owner filters reports to understand sales, expenses, stock value, and replenishment needs.

## Functional and Quality Requirements

- The server is the authority for stock, permissions, and finalized business transactions.
- Stock-changing operations must complete consistently: failed operations must not leave a sale, transfer, or return only partly recorded.
- Retrying a request must not create duplicate sales, receipts, refunds, or stock movements.
- Concurrent sales must not sell the same unavailable stock. Negative available stock is disallowed in the initial version.
- Finalized records retain their history. Corrections use linked reversals or adjustments rather than silently rewriting past movements.
- Monetary calculations use decimal arithmetic with defined currency and rounding rules. The first version uses one configured currency per business (TMT for the pilot, 2 decimals, rounded half up). One limited exception, decided 2026-10-06: a product's selling price may be stated in USD and is converted to the business currency at an exchange rate entered by an owner or manager; the rate used is saved on each sale. Purchase costs, totals, payments, stock values and reports remain in the business currency.
- Important forms provide validation, loading, success, empty, and error states. A failed request must never appear as a successful transaction.
- Use authenticated, encrypted network connections. Keep server credentials out of the mobile application and protect stored sessions.
- Tablet layouts support portrait and landscape, accessible text sizing, readable contrast, and comfortable touch targets.
- Both supported languages must remain usable with long translations, scaled text, barcode entry, and localized document generation.
- Stock-changing actions require internet access in the initial version. Cached information, if provided, must clearly show that it may be stale.
- Country-specific invoice and tax requirements must be established before commercial launch; legal compliance is not assumed from generic invoice support.
- Hardware integrations and recovery procedures must be validated on the selected devices and deployment environment.

## Delivery Stages

1. Foundation and Android workflow: Russian and Turkmen localization, business isolation, users and roles, locations, products, barcode lookup, suppliers, purchases, receiving, sales, receipts, and stock history.
2. Inventory operations: transfers, physical counts, reorder suggestions, returns, and refunds.
3. Business management and pilot readiness: expenses, warranties, imports and exports, dashboards, reports, activity review, and verified backup recovery.
4. Apple release: validate and release the shared Flutter application for iPad and iPhone, including platform-specific scanning and hardware checks.

All listed features remain in the agreed product scope. Stages determine delivery order, not which features are included. Access control and transaction integrity apply from the foundation stage.

## Success Metrics and Acceptance Criteria

- A pilot store can complete purchase, receipt, sale, transfer, count, return, and warranty workflows without directly editing database records.
- Stock balances match the recorded movements across representative end-to-end scenarios, including partial deliveries and returns.
- Duplicate-request and concurrent-sale checks produce no duplicate transactions or unintended negative available stock.
- Unauthorized access checks deny cross-business records and actions outside each role's permissions.
- Product import accepts a valid catalog and reports invalid rows without unexplained data changes.
- A verified backup restores representative business records and uploaded documents successfully.
- Barcode lookup and tablet layouts work on the selected real Android device; the equivalent iOS checks pass before the Apple release.
- Pilot workflows can be completed in Russian and Turkmen without untranslated system messages or missing glyphs. Language selection persists, and switching language does not lose entered work or alter transaction values.
- Imports, exports, receipts, invoices, and report documents preserve representative Russian and Turkmen text correctly.
- Pilot feedback measures task completion, time spent on routine workflows, stock discrepancies, and staff satisfaction. Quantitative business targets will be set after establishing the pilot store's baseline.

## Out of Scope for the Initial Version

- Full accounting, payroll, HR, and manufacturing.
- Offline sales and automatic synchronization of offline stock changes.
- Payment gateways, customer credit accounts, and installment management.
- Automatic supplier ordering and advanced demand forecasting.
- Online-store integrations and a separate desktop interface.
- Advanced vehicle compatibility catalogs and automated equivalent-part suggestions.
- Full multi-currency accounting (beyond the limited USD selling-price exception described above), and universal compatibility with scanners or printers.

## Decisions to Confirm During Implementation

- Turkmenistan-specific invoice formats and applicable tax requirements. (Business currency TMT with optional USD selling prices was decided 2026-10-06.)
- Default language for first-time users, document-language defaults, and approved Russian/Turkmen business terminology.
- Pilot tablet model, scanning method, and any required receipt or label printer.
- Warranty claim policies. (FIFO inventory costing and the warranty term fields were decided 2026-10-06.)
- Email service for password-recovery codes, tested from Turkmenistan.
- Refund and stock-adjustment approval rules.
- Hosting, backup frequency, retention, and acceptable recovery time and data loss.

These decisions do not prevent starting the shared product foundation, but must be resolved before their affected workflows are finalized.
