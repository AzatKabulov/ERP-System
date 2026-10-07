"""Product CSV: the export, and the one function that checks an import file.

Export is `;`-separated UTF-8 with a byte-order mark (what spreadsheet programs open correctly
for Russian and Turkmen text) and protected against formula injection. Import accepts `;` or
`,` (found from the header line), a decimal point or comma, with or without the byte-order
mark. `analyze` reads the WHOLE file and reports every row error; the preview shows them and
the apply step refuses to do anything while there is one. Import only ever creates new products.
"""

import csv
import hashlib
import io
import re
from dataclasses import dataclass, field
from decimal import Decimal

from django.db.models.functions import Lower

from apps.common.errors import ApiError

from .models import Barcode, Brand, Category, Product, Unit

MAX_ROWS = 2000
MAX_BYTES = 1024 * 1024  # 1 MB

# The export's columns, in order (`default_cost` only for those who may see costs).
EXPORT_COLUMNS = [
    "sku",
    "name",
    "unit",
    "category",
    "brand",
    "price",
    "currency",
    "default_cost",
    "warranty_months",
    "warranty_terms",
    "return_days",
    "barcodes",
]
REQUIRED_COLUMNS = ["sku", "name", "unit", "price"]
TEXT_COLUMNS = {"sku", "name", "unit", "category", "brand", "warranty_terms", "barcodes"}
BARCODE_SEPARATOR = "|"
MAX_BARCODES = 20  # per product, as in the product form

CENT = Decimal("0.01")
MAX_MONEY = Decimal(10) ** 12  # price and cost are 14 digits with 2 decimals
_FORMULA_STARTS = ("=", "+", "-", "@", "\t", "\r")
_DECIMAL = re.compile(r"[+-]?[0-9]+(?:[.,][0-9]+)?")
_INTEGER = re.compile(r"[+-]?[0-9]+")


# ---- export ---------------------------------------------------------------------------------


def protect(value: str) -> str:
    """A text cell that a spreadsheet could read as a formula gets a leading apostrophe."""
    return "'" + value if value.startswith(_FORMULA_STARTS) else value


def export_csv(products, *, include_cost: bool) -> bytes:
    columns = [c for c in EXPORT_COLUMNS if include_cost or c != "default_cost"]
    buffer = io.StringIO()
    buffer.write("﻿")
    writer = csv.writer(buffer, delimiter=";", lineterminator="\r\n")
    writer.writerow(columns)
    for product in products:
        cost = product.default_purchase_cost
        values = {
            "sku": product.sku,
            "name": product.name,
            "unit": product.unit.name,
            "category": product.category.name if product.category_id else "",
            "brand": product.brand.name if product.brand_id else "",
            "price": str(product.price_amount),
            "currency": product.price_currency,
            "default_cost": "" if cost is None else str(cost),
            "warranty_months": str(product.warranty_months),
            "warranty_terms": product.warranty_terms,
            "return_days": "" if product.return_days is None else str(product.return_days),
            "barcodes": BARCODE_SEPARATOR.join(b.code for b in product.barcodes.all()),
        }
        writer.writerow([protect(values[c]) if c in TEXT_COLUMNS else values[c] for c in columns])
    return buffer.getvalue().encode("utf-8")


# ---- import: reading the file ---------------------------------------------------------------


def too_large() -> ApiError:
    return ApiError(
        "import_too_large",
        "The file is too big: split it into smaller files",
        params={"max_rows": MAX_ROWS, "max_bytes": MAX_BYTES},
    )


def _invalid_file(reason: str) -> ApiError:
    return ApiError(
        "invalid_file",
        "The file cannot be read: save it as CSV in UTF-8",
        params={"reason": reason},
    )


