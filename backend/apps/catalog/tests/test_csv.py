import csv
import hashlib
import io
import threading
from concurrent.futures import ThreadPoolExecutor
from decimal import Decimal
from unittest import mock

from django.core.files.uploadedfile import SimpleUploadedFile
from django.db import connections
from rest_framework.test import APIClient

from apps.audit.models import AuditEvent
from apps.businesses.models import Role
from apps.businesses.permissions import has_permission
from apps.catalog import csvio
from apps.catalog import services as catalog_services
from apps.catalog.models import Barcode, Brand, Category, Product, Unit
from apps.common.errors import ApiError
from apps.common.testing import APITestCase, APITransactionTestCase, client_for
from apps.inventory.models import CostLayer, StockBalance, StockMovement
from apps.inventory.tests.support import World, ledger_differences

D = Decimal
HEADER = csvio.EXPORT_COLUMNS
TURKMEN = "ÄÇŇÖŞÜÝŽ äçňöşüýž"
RUSSIAN = "Тормозные колодки Ёлка ёлка"


def row(sku="X-1", name="Item", unit="pc", **cells):
    """One CSV row (cells in column order). Unnamed cells are empty."""
    values = {"sku": sku, "name": name, "unit": unit, "price": "10.00", **cells}
    return [str(values.get(column, "")) for column in HEADER]


def make_csv(rows, *, header=None, delimiter=";", bom=False, eol="\r\n") -> bytes:
    out = io.StringIO()
    writer = csv.writer(out, delimiter=delimiter, lineterminator=eol)
    writer.writerow(header or HEADER)
    writer.writerows(rows)
    return (("﻿" if bom else "") + out.getvalue()).encode("utf-8")


def send(client, url, data: bytes, name="products.csv"):
    file = SimpleUploadedFile(name, data, content_type="text/csv")
    return client.post(url, {"file": file}, format="multipart")


def parse_export(response) -> list[dict]:
    text = response.content.decode("utf-8-sig")
    return list(csv.DictReader(io.StringIO(text), delimiter=";"))


class CsvCase(APITestCase):
    def setUp(self):
        super().setUp()
        self.w = World()
        self.owner = self.w.api[Role.OWNER]
        self.manager = self.w.api[Role.MANAGER]
        self.export_url = f"{self.w.base}/catalog/export/"
        self.preview_url = f"{self.w.base}/catalog/import/preview/"
        self.apply_url = f"{self.w.base}/catalog/import/apply/"

    def tearDown(self):
        self.assertEqual(ledger_differences(), [])  # an import never touches stock
        super().tearDown()

    def counts(self):
        return {
            "products": Product.objects.count(),
            "categories": Category.objects.count(),
            "brands": Brand.objects.count(),
            "barcodes": Barcode.objects.count(),
            "audit": AuditEvent.objects.count(),
        }

    def stock_counts(self):
        return (
            StockMovement.objects.count(),
            StockBalance.objects.count(),
            CostLayer.objects.count(),
        )

    def preview(self, data, client=None, **kwargs):
        return send(client or self.owner, self.preview_url, data, **kwargs)

    def apply(self, data, client=None, **kwargs):
        return send(client or self.owner, self.apply_url, data, **kwargs)

    def error(self, response):
        return response.json()["error"]

    def product(self, sku):
        return Product.objects.get(business=self.w.a, sku=sku)


