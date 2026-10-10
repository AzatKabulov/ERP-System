# Try the whole system on your own computer (no Docker)

For your own testing. One program starts everything: the database, the server, the web app, the install page and the Android app. Nothing to sign up for, nothing is opened to the internet.

Status (2026-10-10): checked on Linux (all 682 backend tests on this database, and the full browser run of 216 checks against it). **Not tried on Windows or on a Mac yet**: if something fails, send the last lines it printed.

## What you need

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

## Good to know

- The browser version has no camera button (browsers only allow the camera on `https`); a USB hand scanner works in it. The camera is tested on the tablet with the installed app.
- Windows may ask whether the program may accept connections: allow it on private networks (the tablet needs that).
- If port 8000 is taken, add `--port 8001` to the command.
- The database here is a PostgreSQL program carried by a Python package (`pixeltable-pgserver`, PostgreSQL 18); the real servers use PostgreSQL 16 in Docker. The server code is the same. It is a development server for testing: do not keep real shop data in it, and do not leave it open on an untrusted network.
- The database program cannot run from an elevated "Run as administrator" window: use a normal window.
- The test app is a debug build signed with a throwaway key. When a newer test build comes out, remove the old app from the tablet before installing the new one (the data lives on the computer, not on the tablet).
