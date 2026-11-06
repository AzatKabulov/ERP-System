# Selling the ERP as a subscription

Status: plan for the owner's review, 2026-11-06. Nothing here is built yet. It adds to [PRD.md](PRD.md) and [ARCHITECTURE.md](ARCHITECTURE.md). The usability work the owner asked for at the same time is in [USABILITY.md](USABILITY.md).

## 1. How it will work

1. A store (say Willy Wonka) buys a package from us.
2. We open the owner console, create the store and get a login and a temporary password.
3. We hand those over, with the web link or the app. The store owner must choose a new password at first sign-in, and we never learn it.
4. The owner adds their own staff. Everyone works in one shared system and sees only their own store.
5. The console shows us every client and when they expire. We renew by hand at first, and automatically later if a payment provider fits.
6. If a store stops paying, it gets warnings, then a grace period, then read-only access. Its data is never deleted automatically.

## 2. Where we stand today

### Already sound (checked in the code on 2026-11-06)

- **Each record belongs to one store.** Products, stock, sales, customers, expenses, warranties and files all point to one `Business`.
- **Every store address is guarded.** A person with no membership in a store gets "not found", so they can't even tell it exists. A test fails if any store route is added without this guard (`common/tests/test_foundation.py`).
- **Lookups are filtered by store as well.** Sale numbers, SKUs and barcodes are counted per store. References sent by the app are accepted only if they belong to the same store (`BusinessScopedField`). 24 backend test files mention another store. I read the search hits below, not all of the code, so Phase 0 includes a full review.

This is good evidence, not a guarantee. The owner calls a leak between stores "a big issue", so Phase 0 adds one test that attacks every route.

### Blocks selling to a second store

