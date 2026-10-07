import threading
import uuid
from concurrent.futures import ThreadPoolExecutor
from datetime import timedelta
from decimal import Decimal
from unittest import mock

from django.db import DatabaseError, connection, connections, transaction
from django.utils import timezone

from apps.audit.models import AuditEvent
from apps.businesses.models import Role
from apps.catalog.models import Product
from apps.common.testing import APITestCase, APITransactionTestCase, client_for
from apps.inventory.models import CostLayer, StockBalance, StockMovement
from apps.inventory.tests.support import World, ledger_differences, make_product
from apps.sales.models import ReturnInspection, Sale, SaleReturn, SaleReturnLine

D = Decimal


class ReturnsCase(APITestCase):
    def setUp(self):
        super().setUp()
        self.w = World()
        self.owner = self.w.api[Role.OWNER]
        self.sales = self.w.api[Role.SALES]
        self.store = self.w.store
        # two batches: 5 at 50.00, then 5 at 60.00
        self.w.stock(self.w.pad, self.store, 5, "50.00")
        self.w.stock(self.w.pad, self.store, 5, "60.00")

    def tearDown(self):
        self.assertEqual(ledger_differences(), [])
        super().tearDown()

    # -- helpers ------------------------------------------------------------------------
    def sell(self, quantity=7, price="100.00", product=None, client=None):
        product = product or self.w.pad
        response = (client or self.sales).post(
            f"{self.w.base}/sales/",
            {
                "location": str(self.store.pk),
                "lines": [
                    {"product": str(product.pk), "quantity": str(quantity), "unit_price": price}
                ],
            },
            format="json",
            HTTP_IDEMPOTENCY_KEY=str(uuid.uuid4()),
        )
        self.assertEqual(response.status_code, 201, response.content)
        return response.json()

    def give_back(self, sale, quantity=1, condition="sellable", *, client=None, key=None, **extra):
        body = {
            "reason": "Did not fit",
            "lines": [
                {
                    "sale_line": sale["lines"][0]["id"],
                    "quantity": str(quantity),
                    "condition": condition,
                }
            ],
            **extra,
        }
        return (client or self.sales).post(
            f"{self.w.base}/sales/{sale['id']}/returns/",
            body,
            format="json",
            HTTP_IDEMPOTENCY_KEY=str(key or uuid.uuid4()),
        )

    def ok(self, sale, quantity=1, condition="sellable", **kwargs):
        response = self.give_back(sale, quantity, condition, **kwargs)
        self.assertEqual(response.status_code, 201, response.content)
        return response.json()

    @staticmethod
    def pieces_by_cost(movement_type):
        """How many pieces came in at each unit cost (a movement is one cost slice)."""
        pieces: dict = {}
        for m in StockMovement.objects.filter(movement_type=movement_type, quantity__gt=0):
            pieces[m.unit_cost] = pieces.get(m.unit_cost, D(0)) + m.quantity
        return pieces

    def on_hand(self, condition="sellable", product=None):
        row = StockBalance.objects.filter(
            product=product or self.w.pad, location=self.store, condition=condition
        ).first()
        return row.quantity if row else D(0)


