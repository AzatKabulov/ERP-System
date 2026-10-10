"""Every number in every report, checked against values worked out by hand from the story in
`support.py` (see there for the prices, quantities and costs)."""

from decimal import Decimal
from unittest import mock

from apps.businesses.models import Business, Role
from apps.businesses.permissions import MATRIX
from apps.common.testing import client_for, make_business, make_member
from apps.inventory.tests.support import make_product
from apps.purchasing import services as purchasing
from apps.reports import returns as returns_report
from apps.reports import stock as stock_report
from apps.reports.tests.support import PERIOD, WHOLE, ReportsCase, at
from apps.sales import services as sales

D = Decimal


class SalesReportTests(ReportsCase):
    def product(self, product, **extra):
        return {
            "product": str(product.pk),
            "sku": product.sku,
            "name": product.name,
            "unit_symbol": product.unit.symbol,
            "unit_decimals": product.unit.decimal_places,
            **extra,
        }

    def test_every_figure_of_the_whole_period(self):
        # revenue 362.50 + 180.00 + 665.00 + 110.00; refunds 112.50 + 190.00 + 95.00;
        # cost of the sales 170 + 100 + 370 + 55 = 695.00 less 54 + 100 + 50 = 204.00 returned
        self.assertEqual(
            self.ok("reports/sales/", **WHOLE),
            {
                "period": PERIOD,
                "location": None,
                "sales_count": 4,
                "revenue": "1317.50",
                "refunds": "397.50",
                "returns_count": 3,
                "net_sales": "920.00",
                "cost_of_goods": "491.00",
                "gross_profit": "429.00",
                "by_payment": [
                    {"method": "cash", "count": 2, "total": "472.50"},
                    {"method": "card", "count": 2, "total": "845.00"},
                ],
                "by_day": [
                    {"date": "2026-10-01", "count": 2, "revenue": "542.50", "refunds": "0.00"},
                    {"date": "2026-10-02", "count": 1, "revenue": "665.00", "refunds": "112.50"},
                    {"date": "2026-10-03", "count": 1, "revenue": "110.00", "refunds": "285.00"},
                ],
                "top_products": [
                    self.product(self.w.pad, quantity="13.000", revenue="1255.00"),
                    self.product(self.w.oil, quantity="2.500", revenue="62.50"),
                ],
            },
        )

    def test_one_location_at_a_time(self):
        store = self.ok("reports/sales/", location=self.w.store.pk, **WHOLE)
        self.assertEqual(store["location"], str(self.w.store.pk))
        self.assertEqual(
            {k: v for k, v in store.items() if k not in ("period", "location")},
            {
                "sales_count": 3,
                "revenue": "1207.50",
                "refunds": "397.50",  # every return went back to the store
                "returns_count": 3,
                "net_sales": "810.00",
                "cost_of_goods": "436.00",
                "gross_profit": "374.00",
                "by_payment": [
                    {"method": "cash", "count": 1, "total": "362.50"},
                    {"method": "card", "count": 2, "total": "845.00"},
                ],
                "by_day": [
                    {"date": "2026-10-01", "count": 2, "revenue": "542.50", "refunds": "0.00"},
                    {"date": "2026-10-02", "count": 1, "revenue": "665.00", "refunds": "112.50"},
                    {"date": "2026-10-03", "count": 0, "revenue": "0.00", "refunds": "285.00"},
                ],
                "top_products": [
                    self.product(self.w.pad, quantity="12.000", revenue="1145.00"),
                    self.product(self.w.oil, quantity="2.500", revenue="62.50"),
                ],
            },
        )
        warehouse = self.ok("reports/sales/", location=self.w.warehouse.pk, **WHOLE)
        self.assertEqual(
            {k: v for k, v in warehouse.items() if k not in ("period", "location")},
            {
                "sales_count": 1,
                "revenue": "110.00",
                "refunds": "0.00",
                "returns_count": 0,
                "net_sales": "110.00",
                "cost_of_goods": "55.00",
                "gross_profit": "55.00",
                "by_payment": [{"method": "cash", "count": 1, "total": "110.00"}],
                "by_day": [
                    {"date": "2026-10-03", "count": 1, "revenue": "110.00", "refunds": "0.00"}
                ],
                "top_products": [self.product(self.w.pad, quantity="1.000", revenue="110.00")],
            },
        )

    def test_a_sale_at_2330_and_one_at_0030_belong_to_different_days(self):
        first = self.ok("reports/sales/", date_from="2026-10-01", date_to="2026-10-01")
        self.assertEqual((first["sales_count"], first["revenue"]), (2, "542.50"))  # S1 and S2
        self.assertEqual(first["returns_count"], 0)
        second = self.ok("reports/sales/", date_from="2026-10-02", date_to="2026-10-02")
        self.assertEqual((second["sales_count"], second["revenue"]), (1, "665.00"))  # S3
        # the cost of the day's sale less what came back that day: 370.00 - 54.00
        self.assertEqual(
            (second["refunds"], second["cost_of_goods"], second["gross_profit"]),
            ("112.50", "316.00", "236.50"),
        )

    def test_the_business_time_zone_decides_the_day_not_utc(self):
        # In UTC the 00:30 sale (19:30 UTC on 1 October) is still on the first day.
        Business.objects.filter(pk=self.w.a.pk).update(timezone="UTC")
        first = self.ok("reports/sales/", date_from="2026-10-01", date_to="2026-10-01")
        self.assertEqual((first["sales_count"], first["revenue"]), (3, "1207.50"))
        second = self.ok("reports/sales/", date_from="2026-10-02", date_to="2026-10-02")
        self.assertEqual((second["sales_count"], second["refunds"]), (0, "112.50"))

    def test_a_return_counts_on_its_own_day_whenever_the_sale_was(self):
        # R2 and R3 returned goods of S3 (sold on 2 October) on 3 October
        third = self.ok("reports/sales/", date_from="2026-10-03", date_to="2026-10-03")
        self.assertEqual((third["refunds"], third["returns_count"]), ("285.00", 2))
        self.assertEqual((third["sales_count"], third["revenue"]), (1, "110.00"))  # only S4
        self.assertEqual(third["net_sales"], "-175.00")  # more went back than was sold that day
        # cost: S4 55.00 less the 100.00 + 50.00 that came back
        self.assertEqual((third["cost_of_goods"], third["gross_profit"]), ("-95.00", "-80.00"))

    def test_the_default_period_is_the_month_so_far(self):
        with at("2026-10-03", "20:00"):
            body = self.ok("reports/sales/")
        self.assertEqual(body["period"], PERIOD)
        self.assertEqual((body["sales_count"], body["revenue"]), (4, "1317.50"))

    def test_only_date_to_starts_that_months_first_day(self):
        with at("2026-10-03", "20:00"):
            earlier = self.ok("reports/sales/", date_to="2026-09-15")
            from_only = self.ok("reports/sales/", date_from="2026-10-02")
        self.assertEqual(earlier["period"], {"from": "2026-09-01", "to": "2026-09-15"})
        self.assertEqual(earlier["sales_count"], 0)
        self.assertEqual(from_only["period"], {"from": "2026-10-02", "to": "2026-10-03"})
        self.assertEqual(from_only["sales_count"], 2)  # S3 and S4

    def test_nothing_in_the_period_gives_zeros_and_empty_lists(self):
        body = self.ok("reports/sales/", date_from="2026-08-01", date_to="2026-08-31")
        self.assertEqual(
            {k: v for k, v in body.items() if k not in ("period", "location")},
            {
                "sales_count": 0,
                "revenue": "0.00",
                "refunds": "0.00",
                "returns_count": 0,
                "net_sales": "0.00",
                "cost_of_goods": "0.00",
                "gross_profit": "0.00",
                "by_payment": [],
                "by_day": [],
                "top_products": [],
            },
        )

    def test_cost_and_profit_are_left_out_without_the_cost_right(self):
        with mock.patch.dict(MATRIX, {"sales.cost.view": frozenset({Role.OWNER})}):
            body = self.ok("reports/sales/", client=self.manager, **WHOLE)
        self.assertNotIn("cost_of_goods", body)
        self.assertNotIn("gross_profit", body)
        self.assertEqual((body["revenue"], body["net_sales"]), ("1317.50", "920.00"))

    def test_top_products_are_the_ten_biggest_by_revenue(self):
        with at("2026-10-03", "17:00"):
            for number in range(1, 12):  # eleven more products, 1..11 pieces at 1.00 each
                product = make_product(self.w.a, f"X-{number}", f"Extra {number:02d}", self.w.unit)
                self.w.stock(product, self.w.store, 20, "0.50")
                self.sell_one(product, number)
        body = self.ok("reports/sales/", **WHOLE)
        names = [p["name"] for p in body["top_products"]]
        self.assertEqual(len(names), 10)
        # 1255.00, 62.50, then 11.00, 10.00 ... 4.00; Extra 03 and below (3.00 ...) do not fit
        self.assertEqual(names[:3], ["Brake pad", "Engine oil", "Extra 11"])
        self.assertEqual(names[-1], "Extra 04")
        self.assertNotIn("Extra 03", names)

    # -- helpers ------------------------------------------------------------------------
    def sell_one(self, product, quantity):
        return sales.complete_sale(
            self.w.a,
            self.s.owner,
            {
                "location": self.w.store,
                "lines": [{"product": product, "quantity": D(quantity), "unit_price": D("1.00")}],
                "payment_method": "cash",
            },
        )