| Problem | Why it matters | Fix |
|---|---|---|
| **A store owner can't change their password.** The server supports it, but the app has no screen for it. | This is step 3 of the model above. | Add the screen, and force a change at first sign-in. |
| **"Forgot password" doesn't work on the live server,** because no email service is set up. A staff password reset also goes by email. | A locked-out store can't get back in. | Set up email, and add a "reset password" action in the console. |
| **The role picker can't serve two stores.** It assumes logins are literally `owner`, `manager`, `sales`, `warehouse`, and logins are unique across the whole system. | Store 2 can't have an `owner`. Picking "Владелец" would always try store 1's account. | Turn it off and use normal login that remembers the last name on the device. A per-store version is decision D7. |
| **All four live accounts share one weak password,** and it has been typed into a chat. | Anyone who guesses it gets the owner account. | Replace it before any client data goes in. |
| **Every staff member needs their own unique email,** across all stores. | Small shops' sellers often have no email. | Make email optional for staff, with the owner resetting their passwords. |
| **No way to create a store except a server command** (`create_business`). | Not usable day to day. | A "new client" form in the console. |
| **Backups stay on the same machine as the data,** and a restore has never been tried. They do run nightly (4 of 4 so far). | One disk failure loses every client. | Copy them off the server and do a restore drill. |
| **The server is a free 1 GB machine.** With one nearly empty store it already has 356 MB in swap (about 520 MB of memory is still available). | Paying clients shouldn't depend on it. How many stores it can carry is not measured. | Move to a small paid server before real clients, and measure the load. |
| **The live site was uploaded from uncommitted work on one PC.** About 90 files are not in git. | One PC failure loses it, and there is no record of what is running. | Commit, then deploy only from git. |
| **The Android app is signed with a development key,** and has not been run on any device yet. | Moving to a real key later forces every client to reinstall. | Create the real key and decide the app id and product name before the first client. |
| **Can clients in Turkmenistan reach this server?** Never tested from there. | If clients are there and it's blocked or slow, nothing else matters. | Open the site from a real shop's connection there, first. |
| **No terms of service or privacy note.** | Clients trust us with their sales data. | Short terms (needs a lawyer's eye; not something code can settle). |

### We can technically see store data

We run the server, so we can always read the database. The honest promise to clients is "we don't look, and every console action is logged", not "we can't". The console below is built so that normal use never shows a store's sales, customers or prices.

## 3. Subscription rules

- **Packages:** 1 month, 3 months, 1 year, plus custom days. Months are calendar months, so 3 June to 3 July rather than "30 days". We can add or change packages without new code.
- **Renewing:** if the store is still active, the new time is added after the current end date. If it has already lapsed, the new time starts today. The console shows the resulting date before we confirm.
- **Custom extension:** "they'll pay next week, give them 7 days" uses the same action with a required reason.
- **Mistakes:** every change records the old date, the new date, who did it and why. A wrong entry is fixed by another entry, so the history stays honest.
- **Free trial:** optional per client (D3).
- **Two manual switches:** *Suspend* (cut off now, with a reason, even if paid) and *Free access* (a demo or partner store).

What the store experiences (recommended; D2):

| Stage | Who sees what | Can they work? |
|---|---|---|
| Active | Nothing | Yes |
| 7 days before the end | Owner and manager see a banner with the date. Sellers see nothing. | Yes |
| Grace period: 7 days after the end | Red banner with how to pay | Yes, nothing stops mid-sale |
| After grace | A clear screen with our contact details. Staff are told to contact their owner. | Read-only: they can look and export, but not sell or change anything |
| Renewed | Everything returns as it was | Yes |

I recommend read-only over a full lockout. A shop should never lose sight of its own records because of a late payment, and that keeps trust and a path back to paying.

## 4. The owner console

This is our own system, separate from any store, with its own login and two-step sign-in. Every action in it is logged.

**Clients**
- A list with store name, owner, phone, package, end date, days left in colour, and last payment.
- Filters: expiring this week, in grace, read-only, suspended, trial.
- A "new client" form: store name, owner name and contact, language, package. It creates the store and shows the login and temporary password once.
- A client page with subscription and payment history, notes ("called, will pay Friday"), staff count and support requests.
- Actions: renew, custom days, suspend or resume, reset the owner's password. Risky ones ask for confirmation and a reason.

**Money**
- Record each payment: amount, currency, method, reference. A receipt or invoice PDF can come later.
- Income this month, income by package, renewals versus cancellations, and what is due in the next 30 days. These are working figures, not accounting.

**Keeping clients**
- A "who to call" list, which needs no automation to be useful.
- Reminders by email or messenger before expiry, once a channel is chosen (D6).
- Usage signals, to spot a store about to quit: last sign-in and number of sales in 30 days. Counts only, never content, and the terms must say so (D5).

**Support and feedback**
- A "Help / write to us" button in the app. It sends the message with the store name, screen and app version, and the store sees our reply in the app.
- A list in the console: open, answered, closed.
- Start with this request list rather than live chat. Live chat needs someone online to answer. If clients prefer a messenger, a link to it is cheap (first check which one works for them).
- Later, if volume grows, buy a help-desk tool rather than build one.

**Running the service**
- A banner to all stores ("maintenance tonight at 23:00").
- Health at a glance: is the server up, when was the last good backup, how full is the disk.
- A "new version available" prompt in the Android app, since it isn't in an app store.
- Export of a store's data when they leave, and a written rule for how long we keep it.

**Deliberately left out:** logging in *as* a store, because the owner said we don't need access to their system. Support works from screenshots, or from a temporary staff account the store creates and removes itself.

**How to build it:** a separate Django admin site with only these tables, at its own address. It's the quickest route, it works on a phone, and it needs no extra Flutter screens or translations. Today's Django admin isn't fit as it is, for two reasons: it shows every store's sales, customers and expenses, and the live server doesn't route to it at all (`/admin/` answers 404). If daily use outgrows it, we build a nicer page later using the same data.

## 5. Getting paid

**Start by hand.** The client pays however we agree. We confirm it and press Renew. This is enough for the first stores.

**Automate later,** once two questions are answered:
1. **Where is our business registered, and which bank account receives the money?** The options depend on this. I had assumed Turkmenistan at first, but that isn't established. One vendor guide says Stripe doesn't support Turkmenistan-registered businesses, and I haven't confirmed that with Stripe.
2. **How can the clients actually pay?** A provider is useless if clients' cards or banks can't reach it. Merchant-of-record services claim to cover Turkmenistan, but that's a vendor claim I haven't verified, and they'd charge in USD.

The design leaves room for this: a provider's "payment received" message would do exactly what the Renew button does.

## 6. Delivery order

Each phase ends working and tested, with the usual rules from [PLAN.md](../PLAN.md): tests, including another-store denial; Russian and Turkmen text; loading, empty, error and success states.

**Phase 0: Safe for a second store (do first)**
- Commit the current work and deploy from git.
- Change-password screen and forced change at first sign-in. Turn off the role picker.
- Email service, optional staff email, new passwords on the live accounts.
- A test that tries every store route with another store's IDs, plus a review of the search-based findings above.
- Off-site backups and one real restore drill, plus an outside uptime check.
- Check access from the clients' country. Real Android signing key, app id and product name.

**Phase 1: Subscriptions and the console's core**
- Packages, subscription history, the status rules in section 3 and their enforcement.
- Console: client list, new client form, renew, custom days, suspend, reset password, notes, payment records, audit log.
- Clients can be created and renewed by hand from here. **This is the first point we could sell.**

**Phase 2: The store's side of it**
- Banners, the read-only screen, a clear message when a queued sale is refused, in both languages.
- First-run checklist and the top usability fixes ([USABILITY.md](USABILITY.md)).
- Usability test with five real first-time users.

**Phase 3: Running the business**
- Dashboard figures, who-to-call list, support requests in the app, announcements, reminders, usage signals, export on leaving, moving to a paid server if not already done.

**Phase 4: Automatic payment**
- Only once section 5 is answered and there are enough clients to justify it.

## 7. Decisions for the owner

- **D1 Packages and prices,** and the currency we charge in.
- **D2 Lapsed stores:** 7 days of warning, 7 days of grace, then read-only? (Recommended.)
- **D3 Free trial:** recommended 14 days, or none?
- **D4 Where we're registered and how clients pay** (section 5). Which country are the clients in?
- **D5 Usage signals:** may we see counts of sign-ins and sales per store? Recommended yes, and say so in the terms.
- **D6 Which channel reaches clients:** email, Telegram, WhatsApp, phone?
- **D7 Quick login per store.** You asked for the tap-who-you-are login, and Phase 0 has to turn off today's version. It could return properly: a tablet is linked once to its store, then shows that store's staff to tap, followed by a password or PIN. Recommended after Phase 2.
- **D8 Product name.** The app is called "ERP System" on the home screen. Clients will see this, so it needs a name before the first sale.

## 8. Technical notes

For whoever builds this. A new `apps/billing` (platform-level, with no routes under `/businesses/<id>/`).

```python
class Plan:                # code, name, months (1/3/12) or null for custom, price, currency, is_active
class Subscription:        # OneToOne(Business), paid_until, plan, override (none/suspended/free), trial
class SubscriptionEvent:   # AppendOnlyModel: kind, old_until, new_until, plan, amount, currency,
                           # method, reference, note (required), actor, created_at
class ClientNote:          # AppendOnlyModel: business, author, text, created_at
class SupportRequest:      # business, raised_by, subject, status, context (screen, app version)
```

- **Don't derive the end date with `max()` over periods.** A mistaken long grant could never be shortened. Keep `paid_until` on `Subscription`, change it under `select_for_update`, and write an event in the same transaction.
- **Status** is computed in one function from `paid_until`, `override` and the store's time zone, so no scheduled job is needed for access to end on time. Reminders do need one.
- **Enforcement** goes in `HasBusinessPermission` (`apps/businesses/access.py`), after the membership lookup: writes in the read-only stage get HTTP 402 `subscription_expired`, and reads pass. The exports need a check that they stay allowed. `/me/` carries the status so the app can show the banner, with the date only for owner and manager. Sign-in itself is never blocked. `OperationRunner` must treat the 402 as "tell the person", not "retry forever".
- **`Business.is_active = False` stays** as the "closed account" switch. It already hides a store entirely.
- **Console:** a separate `AdminSite` holding only platform tables plus basic `Business` and `Membership` fields. Take the store-data models off the public admin. Needs a Caddy route (today only `/api/*`, `/install*`, `/downloads/*` and the web app are routed), its static files, `DJANGO_ADMIN_PATH` or its own subdomain, and two-step sign-in (a new dependency to approve).
- **Logins** stay unique system-wide: generate them at client creation (`wonka-owner`). Add `must_change_password` to `User`, and make `email` optional for staff (the unique constraint must allow blanks).
- **Login limits already exist** (5 tries a minute per login, 30 per IP). There's no lockout, which is acceptable once passwords are strong.
- **Restores:** one database means a restore rolls back *all* stores. Restoring one store alone needs its own tool. Decide before it's needed, not during an incident.
- **Tests:** status at each boundary (end date, last grace day, day after, time zone edge), one store's lapse never touching another, each role's view of the banner, and a console user with no membership being refused by the store API.

## Sources for section 5

Vendor pages only, not confirmed with the providers: [Doola on Stripe and Turkmenistan](https://www.doola.com/?p=25116), [Dodo Payments on Turkmenistan](https://dodopayments.com/payments-in/turkmenistan).
