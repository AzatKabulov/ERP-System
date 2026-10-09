"""Who may read the reports, what the query string may say, and that nothing crosses businesses."""

from decimal import Decimal
from unittest import mock

from django.db import connection
from django.test.utils import CaptureQueriesContext
from rest_framework.test import APIClient

from apps.businesses.models import Role
from apps.businesses.permissions import MATRIX
from apps.common.testing import client_for, make_business, make_member
from apps.reports.tests.support import PERIOD, WHOLE, ReportsCase, at
from apps.sales import services as sales

REPORTS = [
    "reports/summary/",
    "reports/sales/",
    "reports/stock/",
    "reports/purchasing/",
    "reports/returns/",
    "reports/expenses/",
]
EXPORTS = [path + "export/" for path in REPORTS if "summary" not in path]
READ_ONLY_ROUTES = [*REPORTS, *EXPORTS, "dashboard/", "audit/", "audit/actions/"]
# The two roles that may read reports; sales and warehouse only get the dashboard.
OWNER_AND_MANAGER = [*REPORTS, *EXPORTS, "audit/", "audit/actions/"]


class RoleTests(ReportsCase):
    def test_owner_and_manager_read_everything_sales_and_warehouse_nothing_but_the_dashboard(self):
        expected = {
            Role.OWNER: 200,
            Role.MANAGER: 200,
            Role.SALES: 403,
            Role.WAREHOUSE: 403,
        }
        for path in OWNER_AND_MANAGER:
            for role, status in expected.items():
                with self.subTest(path=path, role=role):
                    response = self.get(self.w.api[role], path)
                    self.assertEqual(response.status_code, status, response.content)
                    if status == 403:
                        self.assertEqual(response.json()["error"]["code"], "permission_denied")
        for role in expected:
            with self.subTest(path="dashboard/", role=role):
                self.assertEqual(self.get(self.w.api[role], "dashboard/").status_code, 200)

    def test_a_manager_sees_exactly_what_the_owner_sees(self):
        for path in [*REPORTS, "dashboard/"]:
            with self.subTest(path=path):
                with at("2026-10-03", "20:00"):
                    owner = self.get(self.owner, path, **WHOLE).json()
                    manager = self.get(self.manager, path, **WHOLE).json()
                self.assertEqual(owner, manager)

    def test_nobody_writes(self):
        for path in READ_ONLY_ROUTES:
            for method in ("post", "put", "patch", "delete"):
                with self.subTest(path=path, method=method):
                    response = getattr(self.owner, method)(f"{self.w.base}/{path}", {})
                    self.assertEqual(response.status_code, 405)
        for path in OWNER_AND_MANAGER:
            with self.subTest(path=path, role="sales"):
                self.assertEqual(self.sales.post(f"{self.w.base}/{path}", {}).status_code, 403)

    def test_anonymous_callers_are_asked_to_sign_in(self):
        for path in READ_ONLY_ROUTES:
            with self.subTest(path=path):
                response = APIClient().get(f"{self.w.base}/{path}")
                self.assertEqual(response.status_code, 401)

    def test_a_report_open_to_a_seller_is_limited_to_the_sellers_location(self):
        with mock.patch.dict(MATRIX, {"report.view": frozenset({Role.OWNER, Role.SALES})}):
            body = self.ok("reports/summary/", client=self.sales, **WHOLE)
            sales = self.ok("reports/sales/", client=self.sales, **WHOLE)
            denied = self.get(self.sales, "reports/summary/", location=self.w.warehouse.pk, **WHOLE)
            own = self.get(self.sales, "reports/summary/", location=self.w.store.pk, **WHOLE)
            export = self.get(
                self.sales, "reports/sales/export/", location=self.w.warehouse.pk, **WHOLE
            )
        # the store's figures only; no cost, profit, expenses or inventory value for a seller
        self.assertEqual(
            body,
            {
                "period": PERIOD,
                "location": None,
                "revenue": "1207.50",
                "refunds": "397.50",
                "net_sales": "810.00",
                "sales_count": 3,
                "returns_count": 3,
                "low_stock_count": 2,
                "open_orders_count": 0,
            },
        )
        self.assertNotIn("cost_of_goods", sales)
        self.assertNotIn("gross_profit", sales)
        self.assertEqual(sales["revenue"], "1207.50")
        self.error(denied, 403, "location_not_permitted")
        self.error(export, 403, "location_not_permitted")
        self.assertEqual(own.status_code, 200)

    def test_a_warehouse_keeper_cannot_ask_for_the_store(self):
        with mock.patch.dict(MATRIX, {"report.view": frozenset({Role.OWNER, Role.WAREHOUSE})}):
            mine = self.ok("reports/stock/", client=self.warehouse, **WHOLE)
            theirs = self.get(self.warehouse, "reports/stock/", location=self.w.store.pk)
        self.assertEqual(mine["low_stock_count"], 1)
        self.assertNotIn("value", mine)  # no stock.cost.view
        self.error(theirs, 403, "location_not_permitted")


