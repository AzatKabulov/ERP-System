"""Reports, dashboard and history on a realistic amount of data (plan step 9.5): about 20,000
sales with their lines, 2,000 returns, 3,000 expenses, 20,000 audit events, a thousand purchase
orders and thousands of stock movements in one business.

Each endpoint must answer within a generous bound, with a fixed number of queries that does not
depend on the volume (the same number as in a business with a handful of rows), and with the
exact figures the generated data adds up to. The data is synthetic; the stock ledger checks
(`reconcile()`) are deliberately NOT run here.

Set ERP_VOLUME_VERBOSE=1 to print the timings."""

import os
import time
from decimal import Decimal

from django.db import connection
from django.test.utils import CaptureQueriesContext

from apps.common.testing import APITestCase, client_for
from apps.inventory.models import MovementType
from apps.reports.scope import money, round_money
from apps.reports.tests.support import at
from apps.reports.tests.volume import FIRST_DAY, LAST_DAY, build_shop

D = Decimal
SECONDS_ALLOWED = 5.0
PERIOD = {"date_from": FIRST_DAY.isoformat(), "date_to": LAST_DAY.isoformat()}
TIMINGS: dict[str, tuple[float, int]] = {}

REPORTS = ["summary", "sales", "stock", "purchasing", "returns", "expenses"]
EXPORTS = ["sales", "stock", "purchasing", "returns", "expenses"]
# The most queries each endpoint may use (the membership lookup is one of them).
QUERY_LIMITS = {
    "reports/summary/": 9,
    "reports/sales/": 9,
    "reports/stock/": 5,
    "reports/purchasing/": 7,
    "reports/returns/": 5,
    "reports/expenses/": 3,
    "reports/sales/export/": 10,
    "reports/stock/export/": 6,
    "reports/purchasing/export/": 8,
    "reports/returns/export/": 6,
    "reports/expenses/export/": 4,
    "dashboard/": 15,
    "audit/": 3,
    "audit/actions/": 2,
}


