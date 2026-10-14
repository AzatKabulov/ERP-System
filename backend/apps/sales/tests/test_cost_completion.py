"""Goods received without a cost: the flag, honest profit, and entering the cost afterwards."""

import uuid
from datetime import timedelta
from decimal import Decimal
from zoneinfo import ZoneInfo

from django.utils import timezone

from apps.audit.models import AuditEvent
from apps.businesses.models import Role
from apps.catalog.models import Product
from apps.common.testing import APITestCase
from apps.inventory.models import CostLayer
from apps.inventory.tests.support import World, ledger_differences, make_product
from apps.sales.models import CostCorrection, SaleLine, SaleReturnLine
from apps.stockops import services as stockops

D = Decimal


class CostCase(APITestCase):
    def setUp(self):
        super().setUp()
        self.w = World()
        self.owner = self.w.api[Role.OWNER]
        self.keeper = self.w.api[Role.WAREHOUSE]
        self.seller = self.w.api[Role.SALES]
        self.manager = self.w.api[Role.MANAGER]
        self.store = self.w.store
        self.warehouse = self.w.warehouse

    def tearDown(self):
        self.assertEqual(ledger_differences(), [])
        super().tearDown()

    # -- helpers ------------------------------------------------------------------------
    def intake(self, product, quantity, cost=None, *, location=None, client=None):
        line = {"product": str(product.pk), "quantity": str(quantity)}
        if cost is not None:
            line["unit_cost"] = str(cost)
        response = (client or (self.owner if cost is not None else self.keeper)).post(
            f"{self.w.base}/intakes/",
            {"location": str((location or self.warehouse).pk), "lines": [line]},
            format="json",
            HTTP_IDEMPOTENCY_KEY=str(uuid.uuid4()),
        )
        self.assertEqual(response.status_code, 201, response.content)
        return response.json()

    def sell(self, product, quantity, price="100.00", *, location=None, client=None):
        response = (client or self.owner).post(
            f"{self.w.base}/sales/",
            {
                "location": str((location or self.warehouse).pk),
                "lines": [
                    {"product": str(product.pk), "quantity": str(quantity), "unit_price": price}
                ],
            },
            format="json",
            HTTP_IDEMPOTENCY_KEY=str(uuid.uuid4()),
        )
        self.assertEqual(response.status_code, 201, response.content)
        return response.json()

    def give_back(self, sale, quantity=1, condition="sellable"):
        response = self.owner.post(
            f"{self.w.base}/sales/{sale['id']}/returns/",
            {
                "reason": "Did not fit",
                "lines": [
                    {
                        "sale_line": sale["lines"][0]["id"],
                        "quantity": str(quantity),
                        "condition": condition,
                    }
                ],
            },
            format="json",
            HTTP_IDEMPOTENCY_KEY=str(uuid.uuid4()),
        )
        self.assertEqual(response.status_code, 201, response.content)
        return response.json()

    def set_cost(self, product, cost, *, client=None):
        return (client or self.owner).post(
            f"{self.w.base}/products/{product.pk}/cost/", {"unit_cost": str(cost)}, format="json"
        )

    def summary(self, client=None):
        today = timezone.now().astimezone(ZoneInfo(self.w.a.timezone)).date()
        response = (client or self.owner).get(
            f"{self.w.base}/reports/summary/",
            {"date_from": str(today - timedelta(days=1)), "date_to": str(today)},
        )
        self.assertEqual(response.status_code, 200, response.content)
        return response.json()

    def layers(self, product):
        return list(
            CostLayer.objects.filter(balance__product=product).order_by("created_at", "layer_no")
        )