class ExportTests(CsvCase):
    def make(self, **fields):
        data = {
            "sku": "P-1",
            "name": "Item",
            "unit": self.w.unit,
            "price_amount": D("10.00"),
            **fields,
        }
        return catalog_services.create_product(self.w.a, self.w.owner, data)

    def test_the_file_is_utf8_with_a_bom_and_semicolons(self):
        response = self.owner.get(self.export_url)
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response["Content-Type"], "text/csv; charset=utf-8")
        self.assertEqual(response["Content-Disposition"], 'attachment; filename="products.csv"')
        self.assertEqual(response["Cache-Control"], "private, no-store")
        self.assertTrue(response.content.startswith(b"\xef\xbb\xbf"))
        first_line = response.content.decode("utf-8-sig").split("\r\n")[0]
        self.assertEqual(
            first_line,
            "sku;name;unit;category;brand;price;currency;default_cost;warranty_months;"
            "warranty_terms;return_days;barcodes",
        )

    def test_the_cost_column_is_there_for_owner_and_manager(self):
        for client in (self.owner, self.manager):
            header = parse_export(client.get(self.export_url))[0].keys()
            self.assertEqual(list(header), HEADER)

    def test_the_cost_column_is_left_out_without_the_cost_permission(self):
        self.make(default_purchase_cost=D("54.00"))

        def without_cost(role, code):
            return code != "catalog.cost.view" and has_permission(role, code)

        with mock.patch("apps.catalog.views.has_permission", side_effect=without_cost):
            response = self.owner.get(self.export_url)
        rows = parse_export(response)
        self.assertEqual(list(rows[0].keys()), [c for c in HEADER if c != "default_cost"])
        self.assertNotIn("54.00", response.content.decode("utf-8-sig"))

    def test_values_use_a_decimal_point_and_barcodes_are_joined(self):
        category = Category.objects.create(business=self.w.a, name="Filters")
        brand = Brand.objects.create(business=self.w.a, name="Bosch")
        self.make(
            sku="F-1",
            name="Oil filter",
            category=category,
            brand=brand,
            price_amount=D("85.50"),
            price_currency="USD",
            default_purchase_cost=D("54.1"),
            warranty_months=12,
            warranty_terms="Return with the receipt",
            return_days=14,
            barcodes=["400001", "400002"],
        )
        self.make(sku="F-2", name="Plain", unit=self.w.litre, price_amount=D("0"))
        rows = {r["sku"]: r for r in parse_export(self.owner.get(self.export_url))}
        self.assertEqual(
            rows["F-1"],
            {
                "sku": "F-1",
                "name": "Oil filter",
                "unit": "Piece",
                "category": "Filters",
                "brand": "Bosch",
                "price": "85.50",
                "currency": "USD",
                "default_cost": "54.10",
                "warranty_months": "12",
                "warranty_terms": "Return with the receipt",
                "return_days": "14",
                "barcodes": "400001|400002",
            },
        )
        self.assertEqual(
            rows["F-2"],
            {
                "sku": "F-2",
                "name": "Plain",
                "unit": "Litre",
                "category": "",
                "brand": "",
                "price": "0.00",
                "currency": "TMT",
                "default_cost": "",
                "warranty_months": "0",
                "warranty_terms": "",
                "return_days": "",
                "barcodes": "",
            },
        )

    def test_only_active_products_are_exported(self):
        self.make(sku="OLD-1", name="Archived", is_active=False)
        self.make(sku="NEW-1", name="Live")
        skus = {r["sku"] for r in parse_export(self.owner.get(self.export_url))}
        self.assertIn("NEW-1", skus)
        self.assertNotIn("OLD-1", skus)
        self.assertEqual(skus, {"BP-1", "OIL-1", "NEW-1"})

    def test_an_empty_catalog_is_just_the_header(self):
        Product.objects.filter(business=self.w.b).delete()
        response = self.w.b_api.get(f"/api/v1/businesses/{self.w.b.pk}/catalog/export/")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.content.decode("utf-8-sig"), ";".join(HEADER) + "\r\n")

    def test_russian_and_turkmen_letters_survive(self):
        category = Category.objects.create(business=self.w.a, name=f"Süzgüçler {RUSSIAN}")
        self.make(
            sku=f"{TURKMEN}-1",
            name=f"{RUSSIAN} {TURKMEN}",
            category=category,
            warranty_terms=f"Kepillik: {TURKMEN}; гарантия\nвторая строка",
            barcodes=["ÄÇŇ-1"],
        )
        response = self.owner.get(self.export_url, HTTP_ACCEPT="text/html")
        self.assertEqual(response.status_code, 200)
        row_ = [r for r in parse_export(response) if r["sku"].startswith("ÄÇŇ")][0]
        self.assertEqual(row_["sku"], f"{TURKMEN}-1")
        self.assertEqual(row_["name"], f"{RUSSIAN} {TURKMEN}")
        self.assertEqual(row_["category"], f"Süzgüçler {RUSSIAN}")
        self.assertEqual(row_["warranty_terms"], f"Kepillik: {TURKMEN}; гарантия\nвторая строка")
        self.assertEqual(row_["barcodes"], "ÄÇŇ-1")

    def test_text_that_could_be_a_formula_is_neutralised(self):
        evil = "=cmd|' /C calc'!A0"
        self.make(sku="E-1", name=evil)
        self.make(sku="E-2", name="+1+1", warranty_terms="@SUM(A1:A9)")
        self.make(sku="E-3", name="-2+3", barcodes=["=1+1"])
        self.make(sku="E-4", name="Tab", warranty_terms="\tTAB")
        self.make(sku="E-5", name="Cr", warranty_terms="\rCR")
        self.make(sku="=E-6", name="Safe")
        self.make(sku="E-7", name="Mid = dash - plus + at @ is fine")
        rows = {r["sku"].lstrip("'"): r for r in parse_export(self.owner.get(self.export_url))}
        self.assertEqual(rows["E-1"]["name"], "'" + evil)
        self.assertEqual(rows["E-2"]["name"], "'+1+1")
        self.assertEqual(rows["E-2"]["warranty_terms"], "'@SUM(A1:A9)")
        self.assertEqual(rows["E-3"]["name"], "'-2+3")
        self.assertEqual(rows["E-3"]["barcodes"], "'=1+1")
        self.assertEqual(rows["E-4"]["warranty_terms"], "'\tTAB")
        self.assertEqual(rows["E-5"]["warranty_terms"], "'\rCR")
        self.assertEqual(rows["=E-6"]["sku"], "'=E-6")
        self.assertEqual(rows["E-7"]["name"], "Mid = dash - plus + at @ is fine")
        self.assertEqual(rows["E-7"]["sku"], "E-7")
        # no text cell of the file starts with a formula character
        for line in parse_export(self.owner.get(self.export_url)):
            for column in ("sku", "name", "category", "brand", "warranty_terms", "barcodes"):
                self.assertFalse(line[column].startswith(("=", "+", "-", "@", "\t", "\r")), line)
        raw = self.owner.get(self.export_url).content.decode("utf-8-sig")
        self.assertIn("'=cmd|' /C calc'!A0", raw)

    def test_the_export_is_audited(self):
        self.owner.get(self.export_url)
        event = AuditEvent.objects.get(action="catalog.exported")
        self.assertEqual(event.actor, self.w.owner)
        self.assertEqual(event.metadata["rows"], 2)

    def test_exported_products_can_be_imported_into_another_business(self):
        category = Category.objects.create(business=self.w.a, name=f"Süzgüçler {RUSSIAN}")
        brand = Brand.objects.create(business=self.w.a, name="Bosch Ä")
        self.make(
            sku="RT-1",
            name=f"{RUSSIAN} {TURKMEN}",
            category=category,
            brand=brand,
            price_amount=D("12.50"),
            price_currency="USD",
            default_purchase_cost=D("7.25"),
            warranty_months=6,
            warranty_terms=f"Kepillik {TURKMEN}",
            return_days=10,
            barcodes=["111", "222"],
        )
        exported = self.owner.get(self.export_url)
        b_base = f"/api/v1/businesses/{self.w.b.pk}"
        Product.objects.filter(business=self.w.b).delete()
        Unit.objects.create(business=self.w.b, name="Litre", symbol="l", decimal_places=2)
        done = send(self.w.b_api, f"{b_base}/catalog/import/apply/", exported.content)
        self.assertEqual(done.status_code, 201, done.content)
        again = self.w.b_api.get(f"{b_base}/catalog/export/")
        before = sorted(parse_export(exported), key=lambda r: r["sku"])
        after = sorted(parse_export(again), key=lambda r: r["sku"])
        self.assertEqual(after, before)

    def test_roles_and_isolation(self):
        for role in (Role.SALES, Role.WAREHOUSE):
            self.assertEqual(self.w.api[role].get(self.export_url).status_code, 403)
        self.assertEqual(APIClient().get(self.export_url).status_code, 401)
        self.assertEqual(self.w.b_api.get(self.export_url).status_code, 404)
        # business B's export never contains business A's products
        rows = parse_export(self.w.b_api.get(f"/api/v1/businesses/{self.w.b.pk}/catalog/export/"))
        self.assertEqual({r["sku"] for r in rows}, {"B-1"})


