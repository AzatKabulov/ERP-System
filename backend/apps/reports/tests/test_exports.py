"""The CSV exports: the file format, what is in it, who may download it, and what it leaves out."""

import csv
import io
from datetime import date
from decimal import Decimal
from unittest import mock

from apps.audit.models import AuditEvent
from apps.businesses.models import Membership, Role
from apps.businesses.permissions import MATRIX
from apps.catalog.models import ReorderSetting
from apps.expenses import services as expense_services
from apps.expenses.models import ExpenseCategory
from apps.inventory.tests.support import make_product
from apps.purchasing import services as purchasing
from apps.purchasing.models import Supplier
from apps.reports import returns as returns_report
from apps.reports import stock as stock_report
from apps.reports.tests.support import PERIOD, WHOLE, ReportsCase, at
from apps.sales import returns as sale_returns
from apps.sales import services as sales

D = Decimal
BOM = b"\xef\xbb\xbf"
TURKMEN = "Şäher Ätiýaçlyk Ýüpek Çäkli Žeňil Öý Ülke"
RUSSIAN = "Тормозные колодки Ёлка"


def table(response) -> list[list[str]]:
    return list(csv.reader(io.StringIO(response.content.decode("utf-8-sig")), delimiter=";"))


class ExportCase(ReportsCase):
    def download(self, slug, client=None, **params):
        return (client or self.owner).get(
            f"{self.w.base}/reports/{slug}/export/", {**WHOLE, **params}
        )


class FileFormatTests(ExportCase):
    def test_every_export_is_a_utf8_csv_download_with_a_byte_order_mark(self):
        for slug in ("sales", "stock", "purchasing", "returns", "expenses"):
            with self.subTest(slug=slug):
                response = self.download(slug)
                self.assertEqual(response.status_code, 200, response.content)
                self.assertEqual(response["Content-Type"], "text/csv; charset=utf-8")
                self.assertEqual(
                    response["Content-Disposition"],
                    f'attachment; filename="{slug}-2026-10-01-2026-10-03.csv"',
                )
                self.assertEqual(response["X-Content-Type-Options"], "nosniff")
                self.assertEqual(response["Cache-Control"], "private, no-store")
                self.assertTrue(response.content.startswith(BOM))
                self.assertNotIn(b"\xef\xbb\xbf", response.content[3:])
                self.assertIn(b"\r\n", response.content)

    def test_the_client_cannot_turn_the_download_into_an_error_with_an_accept_header(self):
        for accept in ("application/json", "text/csv", "application/pdf", "*/*"):
            with self.subTest(accept=accept):
                response = self.owner.get(
                    f"{self.w.base}/reports/sales/export/", WHOLE, HTTP_ACCEPT=accept
                )
                self.assertEqual(response.status_code, 200)
                self.assertEqual(response["Content-Type"], "text/csv; charset=utf-8")

    def test_the_file_name_follows_the_period(self):
        response = self.download("sales", date_from="2026-09-01", date_to="2026-09-30")
        self.assertIn('filename="sales-2026-09-01-2026-09-30.csv"', response["Content-Disposition"])
        with at("2026-10-03", "20:00"):
            default = self.owner.get(f"{self.w.base}/reports/expenses/export/")
        disposition = default["Content-Disposition"]
        self.assertIn('filename="expenses-2026-10-01-2026-10-03.csv"', disposition)

    def test_errors_stay_json_and_leave_no_audit_event(self):
        before = AuditEvent.objects.filter(action="report.exported").count()
        bad = self.owner.get(
            f"{self.w.base}/reports/sales/export/", {"date_from": "x"}, HTTP_ACCEPT="text/csv"
        )
        self.assertEqual(bad.status_code, 400)
        self.assertEqual(bad.json()["error"]["code"], "validation_error")
        denied = self.sales.get(f"{self.w.base}/reports/sales/export/", WHOLE)
        self.assertEqual(denied.status_code, 403)
        self.assertEqual(AuditEvent.objects.filter(action="report.exported").count(), before)