class SummaryTests(ReportsCase):
    def test_every_figure_of_the_whole_period(self):
        self.assertEqual(
            self.ok("reports/summary/", **WHOLE),
            {
                "period": PERIOD,
                "location": None,
                "revenue": "1317.50",
                "refunds": "397.50",
                "net_sales": "920.00",
                "sales_count": 4,
                "returns_count": 3,
                "cost_of_goods": "491.00",
                "gross_profit": "429.00",
                "expenses": "245.50",  # E2 45.50 + E3 200.00 (E1 is September, E4 is void)
                "result": "183.50",  # 429.00 - 245.50
                "inventory_value": "1594.00",
                "low_stock_count": 3,
                "open_orders_count": 2,
            },
        )

    def test_the_store_and_the_warehouse_on_their_own(self):
        store = self.ok("reports/summary/", location=self.w.store.pk, **WHOLE)
        self.assertEqual(
            {k: v for k, v in store.items() if k not in ("period", "location")},
            {
                "revenue": "1207.50",
                "refunds": "397.50",
                "net_sales": "810.00",
                "sales_count": 3,
                "returns_count": 3,
                "cost_of_goods": "436.00",
                "gross_profit": "374.00",
                "expenses": "45.50",
                "result": "328.50",
                "inventory_value": "779.00",
                "low_stock_count": 2,
                "open_orders_count": 0,  # PO-0 arrived, PO-3 is only a draft
            },
        )
        warehouse = self.ok("reports/summary/", location=self.w.warehouse.pk, **WHOLE)
        self.assertEqual(
            {k: v for k, v in warehouse.items() if k not in ("period", "location")},
            {
                "revenue": "110.00",
                "refunds": "0.00",
                "net_sales": "110.00",
                "sales_count": 1,
                "returns_count": 0,
                "cost_of_goods": "55.00",
                "gross_profit": "55.00",
                "expenses": "200.00",
                "result": "-145.00",  # an operating loss: the rent is bigger than the margin
                "inventory_value": "815.00",
                "low_stock_count": 1,
                "open_orders_count": 2,
            },
        )

    def test_the_snapshots_do_not_depend_on_the_period(self):
        body = self.ok("reports/summary/", date_from="2026-09-30", date_to="2026-09-30")
        self.assertEqual((body["revenue"], body["expenses"]), ("0.00", "1000.00"))
        self.assertEqual(body["result"], "-1000.00")
        self.assertEqual(
            (body["inventory_value"], body["low_stock_count"], body["open_orders_count"]),
            ("1594.00", 3, 2),
        )

    def test_keys_the_caller_may_not_see_are_left_out(self):
        cases = {
            "sales.cost.view": {"cost_of_goods", "gross_profit", "result"},
            "expense.view": {"expenses", "result"},
            "stock.cost.view": {"inventory_value"},
        }
        for code, missing in cases.items():
            with self.subTest(code=code):
                with mock.patch.dict(MATRIX, {code: frozenset({Role.OWNER})}):
                    body = self.ok("reports/summary/", client=self.manager, **WHOLE)
                full = self.ok("reports/summary/", **WHOLE)
                self.assertEqual(set(full) - set(body), missing)
                self.assertEqual({k: body[k] for k in body}, {k: full[k] for k in body})

    def test_a_loss_is_written_with_a_minus_sign(self):
        body = self.ok("reports/summary/", date_from="2026-10-03", date_to="2026-10-03")
        # 3 October: gross profit 110 - 285 - (-95) = -80.00, no expenses that day
        self.assertEqual((body["gross_profit"], body["expenses"]), ("-80.00", "0.00"))
        self.assertEqual(body["result"], "-80.00")


