# Usability: principles and review

Status: first review, 2026-11-06. None of the fixes in section 3 are built yet.

**What this review is:** one expert-style inspection by an AI agent. It looked at the live site in a desktop browser at phone width (393 px), on a nearly empty store (close to what a first-time user sees), and at the code. Screens looked at: dashboard, menu, products, stock, sales and cart, expenses, warranties, reports, settings, sign-in.

**What it isn't:** evidence that real people find the app easy. No real user, phone or tablet was involved. Principles sometimes conflict, and no checklist can prove "all of HCI" is applied. Only watching first-time users can show that (section 4).

## 1. The rules every screen must follow

Read with [DESIGN_SYSTEM.md](DESIGN_SYSTEM.md) before any UI change. Sources: Nielsen's 10 heuristics, Shneiderman's 8 golden rules, Norman's design principles, Fitts's and Hick's laws, chunking, Gestalt grouping, WCAG 2.2 AA.

**Finding the way**
1. **One clear next step.** Each screen has one main action, and an empty screen says what to do and offers a button for it (Norman: signifiers).
2. **See, don't remember.** Show choices rather than making people recall a code, a path or a hidden menu (Nielsen 6).
3. **Reveal gradually.** Don't show filters, statuses or options until they can matter (Hick's law, progressive disclosure).
4. **Everything has one name.** The same thing has the same word, place and order on every screen, and the same word never means two things (Nielsen 4, Shneiderman 1).
5. **The shopkeeper's language.** Plain words, not accounting or software terms. If a term is unavoidable, explain it where it appears (Nielsen 2).
6. **Say only what's needed here.** Remove repeated titles and anything that doesn't help this task (Nielsen 8, Gestalt).

**Acting safely**
7. **Prevent the error first.** Don't offer what can't work. Validate as people type, and keep what they typed when something fails (Nielsen 5, Norman: constraints).
8. **Easy to undo.** Reversible actions happen at once with an Undo. Only irreversible or costly ones ask for confirmation, and they say what will happen (Nielsen 3, Shneiderman 6).
9. **Always show what's happening.** Loading, saved, failed, offline. Never show success before the server confirms it (Nielsen 1, Norman: feedback).
10. **Errors say what to do.** Plain words, the cause, and the fix (Nielsen 9).

