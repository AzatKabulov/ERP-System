# Try the whole system on your own computer (no Docker)

### Local test role login (2026-10-26)

On the local sample server, press **Войти** and choose **Владелец**, **Менеджер**, **Продавец** or **Кладовщик**. No fields need filling. If already signed in, sign out first. **Войти по логину и паролю** retains the regular form; existing usernames are `owner`, `manager`, `sales`, `warehouse`, and existing passwords are unchanged. Role selection is unavailable on production deployments, public hosts, inactive sample accounts or a non-sample business.

Receiving now includes **Добавить вручную** for a new product without a barcode and name search for an existing product. Warranty months and batch expiry (`ДД.ММ.ГГГГ`, or ISO `YYYY-MM-DD`) are optional. Stock appears on catalog cards; filters find expired batches or dates within 30 days. These are in-app warnings for dated remaining batches, not push notifications. Existing undated stock stays undated.

For your own testing. One program starts everything: the database, the server, the web app, the install page and the Android app. Nothing to sign up for, nothing is opened to the internet.

Status (2026-10-26): the source launcher runs on this Mac with existing data retained. A separate disposable Mac shop passed 783 backend tests on PostgreSQL and the focused receiving/camera browser checks; see HANDOFF.md for scope. Earlier Linux verification covered 682 backend tests and 216 browser checks. Tried on **Windows 11** from source (not the `ERP-Test.zip` download): the database, browser app and Android emulator (`http://10.0.2.2:8000`) work once **Git for Windows** is installed (see "Good to know"). Physical phone acceptance remains pending.

## The easiest way: one download

1. On GitHub open **Releases** > **Latest test build** (`github.com/AzatKabulov/ERP-System/releases/tag/test-build`) and download **`ERP-Test.zip`**.
2. Unzip it. **Windows:** double-click `START.bat`. **Mac:** double-click `START.command` (first time: right-click > Open).
3. When the window says **Running**, open `http://localhost:8000`, sign in as `owner` with the printed password. For a phone: open the printed `.../install/` address on the same Wi-Fi, install the app, then in the app Server > Change > that address.

Nothing else to install: the package carries the tool that starts it, and the first start downloads the rest once. The longer route below does the same thing from the source code.

## What you need (the longer route)

- Windows 10/11 or a Mac, and the internet for the first start (about 250 MB: Python, the libraries and the database program are downloaded once).
- The small tool **uv** (below). It brings its own Python; you install nothing else.
- For the camera test: an Android tablet or phone on the **same Wi-Fi**.

## Steps

1. **Install uv** (once).
   - Windows: open PowerShell and run `powershell -ExecutionPolicy ByPass -c "irm https://astral.sh/uv/install.ps1 | iex"`, then close PowerShell.
   - Mac: open Terminal and run `curl -LsSf https://astral.sh/uv/install.sh | sh`, then close Terminal.
2. **Download two things from GitHub** and leave both in your Downloads folder:
   - the code: open the branch `claude/laughing-faraday-3dkwcb` on GitHub, Code > Download ZIP, then unzip it;
   - the app: Actions > the latest green **CI** run of the branch > Artifacts > `erp-system-test-build` (do not unzip it).
3. **Start it.**
   - Windows: double-click `scripts\local\start_local.bat` in the unzipped folder.
   - Mac (or any computer): open Terminal in the unzipped folder and run
     `uv run --project backend --with pixeltable-pgserver==0.6.0 python scripts/local/run_local.py`
   The first start takes a few minutes. When it says **Running**, it prints the addresses and a password. **Write the password down**: it is shown once.
4. **Open it.** On this computer go to `http://localhost:8000/`. Sign in as `owner` (or `manager`, `sales`, `warehouse`: the four roles of the test shop, all with the printed password), so you can try what each role sees.
5. **Tablet (camera):** on the same Wi-Fi open the printed `http://<address>:8000/install/`, install the app (allow "install from this source"; "Install anyway" if Play Protect warns), open it, tap **Server > Change** and type `http://<address>:8000`.

To stop: press Ctrl+C in the window (or close it). To start again: the same command; everything you entered is kept in the folder `local-data` next to the code. To start from nothing: stop it and delete `local-data`. If you lost the password: start with `--reset-password` added to the command.

## If you have Flutter: run the web app yourself (no download of the test build)

The web app is the same app, built for browsers. With Flutter installed you can start it the usual way and skip the GitHub download of the app:

1. Start the server and database as in step 3 (the web page it prints may say "No web app found": that is fine, the server is running on port 8000).
2. In a second terminal: `cd mobile && flutter run -d chrome --web-port 8080 --dart-define=API_BASE_URL=http://localhost:8000`
3. Chrome opens the app on `http://localhost:8080`; sign in as `owner` with the printed password. Edits to the code reload as usual.

Or build it once and let the server show it on port 8000: `cd mobile && flutter build web --no-web-resources-cdn`, then start the server with `--web mobile/build/web`.

### Sign in from an iPhone or another browser on the same Wi-Fi