class PreviewAndApplyTests(CsvCase):
    def test_a_valid_file_creates_exactly_these_products(self):
        Category.objects.create(business=self.w.a, name="Existing cat")
        data = make_csv(
            [
                row(
                    "OIL-10",
                    "Engine oil 5W-30",
                    "Litre",
                    category="Oils",
                    brand="Castrol",
                    price="45.50",
                    currency="usd",
                    default_cost="30",
                    warranty_months="12",
                    warranty_terms="With receipt",
                    return_days="14",
                    barcodes="5000001|5000002",
                ),
                row("PAD-9", "Pad", "pc", category="existing CAT", price="0"),
                row("PLAIN", "Plain", "piece"),
            ]
        )
        response = self.apply(data)
        self.assertEqual(response.status_code, 201, response.content)
        self.assertEqual(response.json(), {"created": 3})
        oil = self.product("OIL-10")
        self.assertEqual(
            (
                oil.name,
                oil.unit,
                oil.category.name,
                oil.brand.name,
                oil.price_amount,
                oil.price_currency,
                oil.default_purchase_cost,
                oil.warranty_months,
                oil.warranty_terms,
                oil.return_days,
                oil.is_active,
            ),
            (
                "Engine oil 5W-30",
                self.w.litre,
                "Oils",
                "Castrol",
                D("45.50"),
                "USD",
                D("30.00"),
                12,
                "With receipt",
                14,
                True,
            ),
        )
        self.assertEqual(list(oil.barcodes.values_list("code", flat=True)), ["5000001", "5000002"])
        pad = self.product("PAD-9")
        self.assertEqual(
            pad.category.name, "Existing cat"
        )  # the existing one, matched ignoring case
        self.assertEqual((pad.price_amount, pad.price_currency), (D("0.00"), "TMT"))
        self.assertEqual(Category.objects.filter(business=self.w.a).count(), 2)  # + "Oils"
        plain = self.product("PLAIN")
        self.assertEqual(
            (plain.unit, plain.category, plain.brand, plain.default_purchase_cost),
            (self.w.unit, None, None, None),
        )
        self.assertEqual(
            (plain.warranty_months, plain.warranty_terms, plain.return_days), (0, "", None)
        )
        self.assertEqual(plain.barcodes.count(), 0)
        # search keys are rebuilt: name, sku, brand, category, barcodes
        self.assertEqual(oil.search_key, "engine oil 5w-30 oil-10 5000001 5000002 castrol oils")
        found = self.owner.get(f"{self.w.base}/products/?q=5000002").json()["results"]
        self.assertEqual([p["sku"] for p in found], ["OIL-10"])
        found = self.owner.get(f"{self.w.base}/products/?q=castrol").json()["results"]
        self.assertEqual([p["sku"] for p in found], ["OIL-10"])
        looked_up = self.owner.get(f"{self.w.base}/barcodes/lookup/?code=5000001")
        self.assertEqual(looked_up.json()["sku"], "OIL-10")

    def test_one_audit_event_for_the_import_with_the_rows_and_the_files_hash(self):
        data = make_csv([row("A-1", category="New cat", brand="New brand"), row("A-2")])
        self.assertEqual(self.apply(data).status_code, 201)
        event = AuditEvent.objects.get(action="catalog.imported")
        self.assertEqual(event.actor, self.w.owner)
        self.assertEqual(event.business, self.w.a)
        self.assertEqual(
            event.metadata,
            {
                "rows": 2,
                "created": 2,
                "sha256": hashlib.sha256(data).hexdigest(),
                "categories_created": 1,
                "brands_created": 1,
            },
        )
        self.assertEqual(AuditEvent.objects.filter(action="product.created").count(), 2)

    def test_the_preview_changes_nothing(self):
        data = make_csv([row("A-1", category="New cat", brand="New brand"), row("A-2")])
        before = self.counts()
        response = self.preview(data)
        self.assertEqual(response.status_code, 200)
        self.assertEqual(
            response.json(),
            {"rows": 2, "valid": 2, "errors": [], "error_count": 0, "truncated": False},
        )
        self.assertEqual(self.counts(), before)

    def test_importing_never_creates_stock(self):
        before = self.stock_counts()
        self.assertEqual(self.apply(make_csv([row("S-1"), row("S-2")])).status_code, 201)
        self.assertEqual(self.stock_counts(), before)
        self.assertEqual(StockBalance.objects.filter(product__sku__in=["S-1", "S-2"]).count(), 0)

    def test_an_error_on_the_last_row_changes_nothing(self):
        rows = [
            row(f"OK-{n}", f"Item {n}", category=f"Cat {n % 5}", brand=f"Brand {n % 3}")
            for n in range(60)
        ]
        rows.append(row("BAD", price="ten"))
        data = make_csv(rows)
        before = self.counts()
        stock = self.stock_counts()
        preview = self.preview(data)
        self.assertEqual(preview.status_code, 200)
        self.assertEqual(
            preview.json(),
            {
                "rows": 61,
                "valid": 60,
                "errors": [{"row": 61, "field": "price", "code": "invalid_number"}],
                "error_count": 1,
                "truncated": False,
            },
        )
        response = self.apply(data)
        self.assertEqual(response.status_code, 409)
        error = self.error(response)
        self.assertEqual(error["code"], "import_invalid")
        self.assertEqual(
            error["params"],
            {
                "errors": [{"row": 61, "field": "price", "code": "invalid_number"}],
                "error_count": 1,
            },
        )
        self.assertEqual(self.counts(), before)  # no product, category, brand, barcode or event
        self.assertEqual(self.stock_counts(), stock)

    def test_a_failure_in_the_middle_of_the_apply_rolls_everything_back(self):
        rows = [
            row(f"M-{n}", f"Item {n}", category=f"Cat {n}", brand=f"Brand {n}", barcodes=f"BC{n}")
            for n in range(10)
        ]
        data = make_csv(rows)
        before = self.counts()
        real = catalog_services.create_product
        calls = {"n": 0}

        def flaky(business, actor, data):
            calls["n"] += 1
            if calls["n"] == 6:
                raise RuntimeError("boom")
            return real(business, actor, data)

        client = APIClient(raise_request_exception=False)
        client.force_authenticate(self.w.owner)
        with mock.patch("apps.catalog.services.create_product", side_effect=flaky):
            response = send(client, self.apply_url, data)
        self.assertEqual(response.status_code, 500)
        self.assertEqual(calls["n"], 6)
        self.assertEqual(self.counts(), before)  # even the categories and brands of rows 1-5
        self.assertFalse(AuditEvent.objects.filter(action="catalog.imported").exists())
        # nothing is stuck: the same file imports fine afterwards
        self.assertEqual(self.apply(data).json(), {"created": 10})

    def test_a_clash_found_while_applying_is_reported_by_row_and_rolls_back(self):
        data = make_csv([row(f"C-{n}", category=f"Cat {n}") for n in range(8)])
        before = self.counts()
        real = catalog_services.create_product
        calls = {"n": 0}

        def clash(business, actor, fields):
            calls["n"] += 1
            if calls["n"] == 4:  # someone created this SKU a moment ago
                raise ApiError(
                    "validation_error",
                    "SKU already used",
                    fields={"sku": [{"code": "sku_taken", "message": "taken"}]},
                )
            return real(business, actor, fields)

        with mock.patch("apps.catalog.services.create_product", side_effect=clash):
            response = self.apply(data)
        self.assertEqual(response.status_code, 409)
        self.assertEqual(
            self.error(response)["params"],
            {"errors": [{"row": 4, "field": "sku", "code": "sku_exists"}], "error_count": 1},
        )
        self.assertEqual(self.counts(), before)

    def test_every_problem_has_its_code_and_row_number(self):
        Brand.objects.create(business=self.w.a, name="Old brand", is_active=False)
        catalog_services.create_product(
            self.w.a,
            self.w.owner,
            {
                "sku": "HAS-BC",
                "name": "x",
                "unit": self.w.unit,
                "price_amount": D("1"),
                "barcodes": ["EXIST-1"],
            },
        )
        cases = [  # (row cells, expected [(field, code)])
            (row("OK-1", barcodes="B-1|B-2"), []),
            (row("", "No sku"), [("sku", "required")]),
            (row("S" * 65), [("sku", "too_long")]),
            (row("bp-1", "Same as BP-1 in another case"), [("sku", "sku_exists")]),
            (row("DUP-1"), []),
            (row("dup-1"), [("sku", "sku_duplicate_in_file")]),
            (row("N-1", ""), [("name", "required")]),
            (row("U-1", unit="nonsense"), [("unit", "unknown_unit")]),
            (row("U-2", unit=""), [("unit", "required")]),
            (row("P-1", price="abc"), [("price", "invalid_number")]),
            (row("P-2", price="-5"), [("price", "negative_number")]),
            (row("P-3", price="1.234"), [("price", "too_many_decimals")]),
            (row("P-4", price=""), [("price", "required")]),
            (row("P-5", price="1e3"), [("price", "invalid_number")]),
            (row("P-6", price="99999999999999"), [("price", "out_of_range")]),
            (row("P-7", price="1 000"), [("price", "invalid_number")]),
            (row("C-1", currency="EUR"), [("currency", "invalid_currency")]),
            (row("D-1", default_cost="-1"), [("default_cost", "negative_number")]),
            (row("D-2", default_cost="1.005"), [("default_cost", "too_many_decimals")]),
            (row("W-1", warranty_months="121"), [("warranty_months", "out_of_range")]),
            (row("W-2", warranty_months="-1"), [("warranty_months", "negative_number")]),
            (row("W-3", warranty_months="1.5"), [("warranty_months", "invalid_number")]),
            (row("W-4", warranty_months="120"), []),
            (row("T-1", warranty_terms="t" * 2001), [("warranty_terms", "too_long")]),
            (row("R-1", return_days="3651"), [("return_days", "out_of_range")]),
            (row("R-2", return_days="x"), [("return_days", "invalid_number")]),
            (row("R-3", return_days="0"), []),
            (row("R-4", return_days="3650"), []),
            (row("L-1", "n" * 256), [("name", "too_long")]),
            (row("L-2", category="c" * 121), [("category", "too_long")]),
            (row("L-3", brand="Old brand"), [("brand", "inactive_reference")]),
            (row("B-3", barcodes="EXIST-1"), [("barcodes", "barcode_exists")]),
            (row("B-4", barcodes="B-2"), [("barcodes", "barcode_duplicate_in_file")]),
            (row("B-5", barcodes="Z-1|Z-1"), [("barcodes", "barcode_duplicate_in_file")]),
            (
                row("B-6", barcodes="|".join(f"Q-{n}" for n in range(21))),
                [("barcodes", "too_many")],
            ),
            (row("B-7", barcodes="b" * 65), [("barcodes", "too_long")]),
            (
                row("", "", "nonsense", price="abc"),
                [
                    ("sku", "required"),
                    ("name", "required"),
                    ("unit", "unknown_unit"),
                    ("price", "invalid_number"),
                ],
            ),
            (row("X-1") + ["stray"], [("", "too_many_columns")]),
            (row("X-2") + ["", ""], []),  # empty trailing cells are harmless
        ]
        data = make_csv([cells for cells, _ in cases])
        expected = [
            {"row": number, "field": field, "code": code}
            for number, (_, problems) in enumerate(cases, start=1)
            for field, code in problems
        ]
        valid_rows = sum(1 for _, problems in cases if not problems)
        before = self.counts()
        response = self.preview(data)
        self.assertEqual(response.status_code, 200)
        body = response.json()
        self.assertEqual(body["errors"], expected)
        self.assertEqual(body["error_count"], len(expected))
        self.assertEqual((body["rows"], body["valid"]), (len(cases), valid_rows))
        self.assertFalse(body["truncated"])
        applied = self.apply(data)
        self.assertEqual(applied.status_code, 409)
        self.assertEqual(self.error(applied)["params"]["errors"], expected[:50])
        self.assertEqual(self.error(applied)["params"]["error_count"], len(expected))
        self.assertEqual(self.counts(), before)

    def test_existing_products_are_never_updated(self):
        existing = self.product("BP-1")
        data = make_csv([row("bp-1", "New name", price="1.00"), row("NEW-1")])
        response = self.apply(data)
        self.assertEqual(response.status_code, 409)
        self.assertEqual(
            self.error(response)["params"]["errors"],
            [{"row": 1, "field": "sku", "code": "sku_exists"}],
        )
        existing.refresh_from_db()
        self.assertEqual((existing.name, existing.price_amount), ("Brake pad", D("100.00")))
        self.assertFalse(Product.objects.filter(sku="NEW-1").exists())

    def test_an_archived_product_still_owns_its_sku(self):
        Product.objects.filter(sku="BP-1").update(is_active=False)
        response = self.preview(make_csv([row("BP-1")]))
        self.assertEqual(
            response.json()["errors"], [{"row": 1, "field": "sku", "code": "sku_exists"}]
        )

    def test_the_same_file_twice_never_makes_duplicates(self):
        data = make_csv([row("T-1"), row("T-2")])
        self.assertEqual(self.apply(data).status_code, 201)
        again = self.apply(data)
        self.assertEqual(again.status_code, 409)
        self.assertEqual(self.error(again)["params"]["error_count"], 2)
        self.assertEqual(Product.objects.filter(sku__in=["T-1", "T-2"]).count(), 2)

    def test_units_match_by_symbol_or_name_ignoring_case(self):
        Unit.objects.create(business=self.w.a, name="Штука", symbol="шт", decimal_places=0)
        Unit.objects.create(business=self.w.a, name="Old", symbol="old", is_active=False)
        Unit.objects.create(business=self.w.a, name="Twin A", symbol="tw", decimal_places=0)
        Unit.objects.create(business=self.w.a, name="Twin B", symbol="tw", decimal_places=1)
        data = make_csv(
            [
                row("U-1", unit="PC"),
                row("U-2", unit="LITRE"),
                row("U-3", unit="ШТ"),
                row("U-4", unit="штука"),
                row("U-5", unit="old"),  # an inactive unit is not offered
                row("U-6", unit="tw"),  # two units share this symbol: ambiguous
                row("U-7", unit="Twin B"),  # their names are unique, so the name works
            ]
        )
        body = self.preview(data).json()
        self.assertEqual(
            body["errors"],
            [
                {"row": 5, "field": "unit", "code": "unknown_unit"},
                {"row": 6, "field": "unit", "code": "unknown_unit"},
            ],
        )

    def test_an_inactive_category_is_not_silently_reused(self):
        Category.objects.create(business=self.w.a, name="Archived", is_active=False)
        body = self.preview(make_csv([row("A-1", category="archived")])).json()
        self.assertEqual(
            body["errors"], [{"row": 1, "field": "category", "code": "inactive_reference"}]
        )

    def test_a_new_name_used_by_many_rows_is_created_once(self):
        data = make_csv(
            [row(f"N-{n}", category="Fresh", brand="FRESH" if n % 2 else "Fresh") for n in range(6)]
        )
        self.assertEqual(self.apply(data).status_code, 201)
        self.assertEqual(Category.objects.filter(name="Fresh").count(), 1)
        self.assertEqual(Brand.objects.filter(business=self.w.a, name__iexact="fresh").count(), 1)
        self.assertEqual(AuditEvent.objects.filter(action="category.created").count(), 1)

    def test_other_business_data_is_never_matched(self):
        Category.objects.create(business=self.w.b, name="Theirs")
        catalog_services.create_product(
            self.w.b,
            self.w.b_owner,
            {
                "sku": "B-ONLY",
                "name": "x",
                "unit": Unit.objects.get(business=self.w.b, name="Piece"),
                "price_amount": D("1"),
                "barcodes": ["B-CODE"],
            },
        )
        data = make_csv([row("B-ONLY", category="Theirs", barcodes="B-CODE")])
        self.assertEqual(self.apply(data).status_code, 201)
        mine = self.product("B-ONLY")
        self.assertEqual(mine.category.business, self.w.a)
        self.assertEqual(mine.barcodes.get().business, self.w.a)
        self.assertEqual(Product.objects.filter(sku="B-ONLY").count(), 2)