**Comfort and access**
11. **Easy to hit.** Touch targets are at least 48 px with spacing, and frequent actions are large and within thumb reach on phones (Fitts's law).
12. **Readable by everyone.** Text contrast of at least 4.5:1, no meaning from colour alone, works at doubled text size, works with screen readers (WCAG).
13. **Fast for experts.** Scanning, keyboard entry and remembered choices shouldn't slow experienced staff (Nielsen 7, Shneiderman 2).
14. **Help when needed.** A short help entry per task, reachable from the screen where it's needed (Nielsen 10).

Each rule is checked in review on the new or changed screen, in both languages, at phone and tablet widths.

## 2. What already works

- **Status:** offline banner, pending-operations banner, "Добавлено: water" after adding to the cart (rule 9).
- **Prevention:** no second-shop option, stock limits, return periods, drafts that survive a crash (rule 7).
- **Contrast:** muted text is 5.4:1 on the page background and 6.0:1 on white (rule 12).
- **Doubled text:** tested on the selling, returns, transfers and counts screens. Not checked for every screen (rule 12).
- **Experts:** barcode scanning, hand-scanner support, keyboard entry (rule 13).
- **Reversal:** a sale isn't silently edited; returns and corrections are linked records (rule 8).

## 3. Problems found

Priority: **A** blocks a first-time user or a client, **B** causes confusion, **C** is polish.

| # | Pri | Where | Problem | Rule | Fix |
|---|---|---|---|---|---|
| 1 | A | Whole app | No first-run guidance and no help at all. A new owner lands on six "0,00 TMT" cards and nothing suggests a next step. | 1, 14 | Dismissible first-run checklist: add a first product, receive stock, make a sale, fill in the shop's details, add staff. Short help per page. |
| 2 | A | Settings | No way to change your password. | 8 | Add it (Phase 0 of the plan). |
| 3 | A | Every empty page | The shared `EmptyState` widget can't hold a button at all. Stock says "enter opening stock", but that action is hidden under "Ещё" and the message sits below the filters, half off-screen. | 1, 3 | Give `EmptyState` an action. When there's no data, hide the filters, move the message up and add a button that goes straight there. |
| 4 | A | Warranties | A brand-new store sees "Ничего не найдено" although nobody searched. A proper empty message exists, but the filter selected by default ("Действует") triggers the no-match one instead. | 9, 10 | Show the proper message whenever the store has no warranties at all. |
| 5 | A | Sign-in | With the role picker, a wrong password closes the box and loses the choice, so you start again. No "show password". | 7 | Keep the box open with the error, and add a show-password eye. (Applies to normal sign-in too.) |
| 6 | B | Menu | Order differs: the side menu has Склад before Продажи, the bottom bar has Продажи before Склад. | 4 | One order everywhere. |
| 7 | B | Stock vs Products | "Добавить товар" does two different things: on Products it creates a product, on Stock it receives goods. | 4 | Rename the Stock one, for example "Принять товар". |
| 8 | B | Settings vs header | Two names for one shop: "Awto Merkezi" (business) and "Авто Запчасти" (location) on the same screen. With one shop, a person shouldn't have to know the difference. | 4 | One shop name, edited in one place. |
| 9 | B | Stock | Leftovers of multi-location after the one-shop decision: a "По точкам" tab and an "В пути" filter. | 3, 6 | Remove both when there's one shop. |
| 10 | B | Stock | Three competing actions plus a second scan button, and five status filters on an empty page. | 1, 3 | One main action (receive by scan), the rest under "Ещё", and filters only once there's stock. |
| 11 | B | Dashboard, Reports | "Валовая прибыль", "Себестоимость проданного", "Чистые продажи" with no explanation. | 5 | Plainer words where possible, and a one-line explanation on tap. Agree the wording with the owner. |
| 12 | B | Every page, phone | Repetition: the page name appears twice and the shop name up to three times, using about 120 px of 852 before the content starts. | 6 | Page name once. Hide the shop chip when there's only one shop. |
| 13 | B | Every page, phone | The RU/TM switch takes prime space on every screen although language is set once (it's also in Settings). | 6 | Keep it on sign-in and in Settings. |
| 14 | B | Phone navigation | Half the app (Расходы, Гарантии, Отчёты, Настройки) is behind a menu icon, duplicating the bottom bar. | 2 | A fifth "Ещё" tab, the pattern phone users already know. |
| 15 | B | Reports, Stock tabs | Tabs run off the edge ("Рас…", "Инвентариза…") with little sign they scroll. | 2 | Fewer tabs, or a clear edge fade. |
| 16 | B | Whole app | Words vary: точка / магазин / место, склад / кладовщик, продажи / касса. No agreed glossary. | 4, 5 | A short RU/TK glossary, applied everywhere, with a native speaker review. |
| 17 | C | Dashboard | Greets by login ("Здравствуйте, owner!") when no name is set. | 5 | Ask for a name at first run. |
| 18 | C | Cart | The bin removes a line at once, with no Undo. Its button is 40 px. | 8, 11 | Undo in a snackbar, and a 48 px target. |
| 19 | C | Bottom bar | 11 px labels. The stepper was raised to 44 px last round but the rule above says 48. | 11, 12 | Check on a real phone, raise where it fits. |
| 20 | C | Phone browser / PWA | `theme-color` is cobalt while the top bar is cream, which may tint the status area against the page. Not seen on a device. | 4 | Match the top bar. |
| 21 | A | iPhone home-screen app | The owner's screenshot shows the whole app about 6% too large, cut off at the right and bottom. The cause isn't established and the fix isn't confirmed (see below). | 9, 12 | Test on the device. |

### About item 21

In the owner's iPhone 15 Pro screenshot, every element measures about 6% larger than the same screen at 393 px, and the right edge and bottom bar run off the screen. On 2026-11-02 this was put down to an accidental pinch zoom and pinch zoom was disabled. That isn't proven: the owner saw it on loading the app, and the check was done in a desktop browser, which would have looked fine before the change too. A uniform scale on load points more to a wrong size at startup in iOS home-screen mode. It needs testing on the device, and if it persists, debugging there.

## 4. Testing with real people

1. **Who:** five people who've never seen the app and would really use it (shop owner, seller), on their own kind of device.
2. **Tasks, with no hints:** sign in and change your password; add a product; receive five of it; sell two; print or share the receipt; take one back; find today's sales; add a seller.
3. **Record:** finished or not, time, wrong turns, and what they say aloud. Then the 10-question System Usability Scale (SUS). A score of about 68 is the commonly cited average, so aim above it.
4. **Repeat** after fixes, in Russian and Turkmen.

The agent can prepare the script and score sheet. The sessions need the owner and real users.
