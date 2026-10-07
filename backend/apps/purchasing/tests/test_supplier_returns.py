import threading
import uuid
from concurrent.futures import ThreadPoolExecutor
from decimal import Decimal

from django.db import DatabaseError, connection, connections, transaction

from apps.businesses.models import Role
from apps.common.testing import APITransactionTestCase, client_for
from apps.inventory.models import StockBalance
from apps.inventory.tests.support import World, ledger_differences
from apps.purchasing.models import (
    PurchaseOrder,
    PurchaseOrderLine,
    Supplier,
    SupplierReturn,
    SupplierReturnLine,
)
from apps.purchasing.tests.test_purchasing import PurchasingCase

D = Decimal


class SupplierReturnCase(PurchasingCase):
    def setUp(self):
        super().setUp()
        order = self.submitted(lines=[self.line(self.w.pad, 10, "50.00")])
        received = self.receive(
            order["id"], [{"order_line": order["lines"][0]["id"], "quantity": "10"}]
        )
        self.assertEqual(received.status_code, 201, received.content)
        self.order = self.get_order(order["id"])
        self.delivery = self.order["deliveries"][0]
        self.delivery_line = self.delivery["lines"][0]

    def send_back(self, quantity=2, condition="sellable", *, client=None, key=None, **extra):
        return (client or self.w.api[Role.WAREHOUSE]).post(
            f"{self.w.base}/supplier-returns/",
            {
                "delivery": self.delivery["id"],
                "reason": "Wrong model",
                "lines": [
                    {
                        "delivery_line": self.delivery_line["id"],
                        "quantity": str(quantity),
                        "condition": condition,
                    }
                ],
                **extra,
            },
            format="json",
            HTTP_IDEMPOTENCY_KEY=str(key or uuid.uuid4()),
        )

    def ok(self, *args, **kwargs):
        response = self.send_back(*args, **kwargs)
        self.assertEqual(response.status_code, 201, response.content)
        return response.json()


class SupplierReturnTests(SupplierReturnCase):
    def test_goods_leave_the_stock_and_the_credit_is_the_deliverys_price(self):
        made = self.ok(3, client=self.w.api[Role.OWNER])
        self.assertEqual(made["number"], 1)
        self.assertEqual(made["credit_total"], "150.00")
        self.assertEqual(made["supplier"]["name"], "Ashgabat Parts")
        self.assertEqual(made["delivery"]["order_number"], self.order["number"])
        self.assertEqual(self.on_hand(self.w.pad), D(7))

    def test_a_delivery_line_shows_what_can_still_go_back(self):
        self.ok(4)
        order = self.get_order(self.order["id"])
        line = order["deliveries"][0]["lines"][0]
        self.assertEqual(
            (line["returned_quantity"], line["returnable_quantity"]), ("4.000", "6.000")
        )

    def test_only_what_the_delivery_brought_can_go_back(self):
        self.ok(8)
        response = self.send_back(3)
        self.assertEqual(response.status_code, 409)
        error = response.json()["error"]
        self.assertEqual(error["code"], "over_return")
        self.assertEqual(error["params"]["returnable"], "2.000")

    def test_goods_already_sold_cannot_be_sent_back(self):
        self.w.remove(self.w.pad, self.w.warehouse, 9)  # only one piece is left
        response = self.send_back(2)
        self.assertEqual(response.status_code, 409)
        self.assertEqual(response.json()["error"]["code"], "insufficient_stock")
        self.assertEqual(SupplierReturn.objects.count(), 0)

    def test_damaged_goods_can_be_sent_back_from_the_damaged_pile(self):
        self.w.stock(self.w.pad, self.w.warehouse, 2, "50.00", condition="damaged")
        self.ok(2, "damaged")
        damaged = StockBalance.objects.get(product=self.w.pad, condition="damaged")
        self.assertEqual(damaged.quantity, D(0))
        sellable = StockBalance.objects.get(product=self.w.pad, condition="sellable")
        self.assertEqual(sellable.quantity, D(10))  # sellable stock untouched

    def test_a_reason_is_required_and_the_line_must_belong_to_the_delivery(self):
        self.assertEqual(self.send_back(1, reason=" ").status_code, 400)
        response = self.w.api[Role.OWNER].post(
            f"{self.w.base}/supplier-returns/",
            {
                "delivery": self.delivery["id"],
                "reason": "x",
                "lines": [{"delivery_line": str(uuid.uuid4()), "quantity": "1"}],
            },
            format="json",
            HTTP_IDEMPOTENCY_KEY=str(uuid.uuid4()),
        )
        self.assertEqual(response.status_code, 400)

    def test_the_credit_is_hidden_from_roles_without_cost_access(self):
        made = self.ok(1)
        warehouse = self.w.api[Role.WAREHOUSE].get(f"{self.w.base}/supplier-returns/{made['id']}/")
        self.assertNotIn("credit_total", warehouse.json())
        self.assertNotIn("unit_cost", warehouse.json()["lines"][0])
        manager = self.w.api[Role.MANAGER].get(f"{self.w.base}/supplier-returns/{made['id']}/")
        self.assertEqual(manager.json()["credit_total"], "50.00")

    def test_roles_locations_and_other_businesses(self):
        self.assertEqual(self.send_back(1, client=self.w.api[Role.SALES]).status_code, 403)
        self.assertEqual(self.send_back(1, client=self.w.b_api).status_code, 404)  # not a member
        made = self.ok(1)
        foreign = f"/api/v1/businesses/{self.w.b.pk}"
        self.assertEqual(
            self.w.b_api.get(f"{foreign}/supplier-returns/{made['id']}/").status_code, 404
        )
        self.assertEqual(self.w.b_api.get(f"{foreign}/supplier-returns/").json()["count"], 0)
        # the warehouse user only works at the warehouse, where this delivery arrived
        listed = self.w.api[Role.WAREHOUSE].get(f"{self.w.base}/supplier-returns/").json()
        self.assertEqual(listed["count"], 1)

    def test_a_seller_cannot_read_them(self):
        self.assertEqual(
            self.w.api[Role.SALES].get(f"{self.w.base}/supplier-returns/").status_code, 403
        )

    def test_the_same_key_replays_and_another_body_is_refused(self):
        key = uuid.uuid4()
        first = self.send_back(2, key=key)
        again = self.send_back(2, key=key)
        self.assertEqual((first.status_code, again.status_code), (201, 201))
        self.assertEqual(first.json()["id"], again.json()["id"])
        self.assertEqual(SupplierReturn.objects.count(), 1)
        self.assertEqual(self.send_back(3, key=key).status_code, 422)

    def test_returns_are_history_that_cannot_be_changed(self):
        self.ok(1)
        made = SupplierReturn.objects.get()
        line = SupplierReturnLine.objects.get()
        for table, pk in (
            ("purchasing_supplierreturn", made.pk),
            ("purchasing_supplierreturnline", line.pk),
        ):
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


