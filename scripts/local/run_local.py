#!/usr/bin/env python3
"""The whole system on your own computer, without Docker: an embedded PostgreSQL (a Python
package that carries the database program), this project's server, the web app, the install page
and the Android app, all started by one command.

    uv run --project backend --with pixeltable-pgserver==0.6.0 python scripts/local/run_local.py

(see docs/LOCAL_TEST.md). Everything is kept in the folder `local-data/` next to the code: delete
it to start from nothing. For testing only: it is a development server, not a place for real data.
"""

import argparse
import atexit
import os
import secrets
import shutil
import signal
import socket
import sys
import zipfile
from pathlib import Path
from urllib.parse import parse_qs, urlsplit

ROOT = Path(__file__).resolve().parents[2]
BACKEND = ROOT / "backend"
HERE = Path(__file__).resolve().parent
SAMPLE_USERS = ("owner", "manager", "sales", "warehouse")


def say(text=""):
    print(text, flush=True)


def fail(text):
    say(f"\nError: {text}")
    sys.exit(1)


def lan_address() -> str:
    """The address of this computer on the local network (no packet is sent)."""
    probe = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        probe.connect(("10.255.255.255", 1))
        return probe.getsockname()[0]
    except OSError:
        return ""
    finally:
        probe.close()


def download_places() -> list[Path]:
    places = [Path.home() / "Downloads", Path.home() / "downloads", Path.cwd(), ROOT]
    users = Path("/mnt/c/Users")  # Windows downloads seen from WSL
    if users.is_dir():
        places += [d / "Downloads" for d in users.iterdir()]
    return [p for p in places if p.is_dir()]


def newest(pattern: str) -> Path | None:
    found = [f for place in download_places() for f in place.glob(pattern) if f.is_file()]
    return max(found, key=lambda f: f.stat().st_mtime, default=None)


def extract_build(data: Path, web: Path | None, apk: Path | None) -> tuple[bool, bool]:
    """Put the web app and the Android file where the server looks for them. Takes what was
    given, else the newest test build found in the download folders. Returns (web, apk) found."""
    public = data / "public"
    work = data / "incoming"
    shutil.rmtree(work, ignore_errors=True)
    work.mkdir(parents=True)
    if web is None and apk is None:
        web = newest("erp-system-test-web*.zip")
        apk = newest("erp-system-test-debug*.apk")
        bundle = newest("erp-system-test-build*.zip")
        if (web is None or apk is None) and bundle is not None:
            say(f"   Found {bundle}")
            with zipfile.ZipFile(bundle) as z:
                z.extractall(work)
            web = next(work.glob("**/erp-system-test-web*.zip"), None)
            apk = next(work.glob("**/erp-system-test-debug*.apk"), None)
    got_web = got_apk = False
    if web is not None:
        target = public / "web"
        shutil.rmtree(target, ignore_errors=True)
        if web.is_dir():
            shutil.copytree(web, target)
        else:
            with zipfile.ZipFile(web) as z:
                z.extractall(target)
        got_web = (target / "index.html").is_file()
    if apk is not None:
        (public / "downloads").mkdir(parents=True, exist_ok=True)
        shutil.copyfile(apk, public / "downloads" / "erp.apk")
        got_apk = True
    shutil.rmtree(work, ignore_errors=True)
    return got_web, got_apk


def start_database(data: Path) -> dict:
    try:
        import pixeltable_pgserver as pgserver
    except ImportError:
        fail(
            "the embedded database package is missing. Start this program with:\n"
            "    uv run --project backend --with pixeltable-pgserver==0.6.0 "
            "python scripts/local/run_local.py"
        )
    say("   Starting the database (the first time it prepares its files)...")
    server = pgserver.get_server(data / "pgdata", cleanup_mode="stop")
    atexit.register(server.cleanup)
    uri = urlsplit(server.get_uri())
    query = parse_qs(uri.query)
    return {
        "host": query.get("host", [uri.hostname or "127.0.0.1"])[0],
        "port": str(uri.port or 5432),
        "user": uri.username or "postgres",
        "password": uri.password or "",
    }


def ensure_database(db: dict) -> None:
    import psycopg

    with psycopg.connect(
        host=db["host"],
        port=db["port"],
        user=db["user"],
        password=db["password"],
        dbname="postgres",
        autocommit=True,
    ) as conn:
        if not conn.execute("SELECT 1 FROM pg_database WHERE datname = 'erp'").fetchone():
            conn.execute("CREATE DATABASE erp ENCODING 'UTF8' LOCALE 'C' TEMPLATE template0")


