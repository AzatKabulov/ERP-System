"""Read-only automotive references. Never infer fitment, substitute parts or prices."""

import json
import re
import urllib.request
from functools import lru_cache
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urlencode

from django.conf import settings
from django.core.cache import cache

from . import lookup


def identify(raw: str, brand: str = "") -> tuple[str, str]:
    value = raw.strip().upper()
    brand = brand.strip().upper()
    if len(value) > 64 or len(brand) > 64 or not re.fullmatch(r"[A-Z0-9 .-]+", value):
        return "", ""
    for label in (
        "MITSUBISHI FUSO",
        "GOODRUBBER",
        "MITSUBISHI",
        "SUPREME",
        "MAWROOIL",
        "TAIHO",
        "ISUZU",
        "FUSO",
        "KYB",
        "OSK",
    ):
        if value.startswith(label + " "):
            brand, value = label, value[len(label) + 1 :].strip()
            break
    # Observed FUSO Code 39 layout: article followed by a separate four-digit field.
    compound = re.fullmatch(r"((?:ME|MH|MB|MC)[0-9]{6}) +[0-9]{4}", value)
    if compound:
        value = compound[1]
    value = value.replace(" ", "")
    if not re.fullmatch(r"[A-Z0-9][A-Z0-9.-]{2,39}", value):
        return "", ""
    if value.isdigit() and not (brand == "KYB" and len(value) == 6):
        return "", ""
    if not any(c.isdigit() for c in value):
        return "", ""
    return value, brand


def key(value: str) -> str:
    return re.sub(r"[ .-]", "", value.upper())


class _Table(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.rows = []
        self.row = None
        self.cell = None

    def handle_starttag(self, tag, attrs):
        if tag == "tr":
            self.row = []
        elif tag in ("td", "th") and self.row is not None:
            self.cell = []

    def handle_data(self, data):
        if self.cell is not None:
            self.cell.append(data)

    def handle_endtag(self, tag):
        if tag in ("td", "th") and self.cell is not None:
            self.row.append(" ".join(" ".join(self.cell).split()))
            self.cell = None
        elif tag == "tr" and self.row is not None:
            self.rows.append(self.row)
            self.row = None


@lru_cache(maxsize=2)
def _catalog(path: str, modified: int, size: int):
    if size > 10_000_000:
        raise ValueError("Reference catalog too large")
    rows = json.loads(Path(path).read_text(encoding="utf-8"))
    if not isinstance(rows, list):
        raise ValueError("Invalid reference catalog")
    index = {}
    for row in rows:
        if not isinstance(row, dict) or not all(
            isinstance(row.get(f), str) for f in ("article", "brand", "name")
        ):
            raise ValueError("Invalid reference row")
        if not isinstance(row.get("brand_aliases", []), list):
            raise ValueError("Invalid brand aliases")
        codes = row.get("code_aliases", [])
        if not isinstance(codes, list) or any(not isinstance(c, str) for c in codes):
            raise ValueError("Invalid code aliases")
        for code in {key(row["article"]), *[key(c) for c in codes]}:
            index.setdefault(code, []).append(row)
    return index


def _reference(article: str, brand: str):
    # Only public reference data; never harvest another shop's products or prices.
    file = Path(settings.PART_REFERENCE_FILE)
    stat = file.stat()
    rows = _catalog(str(file), stat.st_mtime_ns, stat.st_size).get(key(article), [])
    matches = []
    for row in rows:
        aliases = row.get("brand_aliases", [])
        brands = {key(row["brand"]), *[key(b) for b in aliases if isinstance(b, str)]}
        if not brand or key(brand) in brands:
            matches.append(row)
    if len(matches) != 1:
        return None
    row = matches[0]
    return {
        "found": True,
        "name": row["name"][:255],
        "brand": row["brand"][:100],
        "article": row["article"],
        "category": "",
        "quantity": "",
        "source": "ERP parts reference",
        "unavailable": False,
    }


def _osk(article: str, brand: str):
    if brand and brand != "OSK":
        return None
    if not cache.add("parts:osk:admission", True, 1):
        raise OSError("Catalog admission limit")
    request = urllib.request.Request(
        "https://www.oskfilter.com.my/catalog.php?" + urlencode({"keyword": article}),
        headers={"User-Agent": lookup.USER_AGENT},
    )
    with urllib.request.build_opener(lookup._NoRedirect).open(request, timeout=4) as response:
        raw = response.read(lookup.MAX_BYTES + 1)
    if len(raw) > lookup.MAX_BYTES:
        raise ValueError("Catalog response too large")
    page = raw.decode("utf-8")
    parser = _Table()
    parser.feed(page)
    if "OSK | Catalog" not in page:
        raise ValueError("Unexpected catalog response")
    for row in parser.rows:
        # Only the manufacturer's exact product row, never a cross-reference replacement.
        if (
            len(row) == 4
            and key(row[0]) == key(article)
            and row[1]
            in ("AIR FILTER", "OIL FILTER", "FUEL FILTER", "CABIN FILTER", "HYDRAULIC FILTER")
        ):
            return {
                "found": True,
                "name": row[1].title() + " " + row[0],
                "brand": "OSK",
                "article": row[0],
                "category": "",
                "quantity": "",
                "source": "OSK",
                "unavailable": False,
            }
    if "No product is found." not in page and "OSK No" not in page:
        raise ValueError("Unrecognized catalog layout")
    return None


def find(raw: str, brand: str = "") -> dict:
    article, brand = identify(raw, brand)
    empty = {"found": False, "article": article, "unavailable": False}
    if not article:
        return empty
    if not settings.BARCODE_LOOKUP_ENABLED:
        return {**empty, "unavailable": True}
    failed = False
    try:
        result = _reference(article, brand)
        if result:
            return result
    except (OSError, ValueError, TypeError):
        failed = True
    if not settings.PART_LOOKUP_OSK_ENABLED:
        return {**empty, "unavailable": failed}
    cache_key = "parts:osk:v1:" + key(article) + ":" + key(brand)
    cached = cache.get(cache_key)
    if cached is not None:
        return cached
    try:
        result = _osk(article, brand)
        if result:
            cache.set(cache_key, result, lookup.HIT_SECONDS)
            return result
    except (OSError, ValueError, TypeError):
        failed = True
    result = {**empty, "unavailable": failed}
    if not failed:
        cache.set(cache_key, result, lookup.MISS_SECONDS)
    return result