class FlagTests(CostCase):
    def test_goods_received_without_any_cost_are_flagged_unknown(self):
        self.intake(self.w.pad, 5)
        (layer,) = self.layers(self.w.pad)
        self.assertEqual((layer.unit_cost, layer.cost_known), (D("0"), False))

    def test_a_typed_cost_or_a_default_cost_is_a_known_cost(self):
        self.intake(self.w.pad, 5, "40.00")
        self.w.oil.default_purchase_cost = D("8.00")
        self.w.oil.save()
        self.intake(self.w.oil, 3, location=self.warehouse, client=self.keeper)
        self.assertEqual([layer.cost_known for layer in self.layers(self.w.pad)], [True])
        (oil,) = self.layers(self.w.oil)
        self.assertEqual((oil.unit_cost, oil.cost_known), (D("8.00"), True))

    def test_a_sale_from_unknown_goods_is_flagged_and_one_from_known_goods_is_not(self):
        self.intake(self.w.pad, 5)
        self.intake(self.w.oil, 5, "8.00")
        self.sell(self.w.pad, 2)
        self.sell(self.w.oil, 2, "25.00")
        flags = {line.sku: line.cost_known for line in SaleLine.objects.all()}
        self.assertEqual(flags, {"BP-1": False, "OIL-1": True})

    def test_a_sale_that_touches_one_unknown_batch_is_unknown(self):
        self.intake(self.w.pad, 2, "50.00")
        self.intake(self.w.pad, 2)
        self.sell(self.w.pad, 3)
        self.assertFalse(SaleLine.objects.get().cost_known)

    def test_the_flag_follows_goods_that_are_transferred(self):
        self.intake(self.w.pad, 5)
        sent = self.keeper.post(
            f"{self.w.base}/transfers/",
            {
                "from_location": str(self.warehouse.pk),
                "to_location": str(self.store.pk),
                "lines": [{"product": str(self.w.pad.pk), "quantity": "3"}],
            },
            format="json",
            HTTP_IDEMPOTENCY_KEY=str(uuid.uuid4()),
        )
        self.assertEqual(sent.status_code, 201, sent.content)
        received = self.owner.post(
            f"{self.w.base}/transfers/{sent.json()['id']}/receive/",
            {},
            format="json",
            HTTP_IDEMPOTENCY_KEY=str(uuid.uuid4()),
        )
        self.assertEqual(received.status_code, 200, received.content)
        at_store = CostLayer.objects.filter(
            balance__product=self.w.pad, balance__location=self.store, quantity_remaining__gt=0
        )
        self.assertEqual([layer.cost_known for layer in at_store], [False])
        self.sell(self.w.pad, 1, location=self.store)
        self.assertFalse(SaleLine.objects.get().cost_known)

    def test_the_flag_follows_returned_goods_and_the_inspection_decision(self):
        self.intake(self.w.pad, 5)
        sale = self.sell(self.w.pad, 3)
        self.give_back(sale, 1, "sellable")
        self.give_back(sale, 1, "inspection")
        lines = list(SaleReturnLine.objects.order_by("sale_return__number"))
        self.assertEqual([line.cost_known for line in lines], [False, False])
        decided = self.owner.post(
            f"{self.w.base}/returns/{lines[1].sale_return_id}/inspections/",
            {"lines": [{"return_line": str(lines[1].pk), "quantity": "1", "outcome": "sellable"}]},
            format="json",
            HTTP_IDEMPOTENCY_KEY=str(uuid.uuid4()),
        )
        self.assertEqual(decided.status_code, 200, decided.content)
        waiting = CostLayer.objects.filter(
            balance__product=self.w.pad, balance__condition="sellable", quantity_remaining__gt=0
        )
        self.assertTrue(waiting)
        self.assertEqual({layer.cost_known for layer in waiting}, {False})

    def test_goods_found_in_a_count_take_the_flag_of_what_is_known_about_them(self):
        biz, here = self.w.a, self.warehouse
        # nothing known at all: zero, unknown
        self.assertEqual(stockops._surplus_cost(biz, self.w.pad, here), (D("0"), False))
        # an owner-set default cost is a known cost
        self.w.pad.default_purchase_cost = D("55.00")
        self.assertEqual(stockops._surplus_cost(biz, self.w.pad, here), (D("55.00"), True))
        # a latest layer passes on its own flag
        self.intake(self.w.pad, 2)
        self.assertEqual(stockops._surplus_cost(biz, self.w.pad, here), (D("0.00"), False))