def main() -> None:
    parser = argparse.ArgumentParser(description="The whole system on this computer, no Docker.")
    parser.add_argument("--port", type=int, default=8000)
    parser.add_argument(
        "--data", type=Path, default=ROOT / "local-data", help="where everything is kept"
    )
    parser.add_argument(
        "--web",
        type=Path,
        help="a web build folder or zip (default: the newest test build in Downloads)",
    )
    parser.add_argument(
        "--apk", type=Path, help="the Android test app (default: from the same download)"
    )
    parser.add_argument(
        "--reset-password", action="store_true", help="give the four test users a new password"
    )
    args = parser.parse_args()

    data: Path = args.data.resolve()
    for sub in ("pgdata", "private_files", "public/downloads"):
        (data / sub).mkdir(parents=True, exist_ok=True)

    say("1/4  Database")
    db = start_database(data)
    ensure_database(db)

    key_file = data / "secret_key"
    if not key_file.is_file():
        key_file.write_text(secrets.token_urlsafe(48))
    os.environ.update(
        DJANGO_ENV="development",  # sample users are allowed; never "production" here
        DJANGO_DEBUG="false",
        DJANGO_SECRET_KEY=key_file.read_text().strip(),
        DJANGO_ALLOWED_HOSTS="*",
        DJANGO_EMAIL_BACKEND="django.core.mail.backends.console.EmailBackend",
        POSTGRES_HOST=db["host"],
        POSTGRES_PORT=db["port"],
        POSTGRES_USER=db["user"],
        POSTGRES_PASSWORD=db["password"],
        POSTGRES_DB="erp",
        PRIVATE_FILES_ROOT=str(data / "private_files"),
        ERP_LOCAL_WEB_ROOT=str(data / "public" / "web"),
        ERP_LOCAL_DOWNLOADS=str(data / "public" / "downloads"),
        ERP_LOCAL_INSTALL_PAGE=str(ROOT / "infra" / "site" / "install"),
        DJANGO_SETTINGS_MODULE="local_settings",
    )
    sys.path[:0] = [str(BACKEND), str(HERE)]

    say("2/4  The server's own tables and the test shop")
    import django

    django.setup()
    from io import StringIO

    from django.core.management import call_command

    call_command("migrate", interactive=False, verbosity=0)
    call_command("createcachetable", verbosity=0)
    from apps.accounts.models import User
    from apps.businesses.models import Business

    password = ""
    if not Business.objects.exists():
        out = StringIO()
        call_command("create_sample_business", stdout=out)
        for line in out.getvalue().splitlines():
            if "Password for all four users" in line:
                password = line.split(":", 1)[1].strip()
        if not password:
            password = os.environ.get("ERP_SAMPLE_PASSWORD", "")
    elif args.reset_password:
        password = secrets.token_urlsafe(14)
        for user in User.objects.filter(username__in=SAMPLE_USERS):
            user.set_password(password)
            user.save()

    say("3/4  The web app and the Android app")
    got_web, got_apk = extract_build(data, args.web, args.apk)
    if not got_web and not (data / "public" / "web" / "index.html").is_file():
        say("   No web app found: the server runs, but its pages need the test build.")
        say("   Download  erp-system-test-build  from GitHub (Actions > the latest green run,")
        say("   Artifacts), leave the zip in your Downloads folder")
        say("   and start this program again.")
    elif got_apk or (data / "public" / "downloads" / "erp.apk").is_file():
        say("   Ready.")

    port = args.port
    ip = lan_address()
    say("4/4  Running. Leave this window open; press Ctrl+C to stop.")
    say()
    say(f"   On this computer:  http://localhost:{port}/")
    if ip:
        say(f"   On a tablet or phone on the same Wi-Fi:  http://{ip}:{port}/install/")
        say(f"   (install the app, then in the app: Server > Change > http://{ip}:{port})")
    say("   Users: owner, manager, sales, warehouse (the four roles of the test shop)")
    if password:
        say(f"   Password for all four (shown once): {password}")
    else:
        say("   The password was shown the first time. To set a new one: add  --reset-password")
    say()
    call_command("runserver", f"0.0.0.0:{port}", use_reloader=False, verbosity=1)


if __name__ == "__main__":
    # a closed window or a plain "stop" ends the program the same way as Ctrl+C, so the database
    # is stopped properly
    try:
        signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
    except (ValueError, OSError):
        pass
    try:
        main()
    except KeyboardInterrupt:
        say("\nStopped.")