class IsolationTests(ReportsCase):
    def test_a_member_of_another_business_finds_nothing(self):
        other = self.w.b_api
        for path in READ_ONLY_ROUTES:
            with self.subTest(path=path):
                error = self.error(self.get(other, path), 404, "not_found")
                self.assertNotIn("A Store", str(error))

    def test_my_owner_cannot_open_the_other_businesss_reports(self):
        for path in READ_ONLY_ROUTES:
            with self.subTest(path=path):
                response = self.owner.get(f"/api/v1/businesses/{self.w.b.pk}/{path}")
                self.assertEqual(response.status_code, 404)

    def test_each_business_sees_only_its_own_sales_and_expenses(self):
        base = f"/api/v1/businesses/{self.w.b.pk}"
        sold = self.w.b_api.get(f"{base}/reports/sales/", WHOLE).json()
        self.assertEqual((sold["sales_count"], sold["revenue"]), (1, "1000.00"))
        self.assertEqual((sold["cost_of_goods"], sold["gross_profit"]), ("20.00", "980.00"))
        spent = self.w.b_api.get(f"{base}/reports/expenses/", WHOLE).json()
        self.assertEqual((spent["total"], spent["count"]), ("777.00", 1))
        # and business A's figures do not include them (see the full-body tests): 1317.50, 245.50
        mine = self.ok("reports/summary/", **WHOLE)
        self.assertEqual((mine["revenue"], mine["expenses"]), ("1317.50", "245.50"))

    def test_a_location_of_another_business_is_refused_like_a_forbidden_one(self):
        for path in REPORTS:
            with self.subTest(path=path):
                response = self.get(self.owner, path, location=self.w.b_store.pk, **WHOLE)
                self.error(response, 403, "location_not_permitted")
        nobody = "00000000-0000-4000-8000-000000000000"
        unknown = self.get(self.owner, "reports/sales/", location=nobody)
        self.error(unknown, 403, "location_not_permitted")


class ParameterTests(ReportsCase):
    def test_malformed_dates_name_the_field(self):
        for path in [*REPORTS, *EXPORTS]:
            for name in ("date_from", "date_to"):
                for value in ("yesterday", "2026-13-01", "2026-02-30", "2026-1-5", "20261001"):
                    with self.subTest(path=path, name=name, value=value):
                        response = self.get(self.owner, path, **{name: value})
                        error = self.error(response, 400, "validation_error")
                        self.assertEqual(error["fields"][name][0]["code"], "invalid")

    def test_a_reversed_period_is_refused(self):
        for path in [*REPORTS, *EXPORTS]:
            with self.subTest(path=path):
                response = self.get(self.owner, path, date_from="2026-10-03", date_to="2026-10-01")
                error = self.error(response, 400, "validation_error")
                self.assertEqual(error["fields"]["date_from"][0]["code"], "after_date_to")

    def test_a_period_may_be_366_days_long_but_not_367(self):
        for path in [*REPORTS, *EXPORTS]:
            with self.subTest(path=path):
                long = self.get(self.owner, path, date_from="2026-01-01", date_to="2027-01-01")
                self.assertEqual(long.status_code, 200, long.content)
                too_long = self.get(self.owner, path, date_from="2026-01-01", date_to="2027-01-02")
                error = self.error(too_long, 400, "range_too_long")
                self.assertEqual(error["params"], {"max_days": 366})

    def test_blank_dates_mean_the_defaults_and_unknown_parameters_are_ignored(self):
        with at("2026-10-03", "20:00"):
            body = self.ok("reports/summary/", date_from="", date_to="", colour="red")
        self.assertEqual(body["period"], PERIOD)

    def test_a_malformed_location_is_a_validation_error(self):
        for path in REPORTS:
            with self.subTest(path=path):
                response = self.get(self.owner, path, location="the-store")
                error = self.error(response, 400, "validation_error")
                self.assertIn("location", error["fields"])