class StockReportTests(ReportsCase):
    def low(self, product, location, on_hand, minimum, target):
        return {
            "product": {
                "id": str(product.pk),
                "sku": product.sku,
                "name": product.name,
                "unit_symbol": product.unit.symbol,
                "unit_decimals": product.unit.decimal_places,
            },
            "location": self.place(location),
            "on_hand": on_hand,
            "minimum": minimum,
            "target": target,
        }

    def test_every_figure(self):
        self.assertEqual(
            self.ok("reports/stock/", **WHOLE),
            {
                "period": PERIOD,
                "location": None,
                # sorted by place, then product; the archived product, the oil at its minimum
                # (28 = 28) and business B's setting are not listed
                "low_stock": [
                    self.low(self.w.pad, self.w.store, "7.000", "10.000", "30.000"),
                    self.low(self.s.spark, self.w.store, "0.000", "4.000", "10.000"),
                    self.low(self.w.oil, self.w.warehouse, "20.000", "30.000", "50.000"),
                ],
                "low_stock_count": 3,
                "value": {
                    "total": "1594.00",
                    "by_location": [
                        {
                            "location": self.place(self.w.store),
                            "total": "779.00",
                            "by_condition": {
                                # pad 6 @ 60 + 1 @ 50; oil 18 @ 8 + 10 @ 7.50
                                "sellable": "629.00",
                                "damaged": "100.00",  # pad 2 @ 50
                                "inspection": "50.00",  # pad 1 @ 50
                                "in_transit": "0.00",
                            },
                        },
                        {
                            "location": self.place(self.w.warehouse),
                            "total": "815.00",
                            "by_condition": {
                                "sellable": "815.00",  # pad 1 @ 55 + 10 @ 60; oil 20 @ 8
                                "damaged": "0.00",
                                "inspection": "0.00",
                                "in_transit": "0.00",
                            },
                        },
                    ],
                },
                "movements": [
                    {
                        "type": "receipt",
                        "count": 4,
                        "quantity_in": "38.000",
                        "quantity_out": "0.000",
                    },
                    {"type": "sale", "count": 6, "quantity_in": "0.000", "quantity_out": "15.500"},
                    {
                        "type": "transfer_out",
                        "count": 2,
                        "quantity_in": "0.000",
                        "quantity_out": "4.000",
                    },
                    {
                        "type": "transfer_in",
                        "count": 2,
                        "quantity_in": "4.000",
                        "quantity_out": "0.000",
                    },
                    {
                        "type": "return_in",
                        "count": 4,
                        "quantity_in": "4.500",
                        "quantity_out": "0.000",
                    },
                    {
                        "type": "supplier_return",
                        "count": 1,
                        "quantity_in": "0.000",
                        "quantity_out": "2.000",
                    },
                ],
            },
        )

    def test_one_location_at_a_time(self):
        store = self.ok("reports/stock/", location=self.w.store.pk, **WHOLE)
        self.assertEqual(store["low_stock_count"], 2)
        self.assertEqual([r["product"]["sku"] for r in store["low_stock"]], ["BP-1", "SP-1"])
        self.assertEqual(store["value"]["total"], "779.00")
        self.assertEqual(
            [p["location"]["name"] for p in store["value"]["by_location"]], ["A Store"]
        )
        self.assertEqual(
            [(m["type"], m["count"]) for m in store["movements"]],
            [("receipt", 1), ("sale", 5), ("transfer_out", 1), ("return_in", 4)],
        )
        warehouse = self.ok("reports/stock/", location=self.w.warehouse.pk, **WHOLE)
        self.assertEqual(warehouse["low_stock_count"], 1)
        self.assertEqual(warehouse["value"]["total"], "815.00")
        self.assertEqual(
            [(m["type"], m["count"]) for m in warehouse["movements"]],
            [
                ("receipt", 3),
                ("sale", 1),
                ("transfer_out", 1),
                ("transfer_in", 2),
                ("supplier_return", 1),
            ],
        )

    def test_movements_follow_the_period_but_low_stock_and_value_are_of_now(self):
        first_day = self.ok("reports/stock/", date_from="2026-10-01", date_to="2026-10-01")
        self.assertEqual(
            first_day["movements"],
            [{"type": "sale", "count": 3, "quantity_in": "0.000", "quantity_out": "7.500"}],
        )
        before = self.ok("reports/stock/", date_from="2026-09-30", date_to="2026-09-30")
        self.assertEqual(
            before["movements"],
            [
                {
                    "type": "adjustment_in",
                    "count": 4,
                    "quantity_in": "44.000",
                    "quantity_out": "0.000",
                }
            ],
        )
        self.assertEqual(before["value"]["total"], "1594.00")
        self.assertEqual(before["low_stock_count"], 3)

    def test_value_is_rounded_half_up_per_place_and_condition(self):
        with at("2026-10-03", "17:00"):  # 0.5 @ 0.45 = 0.225 on top of the store's 629.00
            self.w.stock(self.w.oil, self.w.store, "0.5", "0.45")
        body = self.ok("reports/stock/", **WHOLE)
        store = body["value"]["by_location"][0]
        self.assertEqual(store["by_condition"]["sellable"], "629.23")
        self.assertEqual((store["total"], body["value"]["total"]), ("779.23", "1594.23"))

    def test_the_list_is_capped_but_the_count_is_not(self):
        self.assertEqual(stock_report.LOW_STOCK_ROWS, 200)
        with mock.patch.object(stock_report, "LOW_STOCK_ROWS", 2):
            body = self.ok("reports/stock/", **WHOLE)
        self.assertEqual(len(body["low_stock"]), 2)
        self.assertEqual(body["low_stock_count"], 3)

    def test_value_is_left_out_without_the_stock_cost_right(self):
        with mock.patch.dict(MATRIX, {"stock.cost.view": frozenset({Role.OWNER})}):
            body = self.ok("reports/stock/", client=self.manager, **WHOLE)
        self.assertNotIn("value", body)
        self.assertEqual(body["low_stock_count"], 3)

    def test_an_empty_shelf_with_no_settings_gives_empty_lists(self):
        shop = make_business("Empty Shop", locations=("Only store",))
        owner = client_for(make_member(shop, Role.OWNER, username="empty-owner"))
        response = owner.get(f"/api/v1/businesses/{shop.pk}/reports/stock/")
        self.assertEqual(response.status_code, 200)
        body = response.json()
        self.assertEqual(
            {k: v for k, v in body.items() if k not in ("period", "location")},
            {
                "low_stock": [],
                "low_stock_count": 0,
                "value": {"total": "0.00", "by_location": []},
                "movements": [],
            },
        )