class ReturnBasicsTests(ReturnsCase):
    def test_a_return_refunds_what_was_charged_and_brings_the_goods_back(self):
        sale = self.sell(7, price="80.00")  # the seller gave a lower price than the catalog's 100
        self.assertEqual(self.on_hand(), D(3))
        made = self.ok(sale, 2)
        self.assertEqual(made["number"], 1)
        self.assertEqual(made["refund_total"], "160.00")  # 2 x 80, not 2 x 100
        self.assertEqual(made["payment_method"], "cash")
        self.assertEqual(made["sale"]["number"], 1)
        self.assertEqual(self.on_hand(), D(5))

    def test_goods_come_back_at_the_cost_they_were_sold_at(self):
        sale = self.sell(7)  # slices: 5 at 50.00 and 2 at 60.00
        self.ok(sale, 1)
        layer = CostLayer.objects.filter(balance__condition="sellable").order_by("-created_at")[0]
        self.assertEqual((layer.unit_cost, layer.quantity_initial), (D("50.00"), D(1)))
        self.ok(sale, 5)  # the 4 remaining at 50.00 and the first 60.00 one
        self.assertEqual(self.pieces_by_cost("return_in"), {D("50.00"): D(5), D("60.00"): D(1)})
        self.ok(sale, 1)  # the last one is the other 60.00
        total_cost = sum(
            m.unit_cost * m.quantity
            for m in StockMovement.objects.filter(movement_type="return_in")
        )
        self.assertEqual(total_cost, D("370.00"))  # exactly what the 7 pieces cost

    def test_only_what_is_still_returnable_can_come_back(self):
        sale = self.sell(3)
        self.ok(sale, 2)
        response = self.give_back(sale, 2)
        self.assertEqual(response.status_code, 409)
        error = response.json()["error"]
        self.assertEqual(error["code"], "over_return")
        self.assertEqual(error["params"]["returnable"], "1.000")
        self.ok(sale, 1)
        self.assertEqual(self.give_back(sale, 1).status_code, 409)
        self.assertEqual(SaleReturn.objects.count(), 2)

    def test_the_last_return_of_a_line_takes_the_remainder_so_cents_never_go_missing(self):
        product = make_product(self.w.a, "L-1", "Rope", self.w.litre, "0.33")
        self.w.stock(product, self.store, 10, "0.10")
        sale = self.sell("3.00", price="0.33", product=product)
        self.assertEqual(sale["total"], "0.99")
        refunds = [
            self.ok(sale, "0.30")["refund_total"],  # 0.099 -> 0.10
            self.ok(sale, "0.30")["refund_total"],
            self.ok(sale, "2.40")["refund_total"],  # the rest: what is left of 0.99
        ]
        self.assertEqual(sum(D(r) for r in refunds), D("0.99"))
        self.assertEqual(refunds[-1], "0.79")

    def test_a_reason_is_required(self):
        sale = self.sell(1)
        response = self.give_back(sale, 1, reason="  ")
        self.assertEqual(response.status_code, 400)
        self.assertIn("reason", response.json()["error"]["fields"])

    def test_a_line_that_is_not_part_of_the_sale_is_refused(self):
        sale = self.sell(1)
        other = self.sell(1)
        body = {
            "reason": "x",
            "lines": [
                {"sale_line": other["lines"][0]["id"], "quantity": "1", "condition": "sellable"}
            ],
        }
        response = self.sales.post(
            f"{self.w.base}/sales/{sale['id']}/returns/",
            body,
            format="json",
            HTTP_IDEMPOTENCY_KEY=str(uuid.uuid4()),
        )
        self.assertEqual(response.status_code, 400)
        self.assertEqual(response.json()["error"]["fields"]["lines"][0]["code"], "invalid_line")

    def test_quantities_follow_the_units_precision(self):
        sale = self.sell(3)
        self.assertEqual(self.give_back(sale, "0.5").status_code, 400)  # pieces are whole

    def test_returned_and_returnable_quantities_show_on_the_sale(self):
        sale = self.sell(4)
        self.ok(sale, 1)
        detail = self.sales.get(f"{self.w.base}/sales/{sale['id']}/").json()
        line = detail["lines"][0]
        self.assertEqual(
            (line["returned_quantity"], line["returnable_quantity"]), ("1.000", "3.000")
        )
        self.assertEqual([r["number"] for r in detail["returns"]], [1])
        self.assertIsNone(line["return_until"])  # no limit set on this product

    def test_everything_is_recorded_with_who_did_it(self):
        sale = self.sell(2)
        made = self.ok(sale, 1)
        self.assertEqual(made["created_by"]["name"], self.w.users[Role.SALES].username)
        event = AuditEvent.objects.filter(action="sale.returned").get()
        self.assertEqual(event.metadata["sale"], 1)