class HonestProfitTests(CostCase):
    def test_profit_leaves_out_sales_whose_cost_is_not_known(self):
        self.intake(self.w.oil, 10, "8.00")
        self.intake(self.w.pad, 10)
        self.sell(self.w.oil, 5, "25.00")  # known: revenue 125.00, cost 40.00
        self.sell(self.w.pad, 2, "100.00")  # unknown: revenue 200.00
        s = self.summary()
        self.assertEqual((s["revenue"], s["net_sales"]), ("325.00", "325.00"))
        self.assertEqual(s["cost_of_goods"], "40.00")  # the placeholder is not counted
        self.assertEqual((s["without_cost"], s["without_cost_lines"]), ("200.00", 1))
        self.assertEqual(s["gross_profit"], "85.00")  # 125.00 - 40.00, not 325.00 - 40.00

    def test_a_sale_with_an_unknown_cost_shows_no_profit(self):
        self.intake(self.w.pad, 10)
        sale = self.sell(self.w.pad, 2)
        detail = self.owner.get(f"{self.w.base}/sales/{sale['id']}/").json()
        self.assertEqual((detail["cost_known"], detail["profit"]), (False, None))
        self.assertFalse(detail["lines"][0]["cost_known"])
        known = self.owner.get(f"{self.w.base}/sales/{self.sell_known()['id']}/").json()
        self.assertEqual((known["cost_known"], known["profit"]), (True, "60.00"))

    def sell_known(self):
        self.intake(self.w.oil, 5, "20.00")
        return self.sell(self.w.oil, 2, "50.00")

    def test_roles_without_cost_access_see_none_of_it(self):
        self.intake(self.w.pad, 10, location=self.store, client=self.owner)  # no cost typed
        sale = self.sell(self.w.pad, 2, location=self.store, client=self.seller)
        self.assertEqual(self.seller.get(f"{self.w.base}/reports/summary/").status_code, 403)
        data = self.seller.get(f"{self.w.base}/sales/{sale['id']}/").json()
        for gone in ("cost_total", "cost_known", "profit"):
            self.assertNotIn(gone, data)
        self.assertNotIn("cost_known", data["lines"][0])