class PurchasingReportTests(ReportsCase):
    def test_every_figure(self):
        # Orders made on 1-3 October: PO-1 (placed), PO-2 (placed), PO-3 (a draft). Only placed
        # orders count towards the ordered total (760 + 135) and the supplier rows.
        self.assertEqual(
            self.ok("reports/purchasing/", **WHOLE),
            {
                "period": PERIOD,
                "location": None,
                "orders_count": 3,
                "by_status": [
                    {"status": "draft", "count": 1},
                    {"status": "ordered", "count": 1},
                    {"status": "partially_received", "count": 1},
                ],
                "deliveries_count": 3,
                "ordered_total": "895.00",
                "received_value": "715.00",  # 75 + (360 + 160) + 120
                "by_supplier": [
                    {
                        "supplier": self.place(self.s.ashgabat),
                        "orders": 1,
                        "received_value": "640.00",
                    },
                    {"supplier": self.place(self.s.tmt), "orders": 1, "received_value": "75.00"},
                ],
                "supplier_returns_count": 1,
                "supplier_returns_credit": "120.00",
            },
        )

    def test_orders_count_by_their_creation_and_deliveries_by_their_receipt(self):
        # PO-0 was ordered in September but its goods came on 2 October
        body = self.ok("reports/purchasing/", date_from="2026-10-02", date_to="2026-10-02")
        self.assertEqual((body["orders_count"], body["by_status"]), (0, []))
        self.assertEqual((body["deliveries_count"], body["received_value"]), (2, "595.00"))
        self.assertEqual(
            [
                (r["supplier"]["name"], r["orders"], r["received_value"])
                for r in body["by_supplier"]
            ],
            [("Ashgabat Parts", 0, "520.00"), ("Türkmen Täze", 0, "75.00")],
        )
        september = self.ok("reports/purchasing/", date_from="2026-09-20", date_to="2026-09-20")
        self.assertEqual(september["orders_count"], 1)
        self.assertEqual(september["by_status"], [{"status": "received", "count": 1}])
        self.assertEqual(september["ordered_total"], "75.00")
        self.assertEqual(september["deliveries_count"], 0)

    def test_the_warehouse_and_the_store_on_their_own(self):
        warehouse = self.ok("reports/purchasing/", location=self.w.warehouse.pk, **WHOLE)
        self.assertEqual(
            {k: v for k, v in warehouse.items() if k not in ("period", "location")},
            {
                "orders_count": 2,
                "by_status": [
                    {"status": "ordered", "count": 1},
                    {"status": "partially_received", "count": 1},
                ],
                "deliveries_count": 2,
                "ordered_total": "895.00",
                "received_value": "640.00",
                "by_supplier": [
                    {
                        "supplier": self.place(self.s.ashgabat),
                        "orders": 1,
                        "received_value": "640.00",
                    },
                    {"supplier": self.place(self.s.tmt), "orders": 1, "received_value": "0.00"},
                ],
                "supplier_returns_count": 1,
                "supplier_returns_credit": "120.00",
            },
        )
        store = self.ok("reports/purchasing/", location=self.w.store.pk, **WHOLE)
        self.assertEqual(
            {k: v for k, v in store.items() if k not in ("period", "location")},
            {
                "orders_count": 1,
                "by_status": [{"status": "draft", "count": 1}],
                "deliveries_count": 1,
                "ordered_total": "0.00",  # the only order is a draft
                "received_value": "75.00",
                "by_supplier": [
                    {"supplier": self.place(self.s.tmt), "orders": 0, "received_value": "75.00"}
                ],
                "supplier_returns_count": 0,
                "supplier_returns_credit": "0.00",
            },
        )

    def test_draft_and_cancelled_orders_are_not_placed_orders(self):
        with at("2026-10-03", "18:00"):
            purchasing.cancel_order(self.w.a, self.s.owner, self.s.po3.pk, "Not needed")
            purchasing.cancel_order(self.w.a, self.s.owner, self.s.po1.pk, "Supplier closed")
        body = self.ok("reports/purchasing/", **WHOLE)
        self.assertEqual(body["orders_count"], 3)  # the split still shows every order
        self.assertEqual(
            body["by_status"],
            [{"status": "ordered", "count": 1}, {"status": "cancelled", "count": 2}],
        )
        self.assertEqual(body["ordered_total"], "135.00")  # PO-2 only
        self.assertEqual(
            body["by_supplier"],
            [{"supplier": self.place(self.s.tmt), "orders": 1, "received_value": "75.00"}],
        )
        # what PO-1 delivered before it was cancelled did arrive, so the total keeps it
        self.assertEqual((body["deliveries_count"], body["received_value"]), (3, "715.00"))

    def test_amounts_are_left_out_without_the_purchasing_cost_right(self):
        with mock.patch.dict(MATRIX, {"purchasing.cost.view": frozenset({Role.OWNER})}):
            body = self.ok("reports/purchasing/", client=self.manager, **WHOLE)
        self.assertEqual(
            body,
            {
                "period": PERIOD,
                "location": None,
                "orders_count": 3,
                "by_status": [
                    {"status": "draft", "count": 1},
                    {"status": "ordered", "count": 1},
                    {"status": "partially_received", "count": 1},
                ],
                "deliveries_count": 3,
                "by_supplier": [
                    {"supplier": self.place(self.s.ashgabat), "orders": 1},
                    {"supplier": self.place(self.s.tmt), "orders": 1},
                ],
                "supplier_returns_count": 1,
            },
        )


