# Handoff

Written at the end of the Claude Code onboarding session on 2026-10-06, when the project moved from Codex (cloud) to Claude Code (cloud). Read [AGENTS.md](AGENTS.md) first, then this file. Contains no secrets.

## 1. Branch and commit

- Working branch: `claude/laughing-faraday-3dkwcb`. The Claude Code environment assigned this name; the requested `claude/first-session` was not used because the environment only permits pushing to its assigned branch.
- Starting commit: `48a43b4` "Build bilingual Flutter ERP prototype and project documentation". At the start of the session `main`, the remote branch and the checkout were all at this commit with a clean working tree.
- This session's changes are the commit(s) on top of `48a43b4`. Use `git log --oneline` for the exact tip.

## 2. Implemented vs planned

The product is a **runnable Flutter interface prototype**. It is not a working ERP: every business operation changes in-memory demonstration data (`mobile/lib/demo/demo_store.dart`) and resets on restart. Do not describe it as production functionality.

| Area | Status |
| --- | --- |
| Screens: dashboard, products, inventory, purchasing, sales and returns, expenses, warranties, reports, administration | Implemented as demonstration UI |
| Sales cart, confirmed checkout, linked returns with sellable/not-sellable restocking | Demo only, in memory |
| Receiving, transfers (complete instantly), counts, expenses | Demo only, in memory |
| Purchase orders (3 fixed samples), warranty cards (3 fixed samples) | Hard-coded samples |
| Russian and Turkmen interfaces (202 matching keys each), persistent language choice, custom Turkmen Flutter delegates, bundled Inter and Noto Serif fonts | Implemented; Turkmen wording still needs fluent-speaker review |
| Manual barcode entry dialog | Demo only |
| Backend (Django REST Framework + PostgreSQL), database | **Not started** (proposed in `docs/ARCHITECTURE.md`) |
| Sign-in, roles and permissions, business isolation | **Not started** |
| Camera or external barcode scanning, receipt/label printing | **Not started**; hardware not selected |
| CSV import/export, backups, document/PDF generation, real transfer states, count reconciliation | **Not started** |
| Currency, tax, valuation, refund and approval rules | Undecided (see "Decisions to Confirm" in `docs/PRD.md`); TMT in the demo is illustrative |
| iPad/iPhone | Deferred; no iOS host generated |

## 3. Changes made this session

No application code, dependency, lockfile or Codex script was changed.

- Added `CLAUDE.md`: points Claude sessions to `AGENTS.md` and the project documents.
- Added `HANDOFF.md` (this file).
- Added `scripts/claude_cloud_env.sh` and `scripts/setup_claude_cloud.sh`: Claude Code cloud counterparts of the Codex scripts. They use `~/.tools/flutter` instead of `/workspace`, rely on the VM's own Java 21 and Chromium, and omit the Android SDK (see section 5). The Codex scripts remain untouched and still apply to the Codex cloud.
- `README.md`: added a short "Claude Code cloud" subsection.

## 4. Checks actually run (this session, this VM)

Toolchain: Flutter 3.47.6 (tag commit `5fc346839b…`, matches the pin), Dart 3.13.5.

| Check | Result |
| --- | --- |
| Flutter SDK commit equals the pinned commit | Passed |
| `flutter pub get --enforce-lockfile` | Passed; `mobile/pubspec.lock` byte-identical before and after all commands |
| `flutter gen-l10n` | Passed |
| `dart format --output=none --set-exit-if-changed lib test` | Passed: 15 files, 0 changes |
| `flutter analyze` | Passed: no issues |
| `flutter test` | Passed: 12 of 12 tests executed (7 in `demo_store_test.dart`, 5 in `app_test.dart`) |
| `flutter build web --no-web-resources-cdn` | Passed (`mobile/build/web`, about 44 MB; ignored by git) |
| `flutter build apk --debug` | **Not possible**: "No Android SDK found" (see section 5) |
| ARB key parity (`app_ru.arb` vs `app_tk.arb`) | 202 keys each, none missing. This shows coverage, not translation quality |
| Browser smoke test: headless Chromium 141 driven by Playwright 1.56 against the served web build | 17 of 17 checks passed (see below); one-off script, not committed |