class ReturnWindowTests(ReturnsCase):
    def product_with(self, days):
        product = make_product(self.w.a, f"D-{days}", f"Item {days}", self.w.unit, "10.00")
        Product.objects.filter(pk=product.pk).update(return_days=days)
        product.refresh_from_db()
        self.w.stock(product, self.store, 20, "5.00")
        return product

    def later(self, days):
        today = timezone.localdate()
        return mock.patch("apps.sales.returns._today", return_value=today + timedelta(days=days))

    def test_the_window_counts_from_the_day_of_the_sale_and_includes_its_last_day(self):
        sale = self.sell(4, "10.00", self.product_with(7))
        self.assertEqual(sale["lines"][0]["return_days"], 7)
        self.assertIsNotNone(sale["lines"][0]["return_until"])
        with self.later(7):
            self.ok(sale, 1)
        with self.later(8):
            response = self.give_back(sale, 1)
        self.assertEqual(response.status_code, 409)
        error = response.json()["error"]
        self.assertEqual(error["code"], "return_window_expired")
        self.assertEqual(error["params"]["until"], sale["lines"][0]["return_until"])

    def test_zero_days_means_the_product_cannot_be_returned(self):
        sale = self.sell(1, "10.00", self.product_with(0))
        response = self.give_back(sale, 1)
        self.assertEqual(response.status_code, 409)
        self.assertEqual(response.json()["error"]["code"], "returns_not_accepted")

    def test_no_limit_means_it_can_always_be_returned(self):
        sale = self.sell(2)
        with self.later(5000):
            self.ok(sale, 1)

    def test_a_later_edit_of_the_product_never_changes_a_sale(self):
        product = self.product_with(7)
        sale = self.sell(2, "10.00", product)
        self.owner.patch(f"{self.w.base}/products/{product.pk}/", {"return_days": 0}, format="json")
        with self.later(3):
            self.ok(sale, 1)  # still the 7 days the sale was made with
        product.refresh_from_db()
        self.assertEqual(product.return_days, 0)

    def test_the_product_field_is_validated(self):
        response = self.owner.patch(
            f"{self.w.base}/products/{self.w.pad.pk}/", {"return_days": 5000}, format="json"
        )
        self.assertEqual(response.status_code, 400)
        cleared = self.owner.patch(
            f"{self.w.base}/products/{self.w.pad.pk}/", {"return_days": None}, format="json"
        )
        self.assertEqual(cleared.status_code, 200)


