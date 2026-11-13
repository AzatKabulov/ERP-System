"""Product information for a scanned barcode (GTIN), from public open databases.

The server asks, never the app: Open Beauty Facts first (cosmetics and care products), then Open
Products Facts, then Open Food Facts. They are free, need no key and are built by volunteers, so
a code that is missing there is common, above all for local goods. A miss is normal and not an
error: the person simply types the name.

What leaves the server is the barcode digits and nothing else (no business, no user, no stock).
Answers are cached in the shared database cache: hits for 30 days, complete misses for 5 minutes.
A network or partial-source failure is not cached and is reported as "unavailable". Set
`ERP_BARCODE_LOOKUP=false` to send nothing out at all.
"""

import json
import re
import urllib.error
import urllib.request
from dataclasses import dataclass
from datetime import UTC, datetime
from time import monotonic

from django.conf import settings
from django.core.cache import cache

SOURCES = (
    ("Open Beauty Facts", "https://world.openbeautyfacts.org/api/v2/product/{code}.json"),
    ("Open Products Facts", "https://world.openproductsfacts.org/api/v2/product/{code}.json"),
    ("Open Food Facts", "https://world.openfoodfacts.org/api/v2/product/{code}.json"),
)
FIELDS = (
    "code,product_name,generic_name,product_name_ru,product_name_en,product_name_tk,"
    "brands,quantity,categories"
)
USER_AGENT = "ERP-System/1.0 (inventory app; barcode lookup by the shop's own server)"
MAX_BYTES = 1_000_000
HIT_SECONDS = 30 * 24 * 3600
MISS_SECONDS = 5 * 60
NAME_MAX = 255
LOOKUP_BUDGET_SECONDS = 10


@dataclass(frozen=True)
class Info:
    found: bool
    name: str = ""
    brand: str = ""
    quantity: str = ""
    source: str = ""
    category: str = ""
    unavailable: bool = False


def valid_gtin(code: str) -> bool:
    """GTIN-8, -12, -13 or -14: digits only, with a correct check digit (a mistyped or cut-off
    code is refused before anything is asked)."""
    if not re.fullmatch(r"[0-9]{8}|[0-9]{12,14}", code):
        return False
    digits = [int(c) for c in code]
    body, check = digits[:-1], digits[-1]
    total = sum(d * (3 if i % 2 == 0 else 1) for i, d in enumerate(reversed(body)))
    return (10 - total % 10) % 10 == check


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        return None


def _fetch(url: str, *, timeout: float | None = None) -> dict | None:
    """The JSON at `url`; None when the database has no such product (404). Network problems
    and bad answers raise."""
    opener = urllib.request.build_opener(_NoRedirect)
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    try:
        with opener.open(request, timeout=timeout or settings.BARCODE_LOOKUP_TIMEOUT) as response:
            return json.loads(response.read(MAX_BYTES))
    except urllib.error.HTTPError as error:
        if error.code == 404:
            return None
        raise


def _clean(text) -> str:
    return " ".join(text.split()) if isinstance(text, str) else ""


def _info(product: dict, source: str) -> Info | None:
    name = next(
        (
            value
            for key in (
                "product_name",
                "generic_name",
                "product_name_ru",
                "product_name_tk",
                "product_name_en",
            )
            if (value := _clean(product.get(key)))
        ),
        "",
    )
    if not name:
        return None
    brand = _clean(product.get("brands")).split(",")[0].strip()
    return Info(
        found=True,
        name=name[:NAME_MAX],
        brand=brand[:100],
        quantity=_clean(product.get("quantity"))[:50],
        source=source,
        category=_clean(product.get("categories")).split(",")[-1].strip()[:100],
    )


def canonical_gtin(code: str) -> str:
    """GS1's 14-digit representation; nonzero carton indicators remain intact."""
    return code.zfill(14)


def _fetch_before(url: str, deadline: float) -> dict | None:
    remaining = deadline - monotonic()
    if remaining <= 0:
        raise TimeoutError("Barcode lookup budget exhausted")
    return _fetch(url, timeout=min(settings.BARCODE_LOOKUP_TIMEOUT, remaining))


def _reserve(provider: str, daily_limit: int, interval: int, deadline: float) -> bool:
    if monotonic() >= deadline:
        return False
    if not cache.add(f"barcode:{provider}:gate", True, timeout=interval):
        return False
    day = datetime.now(UTC).date().isoformat()
    counter = f"barcode:{provider}:day:{day}"
    used = cache.get(counter, 0)
    if used >= daily_limit:
        return False
    cache.set(counter, used + 1, timeout=2 * 24 * 3600)
    return True