class FileFormatTests(CsvCase):
    ROWS = [
        row("F-1", f"{RUSSIAN}", category=TURKMEN, brand="Bosch", price="12.50", barcodes="1|2"),
        row("F-2", f"Şäher {TURKMEN}", "Litre", price="0.05", return_days="7"),
    ]

    def created(self):
        return {
            p.sku: (p.name, p.unit.name, p.price_amount, p.return_days)
            for p in Product.objects.filter(sku__in=["F-1", "F-2"])
        }

    def test_semicolon_and_comma_files_give_the_same_products(self):
        semicolon = make_csv(self.ROWS, delimiter=";")
        comma = make_csv(self.ROWS, delimiter=",")
        self.assertEqual(self.apply(semicolon).status_code, 201)
        first = self.created()
        Product.objects.filter(sku__in=["F-1", "F-2"]).delete()
        self.assertEqual(self.apply(comma).status_code, 201)
        self.assertEqual(self.created(), first)
        self.assertEqual(first["F-1"][2], D("12.50"))

    def test_a_decimal_comma_is_accepted(self):
        semicolon = make_csv([row("D-1", price="12,50", default_cost="7,5")])
        self.assertEqual(self.apply(semicolon).status_code, 201)
        self.assertEqual(self.product("D-1").price_amount, D("12.50"))
        self.assertEqual(self.product("D-1").default_purchase_cost, D("7.50"))
        in_comma_file = make_csv([row("D-2", price="3,25")], delimiter=",")  # quoted by the writer
        self.assertIn(b'"3,25"', in_comma_file)
        self.assertEqual(self.apply(in_comma_file).status_code, 201)
        self.assertEqual(self.product("D-2").price_amount, D("3.25"))

    def test_the_byte_order_mark_is_optional(self):
        for number, bom in enumerate((True, False)):
            sku = f"BOM-{number}"
            response = self.apply(make_csv([row(sku)], bom=bom))
            self.assertEqual(response.status_code, 201, response.content)
            self.assertTrue(Product.objects.filter(sku=sku).exists())

    def test_line_endings_a_missing_final_newline_and_blank_lines(self):
        unix = make_csv([row("L-1"), row("L-2")], eol="\n").rstrip(b"\n")
        self.assertEqual(self.apply(unix).json(), {"created": 2})
        # a blank line still counts as a row position, so row numbers match the file
        gap = make_csv([row("G-1"), [], [], row("G-2", price="bad"), row("G-3")])
        body = self.preview(gap).json()
        self.assertEqual(body["rows"], 3)
        self.assertEqual(body["errors"], [{"row": 4, "field": "price", "code": "invalid_number"}])
        # and rows of only empty cells (a spreadsheet's leftovers) are ignored
        padded = make_csv([row("P-1"), [""] * len(HEADER), row("P-2")])
        self.assertEqual(self.apply(padded).json(), {"created": 2})

    def test_russian_and_turkmen_text_survive_the_import(self):
        self.assertEqual(self.apply(make_csv(self.ROWS, bom=True)).status_code, 201)
        got = self.created()
        self.assertEqual(got["F-1"][0], RUSSIAN)
        self.assertEqual(got["F-2"][0], f"Şäher {TURKMEN}")
        self.assertEqual(self.product("F-1").category.name, TURKMEN)
        exported = parse_export(self.owner.get(self.export_url))
        self.assertIn(RUSSIAN, [r["name"] for r in exported])
        self.assertIn(TURKMEN, [r["category"] for r in exported])

    def test_header_names_ignore_case_and_spaces_and_optional_columns_may_be_missing(self):
        data = make_csv([["Z-1", "Zed", "pc", "5"]], header=[" SKU", "Name ", "UNIT", "Price"])
        self.assertEqual(self.apply(data).status_code, 201)
        product = self.product("Z-1")
        self.assertEqual((product.price_currency, product.warranty_months), ("TMT", 0))
        self.assertIsNone(product.return_days)

    def test_columns_may_come_in_any_order(self):
        data = make_csv(
            [["9.99", "pc", "Any order", "A-1"]], header=["price", "unit", "name", "sku"]
        )
        self.assertEqual(self.apply(data).status_code, 201)
        self.assertEqual(self.product("A-1").price_amount, D("9.99"))

    def test_a_bad_header_is_refused_with_the_columns_at_fault(self):
        cases = [
            (["sku", "name", "unit", "price", "colour"], {"unknown": ["colour"], "missing": []}),
            (["sku", "name", "unit"], {"unknown": [], "missing": ["price"]}),
            (["name", "price"], {"unknown": [], "missing": ["sku", "unit"]}),
        ]
        for header, expected in cases:
            with self.subTest(header=header):
                response = self.preview(make_csv([], header=header))
                self.assertEqual(response.status_code, 400)
                error = self.error(response)
                self.assertEqual(error["code"], "invalid_header")
                self.assertEqual(error["params"]["unknown"], expected["unknown"])
                self.assertEqual(error["params"]["missing"], expected["missing"])
                self.assertEqual(self.apply(make_csv([], header=header)).status_code, 400)
        duplicate = self.preview(make_csv([], header=["sku", "name", "unit", "price", "SKU"]))
        self.assertEqual(self.error(duplicate)["code"], "invalid_header")
        self.assertEqual(self.error(duplicate)["params"]["duplicate"], ["sku"])
        no_header = self.preview(b"\n\n   \n")
        self.assertEqual(self.error(no_header)["code"], "invalid_header")

    def test_a_missing_empty_or_unreadable_file(self):
        none = self.owner.post(self.preview_url, {}, format="multipart")
        self.assertEqual(self.error(none)["code"], "file_required")
        empty = self.preview(b"")
        self.assertEqual(self.error(empty)["code"], "file_required")
        wrong_field = self.owner.post(
            self.apply_url, {"data": SimpleUploadedFile("a.csv", b"x")}, format="multipart"
        )
        self.assertEqual(self.error(wrong_field)["code"], "file_required")
        windows = "sku;name;unit;price\r\nA;Привет;pc;1\r\n".encode("cp1251")
        unreadable = self.preview(windows)
        self.assertEqual(unreadable.status_code, 400)
        self.assertEqual(self.error(unreadable)["code"], "invalid_file")
        self.assertEqual(self.apply(windows).status_code, 400)
        nul = self.preview(b"sku;name;unit;price\r\nA;x\x00y;pc;1\r\n")
        self.assertEqual(self.error(nul)["code"], "invalid_file")
        self.assertEqual(
            self.owner.post(self.preview_url, {"file": "x"}, format="json").status_code, 415
        )
        self.assertFalse(Product.objects.filter(sku="A").exists())