class SupplierReturnConcurrencyTests(APITransactionTestCase):
    def setUp(self):
        super().setUp()
        self.w = World()
        self.supplier = Supplier.objects.create(business=self.w.a, name="Ashgabat Parts")
        owner = client_for(self.w.users[Role.OWNER])
        order = owner.post(
            f"{self.w.base}/purchase-orders/",
            {
                "supplier": str(self.supplier.pk),
                "location": str(self.w.warehouse.pk),
                "lines": [{"product": str(self.w.pad.pk), "quantity": "10", "unit_cost": "50.00"}],
            },
            format="json",
        ).json()
        owner.post(f"{self.w.base}/purchase-orders/{order['id']}/submit/")
        owner.post(
            f"{self.w.base}/purchase-orders/{order['id']}/deliveries/",
            {"lines": [{"order_line": order["lines"][0]["id"], "quantity": "10"}]},
            format="json",
            HTTP_IDEMPOTENCY_KEY=str(uuid.uuid4()),
        )
        self.delivery = owner.get(f"{self.w.base}/purchase-orders/{order['id']}/").json()[
            "deliveries"
        ][0]

    def tearDown(self):
        self.assertEqual(ledger_differences(), [])
        super().tearDown()

    def send_back(self, quantity, key=None):
        try:
            return client_for(self.w.users[Role.WAREHOUSE]).post(
                f"{self.w.base}/supplier-returns/",
                {
                    "delivery": self.delivery["id"],
                    "reason": "x",
                    "lines": [
                        {
                            "delivery_line": self.delivery["lines"][0]["id"],
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

    def test_two_returns_cannot_send_back_more_than_the_delivery_brought(self):
        responses = self.parallel([lambda: self.send_back(7), lambda: self.send_back(7)])
        self.assertEqual(sorted(r.status_code for r in responses), [201, 409])
        self.assertEqual(SupplierReturn.objects.count(), 1)

    def test_eight_simultaneous_copies_make_one_return(self):
        key = uuid.uuid4()
        responses = self.parallel([lambda: self.send_back(2, key=key) for _ in range(8)])
        self.assertEqual({r.status_code for r in responses}, {201})
        self.assertEqual(SupplierReturn.objects.count(), 1)
        self.assertEqual(StockBalance.objects.get().quantity, D(8))


class ReorderTests(PurchasingCase):
    def settings(self, product, location, minimum, target, client=None):
        response = (client or self.owner).put(
            f"{self.w.base}/products/{product.pk}/reorder-settings/",
            {"settings": [{"location": str(location.pk), "minimum": minimum, "target": target}]},
            format="json",
        )
        self.assertEqual(response.status_code, 200, response.content)

    def suggestions(self, query="", client=None):
        response = (client or self.owner).get(f"{self.w.base}/reorder-suggestions/{query}")
        self.assertEqual(response.status_code, 200, response.content)
        return response.json()

    def test_a_product_below_its_minimum_is_suggested_up_to_its_target(self):
        self.settings(self.w.pad, self.w.warehouse, "10", "30")
        self.w.stock(self.w.pad, self.w.warehouse, 4, "50.00")
        data = self.suggestions()
        self.assertEqual(data["count"], 1)
        row = data["results"][0]
        self.assertEqual(row["product"]["sku"], "BP-1")
        self.assertEqual(row["location"]["name"], "A Warehouse")
        self.assertEqual(
            (row["on_hand"], row["on_order"], row["minimum"], row["target"], row["suggested"]),
            ("4.000", "0.000", "10.000", "30.000", "26.000"),
        )

    def test_nothing_is_suggested_at_or_above_the_minimum(self):
        self.settings(self.w.pad, self.w.warehouse, "10", "30")
        self.w.stock(self.w.pad, self.w.warehouse, 10, "50.00")
        self.assertEqual(self.suggestions()["count"], 0)

    def test_goods_already_ordered_count_but_drafts_and_other_places_do_not(self):
        self.settings(self.w.pad, self.w.warehouse, "30", "50")
        self.w.stock(self.w.pad, self.w.warehouse, 4, "50.00")
        self.create_order(lines=[self.line(self.w.pad, 20, "50.00")])  # a draft: not counted yet
        row = self.suggestions()["results"][0]
        self.assertEqual((row["on_order"], row["suggested"]), ("0.000", "46.000"))
        ordered = self.submitted(lines=[self.line(self.w.pad, 20, "50.00")])
        row = self.suggestions()["results"][0]
        self.assertEqual((row["on_order"], row["suggested"]), ("20.000", "26.000"))
        # an order for another place does not count here
        self.submitted(lines=[self.line(self.w.pad, 50, "50.00")], location=self.w.store)
        self.assertEqual(self.suggestions()["results"][0]["on_order"], "20.000")
        # once received it is on the shelf and no longer "on order"
        self.receive(ordered["id"], [{"order_line": ordered["lines"][0]["id"], "quantity": "20"}])
        row = self.suggestions()["results"][0]
        self.assertEqual(
            (row["on_hand"], row["on_order"], row["suggested"]), ("24.000", "0.000", "26.000")
        )

    def test_damaged_goods_are_not_counted_as_stock(self):
        self.settings(self.w.pad, self.w.warehouse, "10", "30")
        self.w.stock(self.w.pad, self.w.warehouse, 20, "50.00", condition="damaged")
        self.assertEqual(self.suggestions()["results"][0]["suggested"], "30.000")

    def test_archived_products_and_other_locations_are_filtered(self):
        self.settings(self.w.pad, self.w.warehouse, "10", "30")
        self.settings(self.rotor, self.w.store, "5", "10")
        self.assertEqual(self.suggestions()["count"], 2)
        self.assertEqual(self.suggestions(f"?location={self.w.store.pk}")["count"], 1)
        self.owner.patch(
            f"{self.w.base}/products/{self.rotor.pk}/", {"is_active": False}, format="json"
        )
        self.assertEqual(self.suggestions()["count"], 1)

    def test_costs_only_for_owner_and_manager_and_the_list_is_not_for_everyone(self):
        self.settings(self.w.pad, self.w.warehouse, "10", "30")
        row = self.suggestions()["results"][0]
        self.assertIn("default_purchase_cost", row["product"])
        for role in (Role.SALES, Role.WAREHOUSE):
            self.assertEqual(
                self.w.api[role].get(f"{self.w.base}/reorder-suggestions/").status_code, 403
            )
        self.assertEqual(self.w.b_api.get(f"{self.w.base}/reorder-suggestions/").status_code, 404)

    def test_a_suggestion_becomes_a_draft_order_through_the_normal_order_api(self):
        self.settings(self.w.pad, self.w.warehouse, "10", "30")
        row = self.suggestions()["results"][0]
        order = self.create_order(
            lines=[
                self.line(self.w.pad, row["suggested"].rstrip("0").rstrip("."), "50.00"),
            ]
        )
        self.assertEqual(order["status"], "draft")
        self.assertEqual(PurchaseOrder.objects.count(), 1)
        self.assertEqual(PurchaseOrderLine.objects.get().quantity, D(30))