class ReturnConditionTests(ReturnsCase):
    def test_damaged_goods_do_not_become_available_stock(self):
        sale = self.sell(4)
        self.ok(sale, 1, "damaged")
        self.assertEqual(self.on_hand("sellable"), D(6))
        self.assertEqual(self.on_hand("damaged"), D(1))

    def test_goods_awaiting_inspection_are_set_aside_until_decided(self):
        sale = self.sell(4)
        made = self.ok(sale, 3, "inspection")
        self.assertEqual((self.on_hand("sellable"), self.on_hand("inspection")), (D(6), D(3)))
        line = made["lines"][0]
        self.assertEqual(line["awaiting_inspection"], "3.000")
        response = self.owner.post(
            f"{self.w.base}/returns/{made['id']}/inspections/",
            {
                "lines": [
                    {"return_line": line["id"], "outcome": "sellable", "quantity": "2"},
                ]
            },
            format="json",
            HTTP_IDEMPOTENCY_KEY=str(uuid.uuid4()),
        )
        self.assertEqual(response.status_code, 200, response.content)
        self.assertEqual(response.json()["lines"][0]["awaiting_inspection"], "1.000")
        self.assertEqual((self.on_hand("sellable"), self.on_hand("inspection")), (D(8), D(1)))
        again = self.owner.post(
            f"{self.w.base}/returns/{made['id']}/inspections/",
            {"lines": [{"return_line": line["id"], "outcome": "damaged", "quantity": "1"}]},
            format="json",
            HTTP_IDEMPOTENCY_KEY=str(uuid.uuid4()),
        )
        self.assertEqual(again.status_code, 200)
        self.assertEqual((self.on_hand("damaged"), self.on_hand("inspection")), (D(1), D(0)))
        self.assertEqual(ReturnInspection.objects.count(), 2)

    def test_the_decision_keeps_the_cost_of_the_goods(self):
        sale = self.sell(7)  # the 5 cheaper pieces and 2 dearer ones
        made = self.ok(sale, 6, "inspection")  # 5 at 50.00 and 1 at 60.00
        line = made["lines"][0]
        self.owner.post(
            f"{self.w.base}/returns/{made['id']}/inspections/",
            {"lines": [{"return_line": line["id"], "outcome": "sellable", "quantity": "6"}]},
            format="json",
            HTTP_IDEMPOTENCY_KEY=str(uuid.uuid4()),
        )
        self.assertEqual(self.pieces_by_cost("inspection_in"), {D("50.00"): D(5), D("60.00"): D(1)})

    def test_more_than_is_waiting_cannot_be_decided_and_other_lines_are_refused(self):
        sale = self.sell(4)
        waiting = self.ok(sale, 2, "inspection")
        too_much = self.owner.post(
            f"{self.w.base}/returns/{waiting['id']}/inspections/",
            {
                "lines": [
                    {
                        "return_line": waiting["lines"][0]["id"],
                        "outcome": "sellable",
                        "quantity": "3",
                    }
                ]
            },
            format="json",
            HTTP_IDEMPOTENCY_KEY=str(uuid.uuid4()),
        )
        self.assertEqual(too_much.status_code, 409)
        self.assertEqual(too_much.json()["error"]["code"], "over_inspection")
        shelf = self.ok(sale, 1, "sellable")
        wrong = self.owner.post(
            f"{self.w.base}/returns/{shelf['id']}/inspections/",
            {
                "lines": [
                    {"return_line": shelf["lines"][0]["id"], "outcome": "damaged", "quantity": "1"}
                ]
            },
            format="json",
            HTTP_IDEMPOTENCY_KEY=str(uuid.uuid4()),
        )
        self.assertEqual(wrong.status_code, 409)
        self.assertEqual(wrong.json()["error"]["code"], "not_awaiting_inspection")

    def test_only_owner_and_manager_decide(self):
        sale = self.sell(2)
        made = self.ok(sale, 1, "inspection")
        body = {
            "lines": [
                {"return_line": made["lines"][0]["id"], "outcome": "sellable", "quantity": "1"}
            ]
        }
        for role in (Role.SALES, Role.WAREHOUSE):
            response = self.w.api[role].post(
                f"{self.w.base}/returns/{made['id']}/inspections/",
                body,
                format="json",
                HTTP_IDEMPOTENCY_KEY=str(uuid.uuid4()),
            )
            self.assertEqual(response.status_code, 403, role)


