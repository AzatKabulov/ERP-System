"""Product information for a scanned barcode (GTIN), from public open databases.

The server asks, never the app: Open Beauty Facts first (cosmetics and care products), then Open
Products Facts, then Open Food Facts. They are free, need no key and are built by volunteers, so
a code that is missing there is common, above all for local goods. A miss is normal and not an
error: the person simply types the name.

What leaves the server is the barcode digits and nothing else (no business, no user, no stock).
Answers are cached in the shared database cache (a hit for 30 days, a miss for 3), so a code is
asked about once. A network failure is not cached and is reported as "unavailable". Set
`ERP_BARCODE_LOOKUP=false` to send nothing out at all.
"""

import json
import re
import urllib.error
import urllib.request
from dataclasses import dataclass

from django.conf import settings
from django.core.cache import cache

SOURCES = (
    ("Open Beauty Facts", "https://world.openbeautyfacts.org/api/v2/product/{code}.json"),
    ("Open Products Facts", "https://world.openproductsfacts.org/api/v2/product/{code}.json"),
    ("Open Food Facts", "https://world.openfoodfacts.org/api/v2/product/{code}.json"),
)
FIELDS = "product_name,generic_name,brands,quantity,categories"
USER_AGENT = "ERP-System/1.0 (inventory app; barcode lookup by the shop's own server)"
MAX_BYTES = 1_000_000
HIT_SECONDS = 30 * 24 * 3600
MISS_SECONDS = 3 * 24 * 3600
NAME_MAX = 255


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
    if not re.fullmatch(r"\d{8}|\d{12,14}", code):
        return False
    digits = [int(c) for c in code]
    body, check = digits[:-1], digits[-1]
    total = sum(d * (3 if i % 2 == 0 else 1) for i, d in enumerate(reversed(body)))
    return (10 - total % 10) % 10 == check


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        return None


def _fetch(url: str) -> dict | None:
    """The JSON at `url`; None when the database has no such product (404). Network problems
    and bad answers raise."""
    opener = urllib.request.build_opener(_NoRedirect)
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    try:
        with opener.open(request, timeout=settings.BARCODE_LOOKUP_TIMEOUT) as response:
            return json.loads(response.read(MAX_BYTES))
    except urllib.error.HTTPError as error:
        if error.code == 404:
            return None
        raise


def _clean(text) -> str:
    return " ".join(text.split()) if isinstance(text, str) else ""


def _info(product: dict, source: str) -> Info | None:
    name = _clean(product.get("product_name")) or _clean(product.get("generic_name"))
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


def lookup(code: str) -> Info:
    """What the open databases know about this (valid) barcode."""
    if not settings.BARCODE_LOOKUP_ENABLED:
        return Info(found=False, unavailable=True)
    key = f"gtin:v2:{code}"
    cached = cache.get(key)
    if cached is not None:
        return Info(**cached)
    answered = False
    for source, template in SOURCES:
        url = template.format(code=code) + f"?fields={FIELDS}"
        try:
            data = _fetch(url)
        except (OSError, ValueError):  # no connection, a timeout, an answer that is not JSON
            continue
        answered = True
        if data and data.get("status") == 1 and isinstance(data.get("product"), dict):
            info = _info(data["product"], source)
            if info is not None:
                cache.set(key, info.__dict__, HIT_SECONDS)
                return info
    if not answered:
        return Info(found=False, unavailable=True)
    miss = Info(found=False)
    cache.set(key, miss.__dict__, MISS_SECONDS)
    return miss