def _read_table(data: bytes) -> tuple[list[str], list[tuple[int, list[str]]]]:
    """(header names, [(row number, cells)]). Row numbers count data rows from 1, header
    excluded, blank rows included, so they match the position in the file. Blank rows are
    left out of the result."""
    if len(data) > MAX_BYTES:
        raise too_large()
    try:
        text = data.decode("utf-8-sig")
    except UnicodeDecodeError as exc:
        raise _invalid_file("encoding") from exc
    if "\x00" in text:
        raise _invalid_file("encoding")
    first_line = next((line for line in text.splitlines() if line.strip()), "")
    delimiter = "," if first_line.count(",") > first_line.count(";") else ";"
    reader = csv.reader(io.StringIO(text), delimiter=delimiter)
    header: list[str] | None = None
    rows: list[tuple[int, list[str]]] = []
    position = 0
    try:
        for record in reader:
            if not any(cell.strip() for cell in record):
                if header is not None:
                    position += 1
                continue
            if header is None:
                header = [cell.strip().casefold() for cell in record]
                while header and not header[-1]:  # a spreadsheet's empty trailing columns
                    header.pop()
                continue
            position += 1
            rows.append((position, record))
            if len(rows) > MAX_ROWS:
                raise too_large()
    except csv.Error as exc:
        raise _invalid_file("csv") from exc
    if header is None:
        raise ApiError(
            "invalid_header",
            "The first row must list the column names",
            params={"missing": REQUIRED_COLUMNS, "unknown": [], "duplicate": []},
        )
    return header, rows


def _check_header(header: list[str]) -> None:
    known = set(EXPORT_COLUMNS)
    unknown = [name for name in header if name not in known]
    missing = [name for name in REQUIRED_COLUMNS if name not in header]
    duplicate = sorted({name for name in header if header.count(name) > 1 and name})
    if unknown or missing or duplicate:
        raise ApiError(
            "invalid_header",
            "The column names are wrong",
            params={"unknown": unknown, "missing": missing, "duplicate": duplicate},
        )


# ---- import: checking the rows --------------------------------------------------------------


@dataclass
class Analysis:
    rows: int  # data rows (blank ones are not counted)
    errors: list[dict]  # {"row", "field", "code"}, in file order
    products: list[dict] = field(default_factory=list)  # the valid rows, ready to create
    sha256: str = ""

    @property
    def valid(self) -> int:
        return self.rows - len({e["row"] for e in self.errors})


def _decimal(text: str, field_name: str, errors: list, *, required: bool) -> Decimal | None:
    """A non-negative amount with at most two decimals (a comma is accepted for the point)."""
    if not text:
        if required:
            errors.append((field_name, "required"))
        return None
    if not _DECIMAL.fullmatch(text):
        errors.append((field_name, "invalid_number"))
        return None
    value = Decimal(text.replace(",", "."))
    if value < 0:
        errors.append((field_name, "negative_number"))
    elif value >= MAX_MONEY:
        errors.append((field_name, "out_of_range"))
    elif value != value.quantize(CENT):
        errors.append((field_name, "too_many_decimals"))
    else:
        return value.quantize(CENT)
    return None


def _integer(text: str, field_name: str, errors: list, *, maximum: int) -> int | None:
    if not _INTEGER.fullmatch(text):
        errors.append((field_name, "invalid_number"))
        return None
    if len(text.lstrip("+-")) > 6:  # far beyond any limit; never feed it to int()
        errors.append((field_name, "out_of_range"))
        return None
    value = int(text)
    if value < 0:
        errors.append((field_name, "negative_number"))
    elif value > maximum:
        errors.append((field_name, "out_of_range"))
    else:
        return value
    return None


def _split_barcodes(text: str) -> list[str]:
    return [code.strip() for code in text.split(BARCODE_SEPARATOR) if code.strip()]


class _Context:
    """What the rows are checked against: the business's units, categories, brands, and the
    SKUs and barcodes that already exist or came earlier in the same file."""

    def __init__(self, business, rows: list[dict]):
        units = list(Unit.objects.filter(business=business, is_active=True))
        self.units_by_name = {u.name.casefold(): u for u in units}
        self.units_by_symbol: dict[str, list[Unit]] = {}
        for unit in units:
            self.units_by_symbol.setdefault(unit.symbol.casefold(), []).append(unit)
        self.categories = {c.name.casefold(): c for c in Category.objects.filter(business=business)}
        self.brands = {b.name.casefold(): b for b in Brand.objects.filter(business=business)}
        skus = {r["sku"].strip().lower() for r in rows if r.get("sku", "").strip()}
        self.existing_skus = set(
            Product.objects.filter(business=business)
            .annotate(key=Lower("sku"))
            .filter(key__in=skus)
            .values_list("key", flat=True)
        )
        codes = {c for r in rows for c in _split_barcodes(r.get("barcodes", ""))}
        self.existing_barcodes = set(
            Barcode.objects.filter(business=business, code__in=codes).values_list("code", flat=True)
        )
        self.seen_skus: set[str] = set()
        self.seen_barcodes: set[str] = set()

    def unit(self, text: str) -> Unit | None:
        key = text.casefold()
        if key in self.units_by_name:
            return self.units_by_name[key]
        matches = self.units_by_symbol.get(key, [])
        return matches[0] if len(matches) == 1 else None  # two units with that symbol: unclear