class ReturnAccessTests(ReturnsCase):
    def test_the_warehouse_cannot_make_or_read_returns(self):
        sale = self.sell(2)
        self.assertEqual(
            self.give_back(sale, 1, client=self.w.api[Role.WAREHOUSE]).status_code, 403
        )
        self.assertEqual(self.w.api[Role.WAREHOUSE].get(f"{self.w.base}/returns/").status_code, 403)

    def test_another_business_cannot_see_or_return_a_sale(self):
        sale = self.sell(2)
        made = self.ok(sale, 1)
        self.assertEqual(self.give_back(sale, 1, client=self.w.b_api).status_code, 404)
        foreign = f"/api/v1/businesses/{self.w.b.pk}"
        self.assertEqual(self.w.b_api.get(f"{foreign}/returns/{made['id']}/").status_code, 404)
        self.assertEqual(self.w.b_api.get(f"{foreign}/returns/").json()["count"], 0)

    def test_a_seller_only_returns_sales_of_their_own_locations(self):
        self.w.stock(self.w.pad, self.w.warehouse, 5, "50.00")
        response = self.owner.post(
            f"{self.w.base}/sales/",
            {
                "location": str(self.w.warehouse.pk),
                "lines": [{"product": str(self.w.pad.pk), "quantity": "2", "unit_price": "100.00"}],
            },
            format="json",
            HTTP_IDEMPOTENCY_KEY=str(uuid.uuid4()),
        )
        sale = response.json()
        self.assertEqual(self.give_back(sale, 1).status_code, 404)  # the seller works at the store

    def test_cost_is_shown_to_owner_and_manager_only(self):
        sale = self.sell(2)
        made = self.ok(sale, 1)
        seller = self.sales.get(f"{self.w.base}/returns/{made['id']}/").json()
        self.assertNotIn("cost_total", seller["lines"][0])
        manager = self.w.api[Role.MANAGER].get(f"{self.w.base}/returns/{made['id']}/").json()
        self.assertEqual(manager["lines"][0]["cost_total"], "50.00")

    def test_the_list_filters_by_number_and_sale(self):
        first, second = self.sell(2), self.sell(2)
        self.ok(first, 1)
        made = self.ok(second, 1)
        listed = self.sales.get(f"{self.w.base}/returns/?q=R-0002").json()
        self.assertEqual([r["id"] for r in listed["results"]], [made["id"]])
        by_sale = self.sales.get(f"{self.w.base}/returns/?sale={first['id']}").json()
        self.assertEqual(by_sale["count"], 1)
        self.assertFalse(listed["results"][0]["awaiting_inspection"])


class ReturnHistoryIsFixedTests(ReturnsCase):
    def test_returns_cannot_be_edited_or_deleted_even_with_raw_sql(self):
        sale = self.sell(2)
        self.ok(sale, 1, "inspection")
        made = SaleReturn.objects.get()
        line = SaleReturnLine.objects.get()
        for table, pk in (("sales_salereturn", made.pk), ("sales_salereturnline", line.pk)):
            for sql in (
                f"UPDATE {table} SET id = id WHERE id = %s",
                f"DELETE FROM {table} WHERE id = %s",
            ):
                with (
                    self.assertRaises(DatabaseError),
                    transaction.atomic(),
                    connection.cursor() as c,
                ):
                    c.execute(sql, [pk])
        made.refund_total = D(1)
        with self.assertRaises(RuntimeError):
            made.save()


class ReturnRetryTests(ReturnsCase):
    def test_the_same_key_replays_the_same_return(self):
        sale = self.sell(3)
        key = uuid.uuid4()
        first = self.give_back(sale, 1, key=key)
        again = self.give_back(sale, 1, key=key)
        self.assertEqual((first.status_code, again.status_code), (201, 201))
        self.assertEqual(first.json()["id"], again.json()["id"])
        self.assertEqual(SaleReturn.objects.count(), 1)
        self.assertEqual(self.on_hand(), D(8))

    def test_the_same_key_with_another_body_is_refused(self):
        sale = self.sell(3)
        key = uuid.uuid4()
        self.assertEqual(self.give_back(sale, 1, key=key).status_code, 201)
        self.assertEqual(self.give_back(sale, 2, key=key).status_code, 422)

    def test_the_outcome_of_a_lost_answer_can_be_asked_for(self):
        sale = self.sell(3)
        key = uuid.uuid4()
        made = self.give_back(sale, 1, key=key).json()
        status = self.sales.get(f"{self.w.base}/operations/return_complete/{key}/")
        self.assertEqual(status.status_code, 200)
        self.assertEqual(status.json()["response"]["id"], made["id"])