The normal web build needs HTTPS for its secure session storage. `http://localhost` works on the computer, but `http://192.168.x.x:8000` on a phone is not a secure browser origin: the server can accept the password while the app fails to save the session.

For this local test server only, build with `cd mobile && flutter build web --no-web-resources-cdn --dart-define=LOCAL_HTTP_TESTING=true`, then start with `--web mobile/build/web`. On a private IPv4 address (`10.x.x.x`, `172.16.x.x` through `172.31.x.x`, or `192.168.x.x`) the web app then keeps its session in the tab's memory, without saving tokens to browser storage. Refreshing or closing the page requires signing in again; saved pending operations are recovered after signing in. Open the phone's local address again after replacing an older build.

The option defaults to false and does not affect native apps, HTTPS or public hosts. Do not use it for a public or production deployment: use HTTPS there. The local HTTP test server is only for test data on a trusted Wi-Fi network.

### Test with the MacBook webcam

Open `http://localhost:8000/` on the MacBook (rather than its Wi-Fi IP address). In Sales click the scan icon beside search; in receiving click the camera button. Receiving immediately opens a single form with product details, quantity and both manual prices. Available online name, brand, category and package size are suggested for review, without overwriting your edits. Allow the browser's camera request. If macOS blocks access, enable the browser in System Settings > Privacy & Security > Camera and reopen the scanner. The camera opens only after clicking Scan; closing the scanner stops it. A scanned sales item appears in search without being added to the cart. Show a clear barcode to the webcam; focus and lighting still need checking with the actual device.

The pinned scanner plugin may download its pinned ZXing decoder from jsDelivr when the browser has no native barcode detector, so that first scan needs internet access. No new dependency was added. A webcam without a flashlight does not show the torch control. Denied access or a missing camera offers manual code entry.

## Good to know

- The local launcher prepares gzip versions of public web resources once at startup, reducing the data downloaded over Wi-Fi. Browsers negotiate compression automatically; build files still revalidate after updates. Private API files and APK downloads are not compressed by this helper. If replacing the web build manually, restart the launcher so it prepares the new compressed resources; stale compressed files are never served in place of newer originals.

- Browser camera scanning is available at `http://localhost:8000/` on this computer or on HTTPS. Click the scan icon and allow camera access. Plain HTTP LAN addresses such as `http://192.168.x.x:8000` cannot use the browser camera; use HTTPS or the installed Android app there. Manual entry and keyboard-style scanners remain available.
- Windows may ask whether the program may accept connections: allow it on private networks (the tablet needs that).
- If port 8000 is taken, add `--port 8001` to the command.
- The database here is a PostgreSQL program carried by a Python package (`pixeltable-pgserver`, PostgreSQL 18); the real servers use PostgreSQL 16 in Docker. The server code is the same. It is a development server for testing: do not keep real shop data in it, and do not leave it open on an untrusted network.
- The database program cannot run from an elevated "Run as administrator" window: use a normal window.
- **Windows needs Git for Windows** (free, https://git-scm.com/download/win). The Windows build of the database program leaves out one library (`libwinpthread-1.dll`) and Git carries it; `run_local.py` finds it by itself. Without it the start stops with a message saying so (the raw error is `0xC0000135`). The `ERP-Test.zip` start has the same need.
- **Android emulator:** the app inside the emulator reaches this computer at `http://10.0.2.2:8000` (type it at Server > Change; `127.0.0.1` there means the emulator itself). A debug build allows plain `http`.
- The test app is a debug build signed with a throwaway key. When a newer test build comes out, remove the old app from the tablet before installing the new one (the data lives on the computer, not on the tablet).

## Phone camera over private Wi-Fi HTTPS (2026-10-26)

Phone browsers require a [trusted secure origin for camera access](https://developer.mozilla.org/en-US/docs/Web/API/MediaDevices/getUserMedia). Opening the
laptop's `http://192.168...:8000` address cannot enable the camera. Keep the normal
local launcher running, then from the repository root run:

```sh
python3 scripts/local/serve_https.py --address <laptop-private-Wi-Fi-IPv4>
```

Requires Python 3.13 and OpenSSL. It prints `https://<address>:8443/` and the path
to `local-data/https/phone-test-ca.crt`. Transfer **only that public certificate**
to the test phone and install/trust it using the phone's certificate settings.
On iOS, a manually installed root also needs full trust under Settings → General
→ About → Certificate Trust Settings ([Apple instructions](https://support.apple.com/en-us/102390)). The browser must show a trusted connection;
accepting a warning is not sufficient. Then open the printed HTTPS address and
allow camera permission. The laptop and phone must share the private Wi-Fi.

The helper binds only the chosen private address, forwards only to the local
launcher, and creates no public tunnel. Private keys stay outside the served web
directory and must never be transferred or committed. The server certificate
lasts seven days; restart the helper to issue another. The local CA lasts 30 days;
use a new TLS data folder and trust its new public CA after expiration. Stop the
helper with Ctrl+C. For ordinary hosted use, use the existing Caddy/domain HTTPS
deployment instead; phones should not need a custom CA there.