class LimitTests(CsvCase):
    def rows(self, n, prefix="L"):
        return [row(f"{prefix}-{i:05d}", f"Item {i}", price="1.00") for i in range(n)]

    def test_two_thousand_rows_are_allowed_and_2001_are_not(self):
        body = self.preview(make_csv(self.rows(2000))).json()
        self.assertEqual((body["rows"], body["valid"], body["error_count"]), (2000, 2000, 0))
        for call in (self.preview, self.apply):
            response = call(make_csv(self.rows(2001)))
            self.assertEqual(response.status_code, 400)
            error = self.error(response)
            self.assertEqual(error["code"], "import_too_large")
            self.assertEqual(error["params"], {"max_rows": 2000, "max_bytes": 1048576})
        self.assertEqual(Product.objects.filter(sku__startswith="L-").count(), 0)

    def test_blank_rows_do_not_count_towards_the_limit(self):
        data = make_csv([*self.rows(2000), [], [], []])
        self.assertEqual(self.preview(data).json()["rows"], 2000)

    def test_a_big_file_is_refused_by_size(self):
        padded = make_csv(
            [row("BIG-1", "n" * 200) for _ in range(100)] + [row("BIG-2", "x" * 1_048_576)]
        )
        self.assertGreater(len(padded), 1_048_576)
        for call in (self.preview, self.apply):
            response = call(padded)
            self.assertEqual(response.status_code, 400)
            self.assertEqual(self.error(response)["code"], "import_too_large")
        # a file of exactly 1 MB is not too big (its long names are row errors), one byte more is
        head = make_csv([row(f"EX-{i}", "n" * 1000) for i in range(900)])

        def last(k):
            return (";".join(row("EX-LAST", "n" * k)) + "\r\n").encode()

        exactly = head + last(1_048_576 - len(head) - len(last(0)))
        self.assertEqual(len(exactly), 1_048_576)
        response = self.preview(exactly)
        self.assertEqual(response.status_code, 200, response.content)
        self.assertEqual(response.json()["rows"], 901)
        self.assertEqual(self.error(self.preview(exactly + b"x"))["code"], "import_too_large")

    def test_a_request_announcing_a_far_bigger_body_is_refused_unread(self):
        huge = make_csv([row("H-1", "x" * 2_500_000)])
        response = self.preview(huge)
        self.assertEqual(response.status_code, 400)
        self.assertEqual(self.error(response)["code"], "import_too_large")

    def test_only_the_first_errors_are_shown(self):
        data = make_csv([row(f"E-{n}", price="bad") for n in range(300)])
        body = self.preview(data).json()
        self.assertEqual(len(body["errors"]), 200)
        self.assertEqual((body["error_count"], body["truncated"]), (300, True))
        self.assertEqual((body["rows"], body["valid"]), (300, 0))
        self.assertEqual(body["errors"][-1]["row"], 200)
        applied = self.apply(data)
        self.assertEqual(applied.status_code, 409)
        params = self.error(applied)["params"]
        self.assertEqual((len(params["errors"]), params["error_count"]), (50, 300))

    def test_a_large_valid_import_is_applied_in_one_go(self):
        rows = [
            row(
                f"BULK-{i:05d}",
                f"Item {i}",
                category=f"Cat {i % 20}",
                brand=f"Brand {i % 10}",
                barcodes=f"BULKBC-{i}",
            )
            for i in range(400)
        ]
        response = self.apply(make_csv(rows))
        self.assertEqual(response.json(), {"created": 400})
        self.assertEqual(Product.objects.filter(sku__startswith="BULK-").count(), 400)
        self.assertEqual(Category.objects.filter(name__startswith="Cat ").count(), 20)
        self.assertEqual(Barcode.objects.filter(code__startswith="BULKBC-").count(), 400)