def _upcitemdb(code: str, deadline: float) -> Info:
    """Exact-code metadata within the public trial's daily and burst limits."""
    if not _reserve("upcitemdb", 100, 11, deadline):
        return Info(found=False, unavailable=True)
    try:
        data = _fetch_before(f"https://api.upcitemdb.com/prod/trial/lookup?upc={code}", deadline)
    except (OSError, ValueError):
        return Info(found=False, unavailable=True)
    if not isinstance(data, dict) or data.get("code") != "OK":
        return Info(found=False, unavailable=True)
    items = data.get("items")
    if not isinstance(items, list):
        return Info(found=False, unavailable=True)
    for item in items:
        if not isinstance(item, dict):
            return Info(found=False, unavailable=True)
        identifiers = [_clean(item.get(key)) for key in ("ean", "upc", "gtin")]
        if not any(
            value and canonical_gtin(value) == canonical_gtin(code) for value in identifiers
        ):
            continue
        info = _info(
            {
                "product_name": item.get("title"),
                "brands": item.get("brand"),
                "quantity": item.get("size"),
                "categories": item.get("category"),
            },
            "UPCitemdb",
        )
        if info is not None:
            return info
    return Info(found=False, unavailable=bool(items))


def _gtinhub(code: str, deadline: float) -> Info:
    """Additional documented no-key tier; never accept a mismatched identifier."""
    if not _reserve("gtinhub", 10, 1, deadline):
        return Info(found=False, unavailable=True)
    try:
        data = _fetch_before(f"https://gtinhub.com/api/v1/product/{code}", deadline)
    except (OSError, ValueError):
        return Info(found=False, unavailable=True)
    if data is None or (isinstance(data, dict) and data.get("found") is False):
        return Info(found=False)
    if not isinstance(data, dict) or data.get("found") is not True:
        return Info(found=False, unavailable=True)
    product = data.get("product")
    if not isinstance(product, dict):
        return Info(found=False, unavailable=True)
    returned_code = _clean(product.get("gtin"))
    if not returned_code or canonical_gtin(returned_code) != canonical_gtin(code):
        return Info(found=False, unavailable=True)
    info = _info(
        {
            "product_name": product.get("name"),
            "brands": product.get("brand"),
            "categories": product.get("category"),
        },
        "GTINHub",
    )
    return info or Info(found=False, unavailable=True)


def lookup(code: str) -> Info:
    """What the open databases know about this (valid) barcode."""
    if not settings.BARCODE_LOOKUP_ENABLED:
        return Info(found=False, unavailable=True)
    extra = settings.BARCODE_LOOKUP_UPCITEMDB_ENABLED
    hub = settings.BARCODE_LOOKUP_GTINHUB_ENABLED
    key = f"gtin:v5:{int(extra)}:{int(hub)}:{canonical_gtin(code)}"
    cached = cache.get(key)
    if cached is not None:
        return Info(**cached)
    deadline = monotonic() + LOOKUP_BUDGET_SECONDS
    failed = False
    for source, template in SOURCES:
        url = template.format(code=code) + f"?fields={FIELDS}"
        try:
            data = _fetch_before(url, deadline)
        except (OSError, ValueError):  # no connection, a timeout, an answer that is not JSON
            failed = True
            continue
        if data is not None and not isinstance(data, dict):
            failed = True
            continue
        if data is not None and data.get("status") not in (0, 1):
            failed = True
            continue
        if data and data.get("status") == 1 and isinstance(data.get("product"), dict):
            product = data["product"]
            returned_code = _clean(product.get("code"))
            if returned_code and canonical_gtin(returned_code) != canonical_gtin(code):
                failed = True
                continue
            info = _info(product, source)
            if info is not None:
                cache.set(key, info.__dict__, HIT_SECONDS)
                return info
    if extra:
        info = _upcitemdb(code, deadline)
        if info.found:
            cache.set(key, info.__dict__, HIT_SECONDS)
            return info
        failed = failed or info.unavailable
    if hub:
        info = _gtinhub(code, deadline)
        if info.found:
            cache.set(key, info.__dict__, HIT_SECONDS)
            return info
        failed = failed or info.unavailable
    if failed:
        return Info(found=False, unavailable=True)
    miss = Info(found=False)
    cache.set(key, miss.__dict__, MISS_SECONDS)
    return miss