def _check_row(ctx: _Context, values: dict) -> tuple[list[tuple[str, str]], dict]:
    errors: list[tuple[str, str]] = []

    def cell(name: str) -> str:
        return values.get(name, "").strip()

    sku = cell("sku")
    if not sku:
        errors.append(("sku", "required"))
    elif len(sku) > 64:
        errors.append(("sku", "too_long"))
    else:
        key = sku.lower()
        if key in ctx.existing_skus:
            errors.append(("sku", "sku_exists"))
        elif key in ctx.seen_skus:
            errors.append(("sku", "sku_duplicate_in_file"))
        ctx.seen_skus.add(key)

    name = cell("name")
    if not name:
        errors.append(("name", "required"))
    elif len(name) > 255:
        errors.append(("name", "too_long"))

    unit = None
    if not cell("unit"):
        errors.append(("unit", "required"))
    else:
        unit = ctx.unit(cell("unit"))
        if unit is None:
            errors.append(("unit", "unknown_unit"))

    names = {}
    for column, known in (("category", ctx.categories), ("brand", ctx.brands)):
        text = cell(column)
        names[column] = text or None
        if len(text) > 120:
            errors.append((column, "too_long"))
        elif text and text.casefold() in known and not known[text.casefold()].is_active:
            errors.append((column, "inactive_reference"))

    price = _decimal(cell("price"), "price", errors, required=True)
    currency = cell("currency").upper() or "TMT"
    if currency not in Product.PriceCurrency.values:
        errors.append(("currency", "invalid_currency"))
    cost = _decimal(cell("default_cost"), "default_cost", errors, required=False)
    months = 0
    if cell("warranty_months"):
        months = _integer(cell("warranty_months"), "warranty_months", errors, maximum=120)
    terms = cell("warranty_terms")
    if len(terms) > 2000:
        errors.append(("warranty_terms", "too_long"))
    days = None
    if cell("return_days"):
        days = _integer(cell("return_days"), "return_days", errors, maximum=3650)

    codes = _split_barcodes(cell("barcodes"))
    if len(codes) > MAX_BARCODES:
        errors.append(("barcodes", "too_many"))
    for index, code in enumerate(codes):
        if len(code) > 64:
            errors.append(("barcodes", "too_long"))
        elif code in ctx.existing_barcodes:
            errors.append(("barcodes", "barcode_exists"))
        elif code in ctx.seen_barcodes or code in codes[:index]:
            errors.append(("barcodes", "barcode_duplicate_in_file"))
    ctx.seen_barcodes.update(codes)

    product = {
        "sku": sku,
        "name": name,
        "unit": unit,
        "category": names["category"],
        "brand": names["brand"],
        "price_amount": price,
        "price_currency": currency,
        "default_purchase_cost": cost,
        "warranty_months": months,
        "warranty_terms": terms,
        "return_days": days,
        "barcodes": codes,
    }
    return errors, product


def analyze(business, data: bytes) -> Analysis:
    """Check a whole import file against the business's catalogue. Reads the database, changes
    nothing. Raises 400 for a file that cannot be used at all (too big, unreadable, wrong
    columns); every problem with a single row is returned in `errors`."""
    header, table = _read_table(data)
    _check_header(header)
    rows = [dict(zip(header, record, strict=False)) for _, record in table]
    ctx = _Context(business, rows)
    analysis = Analysis(rows=len(table), errors=[], sha256=hashlib.sha256(data).hexdigest())
    for (number, record), values in zip(table, rows, strict=True):
        problems, product = _check_row(ctx, values)
        if any(cell.strip() for cell in record[len(header) :]):
            problems.append(("", "too_many_columns"))
        for field_name, code in dict.fromkeys(problems):  # one entry per field and code
            analysis.errors.append({"row": number, "field": field_name, "code": code})
        if not problems:
            analysis.products.append({"row": number, **product})
    return analysis