class AccessTests(CsvCase):
    def test_only_owner_and_manager_may_import(self):
        data = make_csv([row("R-1")])
        for role in (Role.SALES, Role.WAREHOUSE):
            for url in (self.preview_url, self.apply_url):
                self.assertEqual(send(self.w.api[role], url, data).status_code, 403)
        self.assertEqual(self.apply(data, client=self.manager).status_code, 201)
        self.assertEqual(self.product("R-1").business, self.w.a)

    def test_signed_out_and_other_businesses(self):
        data = make_csv([row("R-2")])
        for url in (self.preview_url, self.apply_url):
            self.assertEqual(send(APIClient(), url, data).status_code, 401)
            self.assertEqual(send(self.w.b_api, url, data).status_code, 404)
        self.assertFalse(Product.objects.filter(sku="R-2").exists())

    def test_importing_into_business_b_creates_products_in_b_only(self):
        b_base = f"/api/v1/businesses/{self.w.b.pk}"
        Unit.objects.create(business=self.w.b, name="Box", symbol="bx", decimal_places=0)
        data = make_csv([row("B-NEW", unit="box", category="B cat")])
        self.assertEqual(
            send(self.w.b_api, f"{b_base}/catalog/import/apply/", data).status_code, 201
        )
        created = Product.objects.get(sku="B-NEW")
        self.assertEqual((created.business, created.category.business), (self.w.b, self.w.b))
        self.assertFalse(Product.objects.filter(business=self.w.a, sku="B-NEW").exists())
        self.assertFalse(Category.objects.filter(business=self.w.a, name="B cat").exists())
        # business A has no unit "box": the same file does not import there
        refused = self.apply(data)
        self.assertEqual(self.error(refused)["params"]["errors"][0]["code"], "unknown_unit")