class ContentTests(ExportCase):
    def test_sales_one_row_per_day(self):
        self.assertEqual(
            table(self.download("sales")),
            [
                ["date", "sales_count", "revenue", "refunds", "net_sales"],
                ["2026-10-01", "2", "542.50", "0.00", "542.50"],
                ["2026-10-02", "1", "665.00", "112.50", "552.50"],
                ["2026-10-03", "1", "110.00", "285.00", "-175.00"],
            ],
        )

    def test_stock_low_stock_lines_then_the_value_rows(self):
        self.assertEqual(
            table(self.download("stock")),
            [
                [
                    "section",
                    "location",
                    "sku",
                    "product",
                    "condition",
                    "on_hand",
                    "minimum",
                    "target",
                    "value",
                ],
                ["low_stock", "A Store", "BP-1", "Brake pad", "", "7.000", "10.000", "30.000", ""],
                ["low_stock", "A Store", "SP-1", "Spark plug", "", "0.000", "4.000", "10.000", ""],
                [
                    "low_stock",
                    "A Warehouse",
                    "OIL-1",
                    "Engine oil",
                    "",
                    "20.000",
                    "30.000",
                    "50.000",
                    "",
                ],
                ["value", "A Store", "", "", "sellable", "", "", "", "629.00"],
                ["value", "A Store", "", "", "damaged", "", "", "", "100.00"],
                ["value", "A Store", "", "", "inspection", "", "", "", "50.00"],
                ["value", "A Store", "", "", "in_transit", "", "", "", "0.00"],
                ["value", "A Warehouse", "", "", "sellable", "", "", "", "815.00"],
                ["value", "A Warehouse", "", "", "damaged", "", "", "", "0.00"],
                ["value", "A Warehouse", "", "", "inspection", "", "", "", "0.00"],
                ["value", "A Warehouse", "", "", "in_transit", "", "", "", "0.00"],
                ["value_total", "", "", "", "", "", "", "", "1594.00"],
            ],
        )

    def test_purchasing_by_supplier(self):
        self.assertEqual(
            table(self.download("purchasing")),
            [
                ["supplier", "orders", "received_value"],
                ["Ashgabat Parts", "1", "640.00"],
                ["Türkmen Täze", "1", "75.00"],
            ],
        )

    def test_returns_by_reason(self):
        self.assertEqual(
            table(self.download("returns")),
            [
                ["reason", "returns_count", "refund"],
                ["Wrong size", "2", "207.50"],
                ["Defective", "1", "190.00"],
            ],
        )

    def test_expenses_by_category(self):
        self.assertEqual(
            table(self.download("expenses")),
            [
                ["category", "count", "total"],
                ["Аренда", "1", "200.00"],
                ["Транспорт", "1", "45.50"],
            ],
        )

    def test_the_location_filter_applies(self):
        rows = table(self.download("sales", location=self.w.warehouse.pk))
        self.assertEqual(rows[1:], [["2026-10-03", "1", "110.00", "0.00", "110.00"]])

    def test_the_file_is_complete_where_the_screen_is_capped(self):
        with (
            mock.patch.object(stock_report, "LOW_STOCK_ROWS", 1),
            mock.patch.object(returns_report, "TOP_REASONS", 1),
        ):
            self.assertEqual(len(table(self.download("stock"))), 1 + 3 + 8 + 1)
            self.assertEqual(len(table(self.download("returns"))), 1 + 2)
            self.assertEqual(len(self.ok("reports/stock/", **WHOLE)["low_stock"]), 1)

    def test_amounts_are_left_out_without_the_matching_right(self):
        with mock.patch.dict(MATRIX, {"purchasing.cost.view": frozenset({Role.OWNER})}):
            rows = table(self.download("purchasing", client=self.manager))
        self.assertEqual(
            rows, [["supplier", "orders"], ["Ashgabat Parts", "1"], ["Türkmen Täze", "1"]]
        )
        with mock.patch.dict(MATRIX, {"stock.cost.view": frozenset({Role.OWNER})}):
            response = self.download("stock", client=self.manager)
        self.assertEqual({row[0] for row in table(response)[1:]}, {"low_stock"})  # no value rows
        self.assertNotIn("1594.00", response.content.decode())

    def test_every_download_is_audited_with_what_was_asked_for(self):
        expected_rows = {"sales": 3, "stock": 12, "purchasing": 2, "returns": 2, "expenses": 2}
        for slug in expected_rows:
            self.download(slug, location=self.w.store.pk if slug == "sales" else "")
        events = AuditEvent.objects.filter(action="report.exported", business=self.w.a)
        self.assertEqual(events.count(), 5)
        by_slug = {e.metadata["slug"]: e for e in events}
        sales_event = by_slug["sales"]
        self.assertEqual(
            sales_event.metadata,
            {
                "slug": "sales",
                "period": PERIOD,
                "location": str(self.w.store.pk),
                "rows": 3,
            },
        )
        self.assertEqual(sales_event.actor, self.s.owner)
        for slug, rows in expected_rows.items():
            self.assertEqual(by_slug[slug].metadata["rows"], rows, slug)
        self.assertEqual(by_slug["stock"].metadata["location"], None)