class VolumeTests(APITestCase):
    @classmethod
    def setUpTestData(cls):
        started = time.perf_counter()
        cls.big = build_shop(
            "Big Shop",
            sales=20000,
            returns=2000,
            expenses=3000,
            events=20000,
            orders=1000,
            movements=6000,
            seed=1,
        )
        cls.tiny = build_shop(
            "Tiny Shop",
            sales=30,
            returns=5,
            expenses=10,
            events=60,
            orders=20,
            movements=40,
            seed=2,
        )
        TIMINGS["building the data"] = (time.perf_counter() - started, 0)

    @classmethod
    def tearDownClass(cls):
        super().tearDownClass()
        if os.environ.get("ERP_VOLUME_VERBOSE"):
            print("\nVOLUME TIMINGS (seconds, queries)")
            for name, (seconds, queries) in sorted(TIMINGS.items()):
                print(f"  {name:<44}{seconds:7.3f} s {queries:3d} queries")

    # -- helpers ------------------------------------------------------------------------
    def fetch(self, shop, path, user=None, label=None, **params):
        client = client_for(user or shop.owner)
        url = f"/api/v1/businesses/{shop.business.pk}/{path}"
        with CaptureQueriesContext(connection) as queries:
            started = time.perf_counter()
            response = client.get(url, params)
            seconds = time.perf_counter() - started
        self.assertEqual(response.status_code, 200, response.content[:500])
        key = f"{label or path} [{shop.business.name}]"
        TIMINGS[key] = (seconds, len(queries))
        self.assertLess(seconds, SECONDS_ALLOWED, f"{key} took {seconds:.2f} s")
        return response, len(queries)

    def report(self, name, **params):
        return self.fetch(self.big, f"reports/{name}/", **{**PERIOD, **params})[0].json()

    # -- the figures at volume -----------------------------------------------------------
    def test_the_sales_figures_are_exact(self):
        b = self.big
        body = self.report("sales")
        net = round_money(b.sales_total) - round_money(b.refund_total)
        cost = round_money(b.sold_cost - b.returned_cost)
        self.assertEqual(body["sales_count"], b.sales)
        self.assertEqual(body["returns_count"], b.returns)
        self.assertEqual(body["revenue"], money(b.sales_total))
        self.assertEqual(body["refunds"], money(b.refund_total))
        self.assertEqual(body["net_sales"], str(net))
        self.assertEqual(body["cost_of_goods"], str(cost))
        self.assertEqual(body["gross_profit"], str(net - cost))
        self.assertEqual(sum(p["count"] for p in body["by_payment"]), b.sales)
        self.assertEqual(sum(d["count"] for d in body["by_day"]), b.sales)
        self.assertEqual(sum(D(d["revenue"]) for d in body["by_day"]), round_money(b.sales_total))
        self.assertEqual(sum(D(d["refunds"]) for d in body["by_day"]), round_money(b.refund_total))
        days = [d["date"] for d in body["by_day"]]
        self.assertEqual(days, sorted(days))
        self.assertEqual(len(days), 90)  # 220 sales a day: no day is empty
        self.assertEqual(len(body["top_products"]), 10)
        revenues = [D(p["revenue"]) for p in body["top_products"]]
        self.assertEqual(revenues, sorted(revenues, reverse=True))

    def test_the_other_reports(self):
        b = self.big
        summary = self.report("summary")
        self.assertEqual(summary["expenses"], money(b.expense_total))
        self.assertEqual(
            summary["result"], money(D(summary["gross_profit"]) - round_money(b.expense_total))
        )
        spent = self.report("expenses")
        self.assertEqual(spent["total"], money(b.expense_total))
        self.assertEqual(spent["count"], b.expense_count)
        self.assertEqual(sum(c["count"] for c in spent["by_category"]), b.expense_count)
        self.assertEqual(sum(D(c["total"]) for c in spent["by_category"]), D(spent["total"]))
        returns = self.report("returns")
        self.assertEqual(returns["returns_count"], b.returns)
        self.assertEqual(returns["refund_total"], money(b.refund_total))
        self.assertEqual(len(returns["by_reason"]), 10)
        self.assertEqual(returns["supplier_returns"]["count"], b.supplier_returns)
        stock = self.report("stock")
        self.assertEqual(len(stock["movements"]), len(MovementType.values))  # every type is there
        self.assertEqual(sum(m["count"] for m in stock["movements"]), 6000)
        self.assertGreater(stock["low_stock_count"], 0)
        self.assertLessEqual(len(stock["low_stock"]), 200)
        self.assertEqual(
            D(stock["value"]["total"]), sum(D(p["total"]) for p in stock["value"]["by_location"])
        )
        buying = self.report("purchasing")
        self.assertEqual(buying["orders_count"], b.orders)
        self.assertEqual(buying["deliveries_count"], b.deliveries)
        self.assertEqual(buying["supplier_returns_count"], b.supplier_returns)
        self.assertEqual(
            D(buying["received_value"]), sum(D(s["received_value"]) for s in buying["by_supplier"])
        )

    def test_one_location_and_the_exports(self):
        self.report("sales", location=self.big.stores[0].pk)
        for slug in EXPORTS:
            response, _ = self.fetch(
                self.big, f"reports/{slug}/export/", label=f"reports/{slug}/export/", **PERIOD
            )
            self.assertTrue(response.content.startswith(b"\xef\xbb\xbf"))
        sales_rows = self.fetch(
            self.big, "reports/sales/export/", label="reports/sales/export/", **PERIOD
        )[0].content.decode("utf-8-sig")
        self.assertEqual(len(sales_rows.splitlines()), 1 + 90)

    def test_the_dashboards(self):
        with at("2026-09-28", "20:00"):
            owner, _ = self.fetch(self.big, "dashboard/")
            seller, _ = self.fetch(
                self.big, "dashboard/", user=self.big.seller, label="dashboard/ seller"
            )
            keeper, _ = self.fetch(
                self.big, "dashboard/", user=self.big.keeper, label="dashboard/ keeper"
            )
        body = owner.json()
        self.assertEqual(len(body["recent_activity"]), 10)
        self.assertGreater(body["sales_month"]["count"], body["sales_today"]["count"])
        self.assertGreaterEqual(body["reorder_count"], 0)  # open orders cover most of the levels
        self.assertLessEqual(seller.json()["sales_month"]["count"], body["sales_month"]["count"])
        self.assertEqual(
            set(keeper.json()), {"generated_at", "low_stock_count", "open_orders_count"}
        )

    def test_the_activity_history(self):
        b = self.big
        first, _ = self.fetch(b, "audit/", limit=100)
        body = first.json()
        self.assertEqual((body["count"], len(body["results"])), (b.events, 100))
        deep, _ = self.fetch(b, "audit/", label="audit/ deep page", limit=100, offset=19900)
        self.assertEqual(len(deep.json()["results"]), 100)
        self.assertIsNone(deep.json()["next"])
        by_prefix = self.fetch(b, "audit/", label="audit/ action prefix", action="sale", limit=100)[
            0
        ]
        self.assertTrue(all(e["action"].startswith("sale.") for e in by_prefix.json()["results"]))
        exact = self.fetch(
            b, "audit/", label="audit/ exact action", action="sale.created", limit=100
        )[0]
        self.assertTrue(all(e["action"] == "sale.created" for e in exact.json()["results"]))
        self.fetch(b, "audit/", label="audit/ text", q="3f", limit=100)
        self.fetch(
            b,
            "audit/",
            label="audit/ actor and days",
            actor=b.seller.pk,
            date_from="2026-08-01",
            date_to="2026-08-31",
            limit=100,
        )
        actions = self.fetch(b, "audit/actions/")[0].json()["actions"]
        self.assertEqual(actions, sorted(actions))
        self.assertEqual(len(actions), 49)

    # -- a fixed number of queries ------------------------------------------------------------
    def test_the_number_of_queries_does_not_grow_with_the_data(self):
        for path, limit in QUERY_LIMITS.items():
            params = PERIOD if path.startswith("reports/") else {}
            with self.subTest(path=path), at("2026-09-28", "20:00"):
                _, big = self.fetch(self.big, path, label=f"count {path}", **params)
                _, tiny = self.fetch(self.tiny, path, label=f"count {path}", **params)
                self.assertEqual(big, tiny, f"{path}: {big} queries for much data, {tiny} for few")
                self.assertLessEqual(big, limit)
