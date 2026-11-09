"""Exercise a disposable shop over HTTP, race sales, then restore its database and files.

Run from the repository root with the pinned backend environment plus
pixeltable-pgserver==0.6.0. No existing database, .env or local-data is modified.
Optional --browser-script runs a current Flutter workflow against this same scratch shop.
"""

import argparse
import atexit
import hashlib
import importlib.util
import io
import json
import os
import secrets
import shutil
import subprocess
import sys
import tempfile
import threading
import time
import urllib.error
import urllib.request
import uuid
from collections import Counter
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta
from decimal import Decimal
from pathlib import Path
from zoneinfo import ZoneInfo

ROOT = Path(__file__).resolve().parents[2]


def require(ok, message):
    if not ok:
        raise AssertionError(message)
    print(f"PASS {message}", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--browser-script", type=Path)
    parser.add_argument("--node", default="node")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    data = Path(tempfile.mkdtemp(prefix="erp-readiness-"))
    atexit.register(shutil.rmtree, data, ignore_errors=True)
    spec = importlib.util.spec_from_file_location(
        "local_runner", ROOT / "scripts/local/run_local.py"
    )
    runner = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(runner)
    db = runner.start_database(data)
    runner.ensure_database(db)
    os.environ.update(
        DJANGO_ENV="development",
        DJANGO_DEBUG="false",
        DJANGO_SECRET_KEY=secrets.token_urlsafe(48),
        DJANGO_ALLOWED_HOSTS="localhost,127.0.0.1,testserver",
        DJANGO_SETTINGS_MODULE="local_settings",
        POSTGRES_HOST=db["host"],
        POSTGRES_PORT=db["port"],
        POSTGRES_USER=db["user"],
        POSTGRES_PASSWORD=db["password"],
        POSTGRES_DB="erp",
        PRIVATE_FILES_ROOT=str(data / "private_files"),
        ERP_LOCAL_WEB_ROOT=str(ROOT / "mobile/build/web"),
        ERP_BARCODE_LOOKUP="false",
        ERP_SAMPLE_PASSWORD=secrets.token_urlsafe(30),
        DJANGO_LOG_LEVEL="ERROR",
    )
    sys.path[:0] = [str(ROOT / "backend"), str(ROOT / "scripts/local")]
    import django

    django.setup()
    from django.core.management import call_command
    from django.core.servers.basehttp import ThreadedWSGIServer, WSGIRequestHandler
    from django.core.wsgi import get_wsgi_application
    from django.db import connections

    for command in ("migrate", "createcachetable", "create_sample_business"):
        call_command(command, stdout=io.StringIO(), verbosity=0)
    with connections["default"].cursor() as cursor:
        cursor.execute("SHOW server_version")
        database_version = cursor.fetchone()[0]
    call_command("check")
    call_command("makemigrations", check=True, dry_run=True, verbosity=0)

    class QuietHandler(WSGIRequestHandler):
        def log_message(self, *values):
            pass

    server = ThreadedWSGIServer(("127.0.0.1", 0), QuietHandler)
    server.daemon_threads = True
    server.set_app(get_wsgi_application())
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    origin = f"http://127.0.0.1:{server.server_port}"
    timings = []
    tokens = {}

    def http(path, *, method="GET", body=None, role="owner", key=None, raw=None, content=None):
        headers = {}
        if role in tokens:
            headers["Authorization"] = f"Bearer {tokens[role]}"
        if key:
            headers["Idempotency-Key"] = key
        payload = raw
        if body is not None:
            payload = json.dumps(body).encode()
            headers["Content-Type"] = "application/json"
        if content:
            headers["Content-Type"] = content
        request = urllib.request.Request(origin + path, payload, headers, method=method)
        started = time.perf_counter()
        try:
            response = urllib.request.urlopen(request, timeout=45)
        except urllib.error.HTTPError as error:
            response = error
        with response:
            value = response.read()
            status = response.status
            kind = response.headers.get("Content-Type", "")
        timings.append(
            {
                "path": path.split("?")[0],
                "method": method,
                "status": status,
                "ms": round((time.perf_counter() - started) * 1000, 2),
            }
        )
        return status, json.loads(value) if "application/json" in kind else value

    def api(path, *, expected=200, **kwargs):
        status, value = http(path, **kwargs)
        if status != expected:
            raise AssertionError(
                f"{kwargs.get('method', 'GET')} {path}: {status}, {str(value)[:500]}"
            )
        return value

    def post(path, body, *, expected=201, key=None, **kwargs):
        return api(
            path,
            method="POST",
            body=body,
            key=key or str(uuid.uuid4()),
            expected=expected,
            **kwargs,
        )

    try:
        for role in ("owner", "manager", "sales", "warehouse"):
            tokens[role] = post("/api/v1/local-test-login/", {"role": role}, expected=200)["access"]
        me = api("/api/v1/me/")
        base = f"/api/v1/businesses/{me['memberships'][0]['business']['id']}"
        today = datetime.now(ZoneInfo(api(base + "/")["timezone"])).date()
        locations = api(base + "/locations/")["results"]
        store = next(x["id"] for x in locations if x["name"] == "Main store")
        warehouse = next(x["id"] for x in locations if x["name"] == "Warehouse")
        unit = next(x["id"] for x in api(base + "/units/")["results"] if x["symbol"] == "шт")
        product = post(
            base + "/products/",
            {
                "sku": "QA-PAD",
                "name": "Тормозные колодки ÄŇŞ Ёё",
                "unit": unit,
                "price_amount": "125.50",
                "price_currency": "TMT",
                "warranty_months": 12,
                "return_days": 30,
                "barcodes": ["4006381333931"],
            },
        )
        product_id = product["id"]
        expiry = (today + timedelta(days=7)).isoformat()
        receipt_body = {
            "location": store,
            "lines": [
                {
                    "product": product_id,
                    "quantity": "50",
                    "unit_cost": "60.25",
                    "expiry_date": expiry,
                }
            ],
        }
        receipt_key = str(uuid.uuid4())
        receipt = post(base + "/intakes/", receipt_body, key=receipt_key)
        replay = post(base + "/intakes/", receipt_body, key=receipt_key)
        require(receipt["id"] == replay["id"], "receiving retry creates one receipt")
        sale = post(
            base + "/sales/",
            {
                "location": store,
                "payment_method": "card",
                "lines": [{"product": product_id, "quantity": "3", "unit_price": "110.25"}],
            },
            role="sales",
        )
        require(sale["total"] == "330.75", "seller's chosen price gives exact sale total")
        for lang in ("ru", "tk"):
            pdf = api(base + f"/sales/{sale['id']}/document/?lang={lang}")
            from pypdf import PdfReader

            text = "".join(page.extract_text() for page in PdfReader(io.BytesIO(pdf)).pages)
            require(
                product["name"] in text, f"{lang} receipt retains Cyrillic and Turkmen product name"
            )
        returned = post(
            base + f"/sales/{sale['id']}/returns/",
            {
                "reason": "QA return",
                "lines": [
                    {"sale_line": sale["lines"][0]["id"], "quantity": "1", "condition": "sellable"}
                ],
            },
            role="sales",
        )
        require(returned["refund_total"] == "110.25", "return refunds price actually charged")
        transfer = post(
            base + "/transfers/",
            {
                "from_location": store,
                "to_location": warehouse,
                "lines": [{"product": product_id, "quantity": "10"}],
            },
        )
        post(base + f"/transfers/{transfer['id']}/receive/", {}, expected=200, role="warehouse")
        count = post(
            base + "/counts/", {"location": store, "scope": "partial", "products": [product_id]}
        )
        api(
            base + f"/counts/{count['id']}/lines/",
            method="PUT",
            body={"lines": [{"product": product_id, "counted_quantity": "37"}]},
        )
        post(base + f"/counts/{count['id']}/submit/", {}, expected=200)
        post(
            base + f"/counts/{count['id']}/approve/",
            {"reason": "QA one damaged unit"},
            expected=200,
        )
        claim = post(
            base + "/warranty-claims/",
            {"sale_line": sale["lines"][0]["id"], "quantity": "1", "problem": "QA repair"},
            role="sales",
        )
        post(
            base + f"/warranty-claims/{claim['id']}/close/",
            {"outcome": "repair", "note": "QA repaired"},
            expected=200,
        )
        image = io.BytesIO()
        from PIL import Image

        Image.new("RGB", (12, 12), "white").save(image, "PNG")
        boundary = secrets.token_hex(16)
        raw = (
            (
                f'--{boundary}\r\nContent-Disposition: form-data; name="file"; '
                'filename="qa.png"\r\n'
                "Content-Type: image/png\r\n\r\n"
            ).encode()
            + image.getvalue()
            + f"\r\n--{boundary}--\r\n".encode()
        )
        attachment = api(
            base + "/attachments/",
            method="POST",
            expected=201,
            raw=raw,
            content=f"multipart/form-data; boundary={boundary}",
        )
        category = api(base + "/expense-categories/")["results"][0]["id"]
        post(
            base + "/expenses/",
            {
                "category": category,
                "location": store,
                "amount": "25.50",
                "spent_on": today.isoformat(),
                "description": "QA transport",
                "attachment": attachment["id"],
            },
        )
        require(
            api(base + f"/attachments/{attachment['id']}/") == image.getvalue(),
            "private expense receipt downloads intact",
        )
        api(base + f"/attachments/{attachment['id']}/", role="sales", expected=403)
        for role in ("sales", "warehouse"):
            api(base + "/reports/summary/", role=role, expected=403)
            shown = api(base + f"/products/{product_id}/", role=role)
            require("default_purchase_cost" not in shown, f"{role} cannot read purchase cost")
        summary = api(base + "/reports/summary/")
        require(
            Decimal(summary["gross_profit"]) == Decimal("100.00"),
            "FIFO gross profit matches two retained units",
        )
        require(
            Decimal(summary["expenses"]) == Decimal("25.50"),
            "expense report matches posted receipt",
        )
        require(Decimal(summary["result"]) == Decimal("74.50"), "operating result reconciles")
        require(
            api(base + f"/products/{product_id}/?location={store}")["stock"]["on_hand"] == "37.000",
            "sale, return, transfer and count leave expected store stock",
        )
        require(
            api(base + f"/products/{product_id}/?location={warehouse}")["expiry"]["date"] == expiry,
            "transferred batch retains expiry",
        )
        require(
            api(base + f"/products/{product_id}/", role="sales")["stock"]["on_hand"] == "37.000",
            "sales role cannot see warehouse quantity",
        )
        require(
            api(base + "/catalog/export/").startswith(b"\xef\xbb\xbf"),
            "catalog export is UTF-8 with BOM",
        )
        require(
            http(
                base.replace(me["memberships"][0]["business"]["id"], str(uuid.uuid4()))
                + "/products/"
            )[0]
            == 404,
            "another business scope is denied",
        )
        require(
            http(base + "/products/", role="anonymous")[0] == 401,
            "unauthenticated catalog is denied",
        )
        for query in ("category=invalid", "brand=invalid", "expiry=invalid"):
            api(base + "/products/?" + query, expected=400)
        api(base + "/reports/summary/?date_from=2026-99-99", expected=400)
        for quantity in ("-1", "0", "NaN", "Infinity", "1.5"):
            post(
                base + "/sales/",
                {
                    "location": store,
                    "lines": [{"product": product_id, "quantity": quantity, "unit_price": "1.00"}],
                },
                expected=400,
            )
        api(base + f"/sales/{sale['id']}/", method="PATCH", body={"total": "0"}, expected=405)
        require(
            api(base + f"/products/{product_id}/?location={store}")["stock"]["on_hand"] == "37.000",
            "malformed filters, invalid quantities and finalized-record edits change no stock",
        )
        # A realistic stock race: 40 independent tills compete for 37 remaining pieces.
        body = {
            "location": store,
            "lines": [{"product": product_id, "quantity": "1", "unit_price": "125.50"}],
        }

        def sell(_):
            return http(
                base + "/sales/", method="POST", body=body, role="sales", key=str(uuid.uuid4())
            )[0]

        with ThreadPoolExecutor(max_workers=12) as pool:
            statuses = Counter(pool.map(sell, range(40)))
        require(
            statuses == {201: 37, 409: 3},
            "40 competing sales sell exactly 37 available units; no 500 or oversell",
        )
        body["location"] = warehouse
        shared_key = str(uuid.uuid4())
        with ThreadPoolExecutor(max_workers=8) as pool:
            copies = list(
                pool.map(
                    lambda _: http(base + "/sales/", method="POST", body=body, key=shared_key),
                    range(8),
                )
            )
        require(
            all(s == 201 for s, _ in copies) and len({v["id"] for _, v in copies}) == 1,
            "eight concurrent retries create exactly one sale",
        )
        # Bounded read load exposes errors and latency; it is not a server capacity claim.
        paths = ["/products/?limit=30", "/stock/?limit=30", "/dashboard/", "/reports/summary/"]
        before = len(timings)
        with ThreadPoolExecutor(max_workers=12) as pool:
            list(pool.map(lambda i: api(base + paths[i % len(paths)]), range(120)))
        read_times = sorted(t["ms"] for t in timings[before:])
        require(len(read_times) == 120, "120 mixed concurrent reads succeed")
        call_command("reconcile_stock")
        if args.browser_script:
            subprocess.run(
                [args.node, str(args.browser_script.resolve())],
                cwd=ROOT,
                env={**os.environ, "ERP_E2E_DISPOSABLE": "true", "E2E_WEB_URL": origin + "/"},
                check=True,
            )
        call_command("reconcile_stock")
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=5)
        connections.close_all()

    # Restore into a second database in the disposable cluster, never into the source shop.
    import pixeltable_pgserver
    import psycopg
    from psycopg import sql

    pg_dump = next(Path(pixeltable_pgserver.__file__).parent.rglob("pg_dump"))
    pg_restore = pg_dump.with_name("pg_restore")
    pg_env = {
        **os.environ,
        "PGHOST": db["host"],
        "PGPORT": db["port"],
        "PGUSER": db["user"],
        "PGPASSWORD": db["password"],
    }
    dump = data / "shop.dump"
    subprocess.run(
        [str(pg_dump), "-Fc", "--no-owner", "-d", "erp", "-f", str(dump)], env=pg_env, check=True
    )
    connect = {
        "host": db["host"],
        "port": db["port"],
        "user": db["user"],
        "password": db["password"],
    }
    with psycopg.connect(**connect, dbname="postgres", autocommit=True) as conn:
        conn.execute("CREATE DATABASE readiness_restored")
    subprocess.run(
        [str(pg_restore), "--no-owner", "--exit-on-error", "-d", "readiness_restored", str(dump)],
        env=pg_env,
        check=True,
    )

    def contents(name):
        with psycopg.connect(**connect, dbname=name) as conn:
            tables = conn.execute(
                "SELECT tablename FROM pg_tables WHERE schemaname='public' ORDER BY tablename"
            ).fetchall()
            return {
                table: conn.execute(
                    sql.SQL(
                        "SELECT count(*), md5(coalesce(string_agg(row_to_json(t)::text, "
                        "E'\\n' ORDER BY row_to_json(t)::text), '')) FROM {} t"
                    ).format(sql.Identifier(table))
                ).fetchone()
                for (table,) in tables
            }

    require(
        contents("erp") == contents("readiness_restored"),
        "restored database matches every public table's row count and content digest",
    )
    restored_files = data / "restored_files"
    shutil.copytree(data / "private_files", restored_files)

    def hashes(folder):
        return {
            str(p.relative_to(folder)): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in folder.rglob("*")
            if p.is_file()
        }

    original_hashes = hashes(data / "private_files")
    require(
        bool(original_hashes) and original_hashes == hashes(restored_files),
        "restored private file bytes match source hashes",
    )
    from django.conf import settings

    connections["default"].settings_dict["NAME"] = "readiness_restored"
    settings.PRIVATE_FILES_ROOT = restored_files
    call_command("reconcile_stock")
    result = {
        "database_version": database_version,
        "store_workflows": "passed",
        "sale_race": dict(statuses),
        "duplicate_retries": 8,
        "mixed_reads": {
            "requests": 120,
            "concurrency": 12,
            "p50_ms": read_times[59],
            "p95_ms": read_times[113],
            "max_ms": read_times[-1],
        },
        "restore": {
            "tables": len(contents("readiness_restored")),
            "private_files": len(original_hashes),
        },
        "requests": timings,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2) + "\n")
    connections.close_all()
    print("PASS disposable store, load and restore drill complete", flush=True)


if __name__ == "__main__":
    main()