class RoleTests(ExportCase):
    def test_only_owner_and_manager_download_reports(self):
        for slug in ("sales", "stock", "purchasing", "returns", "expenses"):
            for role, status in (
                (Role.OWNER, 200),
                (Role.MANAGER, 200),
                (Role.SALES, 403),
                (Role.WAREHOUSE, 403),
            ):
                with self.subTest(slug=slug, role=role):
                    response = self.download(slug, client=self.w.api[role])
                    self.assertEqual(response.status_code, status)
            with self.subTest(slug=slug, who="another business"):
                self.assertEqual(self.download(slug, client=self.w.b_api).status_code, 404)

    def test_the_expense_export_follows_the_expense_right(self):
        with mock.patch.dict(MATRIX, {"expense.view": frozenset({Role.OWNER})}):
            self.assertEqual(self.download("expenses", client=self.manager).status_code, 403)
            self.assertEqual(self.download("sales", client=self.manager).status_code, 200)


class TextSafetyTests(ExportCase):
    """Names and reasons are typed by people: spreadsheets must never run them as formulas, and
    Russian and Turkmen letters must arrive unchanged."""

    FORMULAS = ["=SUM(1;2)", "+1+1", "-2+3", "@cmd", "\tTab", '=HYPERLINK("http://x")']

    def setUp(self):
        super().setUp()
        a, owner = self.w.a, self.s.owner
        member = Membership.objects.get(user=owner, business=a)
        with at("2026-10-03", "17:00"):
            self.sku_product = make_product(a, "-SKU", "=Bad product", self.w.unit, "5.00")
            ReorderSetting.objects.create(
                business=a, product=self.sku_product, location=self.w.store, minimum=5, target=9
            )
            self.w.stock(self.w.oil, self.w.store, 3, "8.00")
            sale = sales.complete_sale(
                a,
                owner,
                {
                    "location": self.w.store,
                    "lines": [{"product": self.w.oil, "quantity": D(2), "unit_price": D("30.00")}],
                    "payment_method": "cash",
                },
            )
            for reason in ("=SUM(1;2)", RUSSIAN):
                sale_returns.create_return(
                    a,
                    owner,
                    member,
                    sale.pk,
                    {
                        "lines": [
                            {
                                "sale_line": sale.lines.get().pk,
                                "quantity": D("0.5"),
                                "condition": "sellable",
                            }
                        ],
                        "reason": reason,
                    },
                )
            for name in (*self.FORMULAS, TURKMEN, RUSSIAN):
                supplier = Supplier.objects.create(business=a, name=name)
                placed = purchasing.create_order(
                    a,
                    owner,
                    {
                        "supplier": supplier,
                        "location": self.w.store,
                        "lines": [{"product": self.w.pad, "quantity": D(1), "unit_cost": D(1)}],
                    },
                )
                purchasing.submit_order(a, owner, placed.pk)
            for name in (*self.FORMULAS, TURKMEN, RUSSIAN):
                category = ExpenseCategory.objects.create(business=a, name=name)
                expense_services.create_expense(
                    a,
                    owner,
                    member,
                    {
                        "category": category,
                        "location": self.w.store,
                        "amount": D("1.00"),
                        "spent_on": date(2026, 10, 3),
                    },
                )

    def cells(self, slug, column):
        rows = table(self.download(slug))
        index = rows[0].index(column)
        return {row[index] for row in rows[1:]}

    def test_cells_that_could_be_formulas_get_a_leading_apostrophe(self):
        for slug, column in (("purchasing", "supplier"), ("expenses", "category")):
            cells = self.cells(slug, column)
            for formula in self.FORMULAS:
                with self.subTest(slug=slug, text=formula):
                    self.assertIn("'" + formula, cells)
                    self.assertNotIn(formula, cells)
        self.assertIn("'=SUM(1;2)", self.cells("returns", "reason"))  # also with a `;` inside
        self.assertIn("'=Bad product", self.cells("stock", "product"))
        self.assertIn("'-SKU", self.cells("stock", "sku"))

    def test_russian_and_turkmen_letters_arrive_unchanged(self):
        for slug, column in (("purchasing", "supplier"), ("expenses", "category")):
            cells = self.cells(slug, column)
            self.assertIn(TURKMEN, cells)
            self.assertIn(RUSSIAN, cells)
        self.assertIn(RUSSIAN, self.cells("returns", "reason"))
        raw = self.download("purchasing").content
        self.assertIn(TURKMEN.encode("utf-8"), raw)

    def test_numbers_and_dates_are_not_touched(self):
        rows = table(self.download("sales"))
        self.assertTrue(all(not cell.startswith("'") for row in rows for cell in row))
        # a negative number stays a number (3 October: 170.00 sold, 315.00 refunded)
        self.assertIn("-145.00", {cell for row in rows for cell in row})