class EnteringTheCostTests(CostCase):
    def story(self):
        """10 pads in without a cost; 4 sold at 100.00; 1 of them brought back."""
        self.intake(self.w.pad, 10)
        self.sale = self.sell(self.w.pad, 4)
        self.back = self.give_back(self.sale, 1)

    def test_the_cost_fixes_the_stock_the_sales_the_returns_and_the_profit(self):
        self.story()
        before = self.summary()
        self.assertEqual(before["without_cost"], "300.00")  # 400.00 sold - 100.00 refunded
        self.assertEqual(before["gross_profit"], "0.00")  # nothing can be said yet

        response = self.set_cost(self.w.pad, "60.00")
        self.assertEqual(response.status_code, 200, response.content)
        done = response.json()
        # the intake batch and the batch that came back; the one sale line; the one return line
        self.assertEqual((done["layers"], done["sale_lines"], done["return_lines"]), (2, 1, 1))
        self.assertEqual(
            {(x.unit_cost, x.cost_known) for x in self.layers(self.w.pad)}, {(D("60.00"), True)}
        )

        after = self.summary()
        self.assertEqual(after["without_cost"], "0.00")
        self.assertEqual(after["cost_of_goods"], "180.00")  # 4 x 60.00 sold, 1 x 60.00 back
        self.assertEqual(after["gross_profit"], "120.00")  # 300.00 net sales - 180.00
        detail = self.owner.get(f"{self.w.base}/sales/{self.sale['id']}/").json()
        self.assertEqual((detail["cost_total"], detail["profit"]), ("240.00", "160.00"))
        self.assertTrue(detail["lines"][0]["cost_known"])
        returned = self.owner.get(f"{self.w.base}/returns/{self.back['id']}/").json()
        self.assertEqual(returned["lines"][0]["cost_total"], "60.00")

        self.assertEqual(after["inventory_value"], "420.00")  # 7 pieces left at 60.00
        self.assertEqual(Product.objects.get(pk=self.w.pad.pk).default_purchase_cost, D("60.00"))

    def test_nothing_that_was_written_is_edited_the_corrections_say_what_changed(self):
        self.story()
        self.set_cost(self.w.pad, "60.00")
        sale_line = SaleLine.objects.get()
        self.assertEqual((sale_line.cost_total, sale_line.cost_known), (D("0"), False))
        corrections = {c.sale_line_id is not None: c for c in CostCorrection.objects.all()}
        self.assertEqual(corrections[True].delta, D("240.00000"))
        self.assertEqual(corrections[False].delta, D("60.00000"))
        self.assertEqual(AuditEvent.objects.filter(action="product.cost_set").count(), 1)
        with self.assertRaises(RuntimeError):
            corrections[True].save()  # append-only, as the ledger is

    def test_sales_and_returns_made_after_the_cost_are_right_without_any_correction(self):
        self.story()
        self.set_cost(self.w.pad, "60.00")
        again = self.give_back(self.sale, 1)  # more goods back from the old sale
        later = self.sell(self.w.pad, 1)
        line = SaleReturnLine.objects.get(sale_return_id=again["id"])
        self.assertEqual((line.cost_total, line.cost_known), (D("60.00000"), True))
        fresh = SaleLine.objects.get(sale_id=later["id"])
        self.assertEqual((fresh.cost_total, fresh.cost_known), (D("60.00000"), True))
        self.assertEqual(CostCorrection.objects.count(), 2)  # still only the first two

    def test_known_batches_are_not_touched_and_a_second_entry_changes_nothing(self):
        self.intake(self.w.pad, 2, "50.00")
        self.intake(self.w.pad, 3)
        self.sell(self.w.pad, 4)  # 2 at 50.00 (known) + 2 unknown
        done = self.set_cost(self.w.pad, "70.00").json()
        self.assertEqual((done["layers"], done["sale_lines"]), (1, 1))
        costs = [x.unit_cost for x in self.layers(self.w.pad)]
        self.assertEqual(costs, [D("50.00"), D("70.00")])
        line = SaleLine.objects.get()
        self.assertEqual(CostCorrection.objects.get().delta, D("140.00000"))  # only 2 x 70.00
        self.assertEqual(line.cost_total + CostCorrection.objects.get().delta, D("240.00000"))
        again = self.set_cost(self.w.pad, "99.00").json()
        self.assertEqual((again["layers"], again["sale_lines"], again["return_lines"]), (0, 0, 0))
        self.assertEqual([x.unit_cost for x in self.layers(self.w.pad)], [D("50.00"), D("70.00")])

    def test_goods_sent_to_another_place_are_priced_there_too(self):
        self.intake(self.w.pad, 5)
        sent = self.keeper.post(
            f"{self.w.base}/transfers/",
            {
                "from_location": str(self.warehouse.pk),
                "to_location": str(self.store.pk),
                "lines": [{"product": str(self.w.pad.pk), "quantity": "3"}],
            },
            format="json",
            HTTP_IDEMPOTENCY_KEY=str(uuid.uuid4()),
        )
        self.owner.post(
            f"{self.w.base}/transfers/{sent.json()['id']}/receive/",
            {},
            format="json",
            HTTP_IDEMPOTENCY_KEY=str(uuid.uuid4()),
        )
        done = self.set_cost(self.w.pad, "10.00").json()
        self.assertEqual(done["layers"], 3)  # the intake batch, its in-transit copy, the arrival
        self.assertEqual({x.cost_known for x in self.layers(self.w.pad)}, {True})
        self.sell(self.w.pad, 1, location=self.store)
        self.assertTrue(SaleLine.objects.get().cost_known)

    def test_a_zero_cost_is_allowed_and_counts_as_known(self):
        self.story()
        self.assertEqual(self.set_cost(self.w.pad, "0").status_code, 200)
        self.assertEqual(self.summary()["without_cost"], "0.00")