class ReturnsReportTests(ReportsCase):
    def test_every_figure(self):
        self.assertEqual(
            self.ok("reports/returns/", **WHOLE),
            {
                "period": PERIOD,
                "location": None,
                "returns_count": 3,
                "refund_total": "397.50",
                "by_condition": [
                    {"condition": "sellable", "quantity": "1.500", "refund": "112.50"},
                    {"condition": "damaged", "quantity": "2.000", "refund": "190.00"},
                    {"condition": "inspection", "quantity": "1.000", "refund": "95.00"},
                ],
                "by_reason": [
                    {"reason": "Wrong size", "count": 2, "refund": "207.50"},
                    {"reason": "Defective", "count": 1, "refund": "190.00"},
                ],
                "supplier_returns": {"count": 1, "credit": "120.00"},
            },
        )

    def test_the_store_has_the_returns_and_the_warehouse_the_supplier_return(self):
        store = self.ok("reports/returns/", location=self.w.store.pk, **WHOLE)
        self.assertEqual(store["returns_count"], 3)
        self.assertEqual(store["supplier_returns"], {"count": 0, "credit": "0.00"})
        warehouse = self.ok("reports/returns/", location=self.w.warehouse.pk, **WHOLE)
        self.assertEqual(
            {k: v for k, v in warehouse.items() if k not in ("period", "location")},
            {
                "returns_count": 0,
                "refund_total": "0.00",
                "by_condition": [],
                "by_reason": [],
                "supplier_returns": {"count": 1, "credit": "120.00"},
            },
        )

    def test_returns_count_on_their_own_day(self):
        body = self.ok("reports/returns/", date_from="2026-10-02", date_to="2026-10-02")
        self.assertEqual((body["returns_count"], body["refund_total"]), (1, "112.50"))  # R1
        self.assertEqual(body["supplier_returns"]["count"], 0)

    def test_only_the_ten_biggest_reasons_are_listed(self):
        self.assertEqual(returns_report.TOP_REASONS, 10)
        with mock.patch.object(returns_report, "TOP_REASONS", 1):
            body = self.ok("reports/returns/", **WHOLE)
        self.assertEqual([r["reason"] for r in body["by_reason"]], ["Wrong size"])
        self.assertEqual(body["returns_count"], 3)

    def test_the_supplier_credit_is_left_out_without_the_purchasing_cost_right(self):
        with mock.patch.dict(MATRIX, {"purchasing.cost.view": frozenset({Role.OWNER})}):
            body = self.ok("reports/returns/", client=self.manager, **WHOLE)
        self.assertEqual(body["supplier_returns"], {"count": 1})