class ImportConcurrencyTests(APITransactionTestCase):
    def test_two_simultaneous_applies_of_one_file_make_one_set_of_products(self):
        w = World()
        data = make_csv(
            [
                row(f"CC-{n}", category=f"Cat {n % 3}", brand="Same brand", barcodes=f"CB{n}")
                for n in range(40)
            ]
        )
        barrier = threading.Barrier(2)

        def attempt():
            try:
                barrier.wait(timeout=10)
                return send(client_for(w.owner), f"{w.base}/catalog/import/apply/", data)
            finally:
                connections.close_all()

        with ThreadPoolExecutor(max_workers=2) as pool:
            responses = list(pool.map(lambda _: attempt(), range(2)))
        self.assertEqual(sorted(r.status_code for r in responses), [201, 409])
        self.assertEqual(Product.objects.filter(sku__startswith="CC-").count(), 40)
        self.assertEqual(Category.objects.filter(business=w.a, name__startswith="Cat ").count(), 3)
        self.assertEqual(Brand.objects.filter(business=w.a, name="Same brand").count(), 1)
        self.assertEqual(Barcode.objects.filter(business=w.a, code__startswith="CB").count(), 40)
        self.assertEqual(AuditEvent.objects.filter(action="catalog.imported").count(), 1)
        loser = [r for r in responses if r.status_code == 409][0]
        self.assertEqual(loser.json()["error"]["code"], "import_invalid")
        # every row now clashes twice: its SKU and its barcode
        self.assertEqual(loser.json()["error"]["params"]["error_count"], 80)
        self.assertEqual(ledger_differences(), [])