class ToCompleteTests(CostCase):
    def test_the_list_shows_what_is_missing_and_shrinks_as_it_is_filled_in(self):
        free = make_product(self.w.a, "FREE-1", "No price yet", self.w.unit, "0.00")
        self.intake(self.w.pad, 5)
        self.intake(self.w.oil, 5, "8.00")
        self.sell(self.w.pad, 2)
        data = self.owner.get(f"{self.w.base}/catalog/to-complete/").json()
        rows = {r["sku"]: r for r in data["results"]}
        self.assertEqual(data["count"], 2)  # the oil is complete: priced and costed
        self.assertEqual(
            (rows["BP-1"]["missing_price"], rows["BP-1"]["missing_cost"]), (False, True)
        )
        self.assertEqual(
            (rows["BP-1"]["stock_without_cost"], rows["BP-1"]["sold_without_cost"]),
            ("3.000", "2.000"),
        )
        self.assertEqual(
            (rows["FREE-1"]["missing_price"], rows["FREE-1"]["missing_cost"]), (True, False)
        )
        self.set_cost(self.w.pad, "60.00")
        free.price_amount = D("5.00")
        free.save()
        self.assertEqual(self.owner.get(f"{self.w.base}/catalog/to-complete/").json()["count"], 0)

    def test_archived_products_are_not_listed(self):
        make_product(self.w.a, "OLD-1", "Retired", self.w.unit, "0.00")
        Product.objects.filter(sku="OLD-1").update(is_active=False)
        self.assertEqual(self.owner.get(f"{self.w.base}/catalog/to-complete/").json()["count"], 0)

    def test_the_dashboard_counts_them_for_roles_that_can_fix_them(self):
        make_product(self.w.a, "FREE-1", "No price yet", self.w.unit, "0.00")
        self.assertEqual(self.owner.get(f"{self.w.base}/dashboard/").json()["to_complete_count"], 1)
        self.assertNotIn("to_complete_count", self.seller.get(f"{self.w.base}/dashboard/").json())
        self.assertNotIn("to_complete_count", self.keeper.get(f"{self.w.base}/dashboard/").json())


class AccessTests(CostCase):
    def test_only_owner_and_manager_can_enter_a_cost(self):
        self.intake(self.w.pad, 5)
        self.assertEqual(self.set_cost(self.w.pad, "5.00", client=self.seller).status_code, 403)
        self.assertEqual(self.set_cost(self.w.pad, "5.00", client=self.keeper).status_code, 403)
        self.assertFalse(self.layers(self.w.pad)[0].cost_known)
        self.assertEqual(self.set_cost(self.w.pad, "5.00", client=self.manager).status_code, 200)

    def test_the_list_is_for_those_who_manage_the_catalog(self):
        url = f"{self.w.base}/catalog/to-complete/"
        self.assertEqual(self.seller.get(url).status_code, 403)
        self.assertEqual(self.keeper.get(url).status_code, 403)
        self.assertEqual(self.manager.get(url).status_code, 200)

    def test_another_business_cannot_see_or_change_this_one(self):
        self.intake(self.w.pad, 5)
        self.assertEqual(
            self.w.b_api.post(
                f"{self.w.base}/products/{self.w.pad.pk}/cost/", {"unit_cost": "1"}, format="json"
            ).status_code,
            404,
        )
        other = f"/api/v1/businesses/{self.w.b.pk}/products/{self.w.pad.pk}/cost/"
        self.assertEqual(
            self.w.b_api.post(other, {"unit_cost": "1"}, format="json").status_code, 404
        )  # the product is not B's
        self.assertFalse(self.layers(self.w.pad)[0].cost_known)

    def test_a_bad_cost_is_refused(self):
        self.intake(self.w.pad, 5)
        for bad in ("-1", "abc", ""):
            response = self.owner.post(
                f"{self.w.base}/products/{self.w.pad.pk}/cost/", {"unit_cost": bad}, format="json"
            )
            self.assertEqual(response.status_code, 400, bad)
        self.assertFalse(self.layers(self.w.pad)[0].cost_known)