class ExpensesReportTests(ReportsCase):
    def test_every_figure(self):
        self.assertEqual(
            self.ok("reports/expenses/", **WHOLE),
            {
                "period": PERIOD,
                "location": None,
                "total": "245.50",
                "count": 2,
                "by_category": [
                    {"category": self.place(self.s.rent), "total": "200.00", "count": 1},
                    {"category": self.place(self.s.transport), "total": "45.50", "count": 1},
                ],
                "by_location": [
                    {"location": self.place(self.w.warehouse), "total": "200.00", "count": 1},
                    {"location": self.place(self.w.store), "total": "45.50", "count": 1},
                ],
            },
        )

    def test_voided_expenses_and_other_periods_are_not_counted(self):
        september = self.ok("reports/expenses/", date_from="2026-09-30", date_to="2026-09-30")
        self.assertEqual((september["total"], september["count"]), ("1000.00", 1))
        second = self.ok("reports/expenses/", date_from="2026-10-02", date_to="2026-10-02")
        self.assertEqual((second["total"], second["count"]), ("200.00", 1))  # E4 is void

    def test_one_location(self):
        store = self.ok("reports/expenses/", location=self.w.store.pk, **WHOLE)
        self.assertEqual((store["total"], store["count"]), ("45.50", 1))
        self.assertEqual(
            store["by_category"],
            [{"category": self.place(self.s.transport), "total": "45.50", "count": 1}],
        )
        self.assertEqual(len(store["by_location"]), 1)

    def test_an_empty_period(self):
        body = self.ok("reports/expenses/", date_from="2026-08-01", date_to="2026-08-31")
        self.assertEqual(
            (body["total"], body["count"], body["by_category"], body["by_location"]),
            ("0.00", 0, [], []),
        )

    def test_it_needs_the_expense_right_not_the_report_right(self):
        with mock.patch.dict(MATRIX, {"report.view": frozenset({Role.OWNER})}):
            self.assertEqual(self.get(self.manager, "reports/sales/").status_code, 403)
            self.assertEqual(self.get(self.manager, "reports/expenses/").status_code, 200)
        with mock.patch.dict(MATRIX, {"expense.view": frozenset({Role.OWNER})}):
            self.assertEqual(self.get(self.manager, "reports/expenses/").status_code, 403)
            self.assertEqual(self.get(self.manager, "reports/sales/").status_code, 200)