class ReturnConcurrencyTests(APITransactionTestCase):
    """Real commits and real threads against PostgreSQL."""

    def setUp(self):
        super().setUp()
        self.w = World()
        self.w.stock(self.w.pad, self.w.store, 10, "50.00")
        response = client_for(self.w.users[Role.SALES]).post(
            f"{self.w.base}/sales/",
            {
                "location": str(self.w.store.pk),
                "lines": [{"product": str(self.w.pad.pk), "quantity": "6", "unit_price": "100.00"}],
            },
            format="json",
            HTTP_IDEMPOTENCY_KEY=str(uuid.uuid4()),
        )
        self.sale = response.json()

    def tearDown(self):
        self.assertEqual(ledger_differences(), [])
        super().tearDown()

    def give_back(self, quantity, key=None):
        try:
            return client_for(self.w.users[Role.SALES]).post(
                f"{self.w.base}/sales/{self.sale['id']}/returns/",
                {
                    "reason": "x",
                    "lines": [
                        {
                            "sale_line": self.sale["lines"][0]["id"],
                            "quantity": str(quantity),
                            "condition": "sellable",
                        }
                    ],
                },
                format="json",
                HTTP_IDEMPOTENCY_KEY=str(key or uuid.uuid4()),
            )
        finally:
            connections.close_all()

    def parallel(self, calls):
        barrier = threading.Barrier(len(calls))

        def worker(call):
            barrier.wait(timeout=10)
            return call()

        with ThreadPoolExecutor(max_workers=len(calls)) as pool:
            return list(pool.map(worker, calls))

    def test_two_returns_cannot_bring_back_more_than_was_sold(self):
        responses = self.parallel([lambda: self.give_back(4), lambda: self.give_back(4)])
        self.assertEqual(sorted(r.status_code for r in responses), [201, 409])
        self.assertEqual(SaleReturn.objects.count(), 1)
        self.assertEqual(SaleReturnLine.objects.get().quantity, D(4))

    def test_many_simultaneous_single_returns_stop_at_what_was_sold(self):
        responses = self.parallel([lambda: self.give_back(1) for _ in range(10)])
        self.assertEqual(sorted(r.status_code for r in responses), [201] * 6 + [409] * 4)
        self.assertEqual(SaleReturn.objects.count(), 6)
        self.assertEqual(
            sorted(SaleReturn.objects.values_list("number", flat=True)), list(range(1, 7))
        )
        total = sum(SaleReturnLine.objects.values_list("refund_amount", flat=True))
        self.assertEqual(total, D("600.00"))

    def test_eight_simultaneous_copies_of_one_return_make_one_return(self):
        key = uuid.uuid4()
        responses = self.parallel([lambda: self.give_back(2, key=key) for _ in range(8)])
        self.assertEqual({r.status_code for r in responses}, {201})
        self.assertEqual(len({r.json()["id"] for r in responses}), 1)
        self.assertEqual(SaleReturn.objects.count(), 1)
        self.assertEqual(Sale.objects.count(), 1)

    def test_two_decisions_cannot_decide_more_than_is_waiting(self):
        made = (
            client_for(self.w.users[Role.SALES])
            .post(
                f"{self.w.base}/sales/{self.sale['id']}/returns/",
                {
                    "reason": "x",
                    "lines": [
                        {
                            "sale_line": self.sale["lines"][0]["id"],
                            "quantity": "3",
                            "condition": "inspection",
                        }
                    ],
                },
                format="json",
                HTTP_IDEMPOTENCY_KEY=str(uuid.uuid4()),
            )
            .json()
        )

        def decide(outcome):
            try:
                return client_for(self.w.users[Role.OWNER]).post(
                    f"{self.w.base}/returns/{made['id']}/inspections/",
                    {
                        "lines": [
                            {
                                "return_line": made["lines"][0]["id"],
                                "outcome": outcome,
                                "quantity": "2",
                            }
                        ]
                    },
                    format="json",
                    HTTP_IDEMPOTENCY_KEY=str(uuid.uuid4()),
                )
            finally:
                connections.close_all()

        responses = self.parallel([lambda: decide("sellable"), lambda: decide("damaged")])
        self.assertEqual(sorted(r.status_code for r in responses), [200, 409])
        self.assertEqual(ReturnInspection.objects.count(), 1)
