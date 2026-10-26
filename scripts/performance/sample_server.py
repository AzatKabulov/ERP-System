"""Disposable, deterministic sample shop for navigation profiling; never existing business data."""

import argparse
import importlib.util
import os
import secrets
import sys
from decimal import Decimal
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser()
parser.add_argument("--data", type=Path, required=True)
parser.add_argument("--web", type=Path, required=True)
parser.add_argument("--port", type=int, default=8001)
args = parser.parse_args()
data = args.data.resolve()
marker = data / ".performance-sample"
if data.exists() and any(data.iterdir()) and not marker.is_file():
    parser.error("Refusing a nonempty folder without the performance-sample marker.")
data.mkdir(parents=True, exist_ok=True)
marker.touch()
password = data / "password"
if not password.exists():
    password.write_text(secrets.token_urlsafe(24))
    password.chmod(0o600)
os.environ["ERP_SAMPLE_PASSWORD"] = password.read_text()
os.environ["ERP_BARCODE_LOOKUP"] = "false"
spec = importlib.util.spec_from_file_location(
    "performance_local_runner", ROOT / "scripts/local/run_local.py"
)
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)
original_extract = runner.extract_build


def prepare(*values):
    from apps.accounts.models import User
    from apps.businesses.models import Business
    from apps.catalog import services
    from apps.catalog.models import Category, Product, Unit

    business = Business.objects.get(name="Sample Auto Parts (test data)")
    owner = User.objects.get(username="owner")
    unit = Unit.objects.get(business=business, symbol="шт")
    category, _ = Category.objects.get_or_create(business=business, name="Test parts")
    if not Product.objects.filter(business=business).exists():
        for index in range(300):
            services.create_product(
                business,
                owner,
                {
                    "sku": f"PERF-{index:04d}",
                    "name": f"{index:04d} Фильтр масляный ÄŇŞ для двигателя, контрольный товар",
                    "unit": unit,
                    "category": category,
                    "price_amount": Decimal("125.50"),
                    "price_currency": "TMT",
                    "barcodes": [],
                },
            )
    if Product.objects.filter(business=business).count() != 300:
        raise RuntimeError("Performance fixture changed; use a fresh disposable folder.")
    return original_extract(*values)


runner.extract_build = prepare
original_say = runner.say
runner.say = lambda text="": None if "Password for all four" in text else original_say(text)
sys.argv = [
    str(ROOT / "scripts/local/run_local.py"),
    "--data",
    str(data),
    "--web",
    str(args.web.resolve()),
    "--port",
    str(args.port),
]
runner.main()