class EmptyBusinessTests(ReportsCase):
    def setUp(self):
        super().setUp()
        shop = make_business("Fresh Shop", locations=("Main",))
        self.fresh = client_for(make_member(shop, Role.OWNER, username="fresh-owner"))
        self.fresh_base = f"/api/v1/businesses/{shop.pk}"

    def read(self, path):
        response = self.fresh.get(f"{self.fresh_base}/{path}", WHOLE)
        self.assertEqual(response.status_code, 200, response.content)
        return {k: v for k, v in response.json().items() if k not in ("period", "location")}

    def test_every_report_is_zeros_and_empty_lists(self):
        self.assertEqual(
            self.read("reports/summary/"),
            {
                "revenue": "0.00",
                "refunds": "0.00",
                "net_sales": "0.00",
                "sales_count": 0,
                "returns_count": 0,
                "cost_of_goods": "0.00",
                "gross_profit": "0.00",
                "expenses": "0.00",
                "result": "0.00",
                "inventory_value": "0.00",
                "low_stock_count": 0,
                "open_orders_count": 0,
            },
        )
        self.assertEqual(
            self.read("reports/purchasing/"),
            {
                "orders_count": 0,
                "by_status": [],
                "deliveries_count": 0,
                "ordered_total": "0.00",
                "received_value": "0.00",
                "by_supplier": [],
                "supplier_returns_count": 0,
                "supplier_returns_credit": "0.00",
            },
        )
        self.assertEqual(
            self.read("reports/returns/"),
            {
                "returns_count": 0,
                "refund_total": "0.00",
                "by_condition": [],
                "by_reason": [],
                "supplier_returns": {"count": 0, "credit": "0.00"},
            },
        )
        self.assertEqual(
            self.read("reports/expenses/"),
            {"total": "0.00", "count": 0, "by_category": [], "by_location": []},
        )
        self.assertEqual(self.read("reports/sales/")["by_day"], [])
        self.assertEqual(self.read("reports/stock/")["movements"], [])

    def test_the_exports_have_only_a_header(self):
        for path in EXPORTS:
            with self.subTest(path=path):
                response = self.fresh.get(f"{self.fresh_base}/{path}", WHOLE)
                self.assertEqual(response.status_code, 200)
                lines = response.content.decode("utf-8-sig").splitlines()
                expected_rows = 1 if "stock" in path else 0  # stock always ends with its total
                self.assertEqual(len(lines) - 1, expected_rows, lines)


class QueryCountTests(ReportsCase):
    """The number of queries is a property of the endpoint, not of the amount of data."""

    # measured: the membership lookup plus the figures themselves
    LIMITS = {
        "reports/summary/": 9,
        "reports/sales/": 9,
        "reports/stock/": 5,
        "reports/purchasing/": 7,
        "reports/returns/": 5,
        "reports/expenses/": 3,
        "dashboard/": 15,
        "audit/": 3,
        "audit/actions/": 2,
    }

    def count(self, client, path):
        params = WHOLE if path.startswith("reports/") else {}
        with CaptureQueriesContext(connection) as queries:
            response = client.get(f"{self.w.base}/{path}", params)
        self.assertEqual(response.status_code, 200, response.content)
        return len(queries)

    def test_each_endpoint_uses_a_small_fixed_number_of_queries(self):
        for path, limit in self.LIMITS.items():
            with self.subTest(path=path):
                self.assertLessEqual(self.count(self.owner, path), limit)

    def test_more_data_does_not_mean_more_queries(self):
        before = {path: self.count(self.owner, path) for path in self.LIMITS}
        with at("2026-10-03", "17:00"):
            for number in range(1, 6):
                self.w.stock(self.w.pad, self.w.store, 5, "50.00")
                sales.complete_sale(
                    self.w.a,
                    self.s.owner,
                    {
                        "location": self.w.store,
                        "lines": [
                            {
                                "product": self.w.pad,
                                "quantity": Decimal(number),
                                "unit_price": Decimal("99.00"),
                            }
                        ],
                        "payment_method": "card",
                    },
                )
        after = {path: self.count(self.owner, path) for path in self.LIMITS}
        self.assertEqual(before, after)