The browser checks covered: Russian is the default language; the demonstration banner is shown; the Sales page opens with an empty cart; adding a product puts 1 item in the cart; the language menu offers `Русский` and `Türkmençe`; switching to Turkmen translates the interface and **keeps the cart**; the choice is stored; checkout asks for confirmation; after confirming, the cart empties and stock falls by exactly 1; all nine pages open in Turkmen; after a reload the language is still Turkmen and demo data has reset; no console errors, page errors or failed requests (the only console output was Chromium's software-WebGL warning in headless mode). Screenshots at 1440×900, 800×1280 and 360×800 were reviewed by eye: layouts adapt (side navigation, rail, menu button) and the Turkmen letters `Ä Ç Ň Ö Ş Ü Ý Ž` that appeared render correctly.

**Not verified**: physical Android device, iOS, TalkBack/VoiceOver, camera or external scanners, printers, release signing, any backend. The earlier Codex results (including the Android debug APK) remain historical and were not reproduced here.

## 5. Environment notes (Claude Code cloud)

- Flutter is installed outside the repository at `~/.tools/flutter` and must be reinstalled in every fresh VM: `bash scripts/setup_claude_cloud.sh`, then `source scripts/claude_cloud_env.sh`.
- `flutter doctor -v`: Flutter works (the "unknown channel" notice is cosmetic for a tag install); Chrome OK (`CHROME_EXECUTABLE=/opt/pw-browsers/chromium`); network resources OK. Android toolchain missing. Linux desktop toolchain missing (GTK), which is irrelevant to this project.
- Flutter prints a harmless "running as root" notice.
- Java: the VM already has OpenJDK 21 with `javac`; nothing was downloaded.
- Reachable by default: `github.com` (git), `storage.googleapis.com`, `pub.dev`, `maven.google.com`, `services.gradle.org`, `plugins.gradle.org`, `repo.maven.apache.org`.
- **Blocked by the network policy: `dl.google.com`** (the proxy answers 403 to the connection). It serves the Android command-line tools and SDK packages, so the Android SDK cannot be installed and no APK can be built until it is allowed. This is an environment limit, not an application defect.
- The Codex scripts were not run: they assume `/workspace`, `CODEX_PROXY_CERT`, a downloaded JDK and `dl.google.com`.

## 6. Remaining blockers

1. **Android builds** need `dl.google.com` allowed (cloud environment settings, Network access: Custom, add the domain under Allowed domains and keep the default package-manager list). After that, extend `scripts/setup_claude_cloud.sh` with the Android steps from `scripts/setup_cloud.sh` (pinned command-line tools, platform 36, build-tools 36.0.0, NDK 28.2.13676358, Gradle mirror). Whether the Gradle Maven mirror host in `scripts/configure_gradle.sh` is reachable here has not been tested.
2. **Product decisions** listed under "Decisions to Confirm" in `docs/PRD.md` (currency, tax and invoice format, costing method, refund and adjustment approvals, hosting, backups, pilot tablet and scanner).
3. **Backend stack authorization.** `AGENTS.md` forbids major architecture changes without approval. Confirm Django REST Framework and PostgreSQL before scaffolding them.
4. **Turkmen terminology** needs review by fluent speakers before any pilot.
5. **Real-device testing** has never happened.

## 7. Observations (not changed)

- At wide widths the top header renders as a narrower floating block rather than a full-width bar. The Codex screenshot `docs/images/dashboard-ru.png` shows the same, so it is pre-existing; confirm whether it is intended.
- In the browser accessibility tree, the Sales page's product-list text is merged into the search field's label. Check how TalkBack reads this on a real device.
- The Sales page shows "available" as stock minus the quantity already in the cart (24 becomes 23 after adding one), which is reasonable but should be a conscious choice.

## 8. Recommended next steps

1. Allow `dl.google.com`, extend the setup script, and confirm a debug APK builds (optional but cheap).
2. Authorize the backend stack, then build a **vertical slice**: a pinned Django/DRF/PostgreSQL scaffold under `backend/` with businesses, locations, memberships, sign-in, permissions and a read-only product catalog, with tests for cross-business denial. Pair it with a Flutter API client, secure session storage and sign-in screens in both languages, and show the real product list in place of the demo list. Keep demo data clearly separate from API data.
3. Next milestone after that: purchasing and receiving, then sales with idempotent retries and a stock ledger (PRD stage 1). Run stock-concurrency tests against PostgreSQL.
4. In parallel, settle the PRD's open decisions with the client and book a fluent-speaker review of the Turkmen strings.

## 9. Switching back to Codex

Tell Codex: "Continue from the branch `claude/laughing-faraday-3dkwcb`. Read `HANDOFF.md` and `AGENTS.md` first, then `docs/PRD.md`. Use the Codex scripts under `scripts/` as before. Report what you verify yourself."
