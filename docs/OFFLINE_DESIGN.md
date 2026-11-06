# Working without internet: design and decision needed

Status: proposal of 2026-10-31, after the owner's request ("think through offline work and add it,
as much as possible, but the main focus stays online"). **Not built yet.** It changes the agreed
operating model (AGENTS.md: "internet access is required for stock-changing actions"), so the
direction below needs the owner's confirmation before code is written.

## What works today

- Every stock or money action goes through the server (FIFO, locks, numbering), so two devices
  can never sell the same last unit.
- A flaky connection is already handled: each action is saved on the device **before** it is sent
  and resent with the same key until the server answers (restart-safe, no double sales). The app
  shows a banner when the server cannot be reached and disables the buttons that need it.
- Reading (products, stock, history, reports) needs the server. Nothing is stored on the device
  except the sign-in, the language and unsent actions.

## Three different situations (they need different answers)

| Situation | Example | Answer |
| --- | --- | --- |
| **1. A bad connection** | the signal drops for a minute | Already covered by the saved-then-resent actions. Improve: keep reading the last loaded lists. |
| **2. Hours without internet** | a power cut at the provider, a rented tablet in a basement | **Offline mode in the app** (option B below). |
| **3. No internet at all, ever** | a market stall with no line | **A server inside the shop** (option A below). The app cannot be the database: stock must stay correct across devices. |

## Option A: the shop server (answers situation 3, and also 1 and 2)

The same system already runs on one computer with no internet (`scripts/local/run_local.py`,
`docs/LOCAL_TEST.md`): the database, the API and the web app in one program. Tablets and phones
connect to it over the shop's Wi-Fi. Everything works exactly as online, including FIFO, returns,
warranties and reports, with no new logic to get wrong. Internet is then only needed for optional
things: the online barcode-name lookup, updates, and copying backups elsewhere.

What must be built to make it a product and not a test tool:
1. A proper **install and start-up** for the shop computer (a Windows installer or a service that
   starts with the computer; no sample data; a real owner and password; the data folder chosen).
2. **Safety:** automatic nightly backup to a second place (a USB disk or a cloud folder), a
   restore button, and a plain warning when the computer is about to run out of disk.
3. **The tablets' connection:** the signed Android app refuses plain `http` on purpose, and a
   browser allows the camera only on `https` or `localhost`. For a Wi-Fi server we need either a
   private HTTPS certificate that the tablets trust (set up once per tablet) or an explicit
   "this shop's own computer" mode in the app that accepts `http` on private addresses only.
   This is a security decision, so it is yours.
4. Remote help (optional): the same computer can also be reached from outside later.

Risk: the shop computer becomes critical (power, disk, theft). Backups are not optional.

## Option B: offline mode in the app (answers situations 1 and 2)

The app keeps a copy of what it needs and lets the seller keep working; it sends the work when the
connection returns.

1. **A local copy of the catalog** (names, articles, barcodes, prices, the last known quantity,
   thumbnails), refreshed at sign-in and while online. Search and barcode scanning then work
   without the server. Stored on the device (IndexedDB in the browser, a local database on Android).
2. **Offline sales.** Allowed only while the local copy is recent (a limit you choose, say
   24 hours). The sale is saved on the device with a provisional number and printed as usual;
   the stock shown on screen is reduced locally so the same unit is not sold twice **on this
   device**. When the connection returns the sale is sent with its saved key; the server numbers it
   and applies FIFO exactly as for an online sale.
3. **Offline receiving** (scan, count, confirm) the same way; it cannot oversell, so it is the
   safe one to allow first.
4. **When the server cannot accept an offline action** (two devices sold the last piece while both
   were offline, or the product was archived): the action goes to a **"needs attention" list** with
   the reason, and a person decides (sell from the next delivery, cancel with a reason, correct the
   stock). Nothing is dropped or changed silently.
5. **Time:** an offline sale is recorded at the time it was made, not the time it was sent, or the
   day's reports would be wrong. The server accepts the device's time inside a safe window and keeps
   both times (a small schema addition).
6. **Not possible offline:** the online barcode-name lookup, reports and history that are not on
   the device, returns of sales the device does not hold, staff changes, password recovery.

Risks to accept, and why this is built after A or only if A is not enough: two devices selling
the same goods offline can both be right locally and one is refused later; the local copy of a
big catalog needs care on a cheap tablet; every new offline action needs tests for "answer lost",
"restart in the middle" and "refused on arrival".

## Recommendation

1. **Decide the situation first.** How often is the shop really without internet, and for how long?
   - A few minutes now and then: nothing more is needed beyond keeping lists visible.
   - Hours, sometimes: build **B**, starting with the catalog copy + offline receiving, then offline
     sales.
   - Often or permanently: build **A** (the shop server), which is smaller and safer than a full
     offline app, and add B later only if tablets also leave the shop.
2. For a first paying client with unreliable internet, **A is the safer first step**: it reuses the
   code that is already tested, and every device stays consistent.

## What I need from the owner

1. The situation above: how bad is the internet at the pilot shops (minutes, hours, never)?
2. For A: may the app accept plain `http` for the shop's own computer on private addresses, or do
   you want HTTPS with a certificate installed on each tablet?
3. For B: how old may the local copy be before offline selling stops (4 hours, a day, a week)? May
   a seller sell a product whose last known quantity is zero while offline (it will be refused or
   put on the attention list when it arrives)?
