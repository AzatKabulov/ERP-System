import threading
import uuid
from concurrent.futures import ThreadPoolExecutor
from decimal import Decimal

from django.db import connections

from apps.audit.models import AuditEvent
from apps.businesses.models import Role
from apps.catalog.models import Product
from apps.common.testing import APITestCase, APITransactionTestCase, client_for
from apps.inventory.models import CostLayer, StockBalance, StockMovement
from apps.inventory.tests.support import World, ledger_differences, make_product
from apps.purchasing.models import Delivery, PurchaseOrder, PurchaseOrderLine, Supplier

D = Decimal


class PurchasingCase(APITestCase):
    def setUp(self):
        super().setUp()
        self.w = World()
        self.owner = self.w.api[Role.OWNER]
        self.supplier = Supplier.objects.create(business=self.w.a, name="Ashgabat Parts")
        self.rotor = make_product(self.w.a, "RT-1", "Rotor", self.w.unit)

    def tearDown(self):
        self.assertEqual(ledger_differences(), [])
        super().tearDown()

    # -- helpers --------------------------------------------------------------------------
    def create_order(self, lines=None, client=None, location=None, **extra):
        lines = lines if lines is not None else [self.line(self.w.pad, 10, "50.00")]
        response = (client or self.owner).post(
            f"{self.w.base}/purchase-orders/",
            {
                "supplier": str(self.supplier.pk),
                "location": str((location or self.w.warehouse).pk),
                "lines": lines,
                **extra,
            },
            format="json",
        )
        self.assertEqual(response.status_code, 201, response.content)
        return response.json()

    @staticmethod
    def line(product, quantity, cost):
        return {"product": str(product.pk), "quantity": str(quantity), "unit_cost": str(cost)}

    def submitted(self, **kwargs):
        order = self.create_order(**kwargs)
        self.submit(order["id"])
        return order

    def submit(self, order_id, client=None):
        return (client or self.owner).post(f"{self.w.base}/purchase-orders/{order_id}/submit/")

    def receive(self, order_id, lines, key=None, client=None, note=""):
        return (client or self.w.api[Role.WAREHOUSE]).post(
            f"{self.w.base}/purchase-orders/{order_id}/deliveries/",
            {"lines": lines, "note": note},
            format="json",
            HTTP_IDEMPOTENCY_KEY=str(key or uuid.uuid4()),
        )

    def get_order(self, order_id, client=None):
        return (client or self.owner).get(f"{self.w.base}/purchase-orders/{order_id}/").json()

    def on_hand(self, product, location=None):
        row = StockBalance.objects.filter(
            product=product, location=location or self.w.warehouse
        ).first()
        return row.quantity if row else D(0)


class SupplierTests(PurchasingCase):
    def test_create_list_search_edit_archive(self):
        url = f"{self.w.base}/suppliers/"
        created = self.owner.post(
            url, {"name": "Türkmen Täze Ätiýaçlyk", "phone": "+993 12 000000"}, format="json"
        )
        self.assertEqual(created.status_code, 201, created.content)
        self.assertEqual(created.json()["name"], "Türkmen Täze Ätiýaçlyk")
        listing = self.owner.get(url).json()
        self.assertEqual(listing["count"], 2)
        self.assertEqual(self.owner.get(f"{url}?q=ashgabat").json()["count"], 1)
        edit = self.owner.patch(
            f"{url}{created.json()['id']}/", {"notes": "Pays cash"}, format="json"
        )
        self.assertEqual(edit.json()["notes"], "Pays cash")
        archive = self.owner.patch(
            f"{url}{created.json()['id']}/", {"is_active": False}, format="json"
        )
        self.assertFalse(archive.json()["is_active"])
        self.assertEqual(self.owner.get(url).json()["count"], 1)  # archived ones are hidden
        self.assertEqual(self.owner.get(f"{url}?active=0").json()["count"], 1)

    def test_names_are_unique_per_business_ignoring_case(self):
        url = f"{self.w.base}/suppliers/"
        clash = self.owner.post(url, {"name": "ASHGABAT parts"}, format="json")
        self.assertEqual(clash.status_code, 400)
        self.assertEqual(clash.json()["error"]["fields"]["name"][0]["code"], "name_taken")
        other = self.w.b_api.post(
            f"/api/v1/businesses/{self.w.b.pk}/suppliers/",
            {"name": "Ashgabat Parts"},
            format="json",
        )
        self.assertEqual(other.status_code, 201)

    def test_roles_and_isolation(self):
        url = f"{self.w.base}/suppliers/"
        self.assertEqual(self.w.api[Role.WAREHOUSE].get(url).status_code, 200)
        self.assertEqual(
            self.w.api[Role.WAREHOUSE].post(url, {"name": "X"}, format="json").status_code, 403
        )
        self.assertEqual(self.w.api[Role.SALES].get(url).status_code, 403)
        self.assertEqual(
            self.w.api[Role.MANAGER].post(url, {"name": "Y"}, format="json").status_code, 201
        )
        self.assertEqual(self.w.b_api.get(url).status_code, 404)
        detail = f"{url}{self.supplier.pk}/"
        self.assertEqual(
            client_for(self.w.b_owner)
            .get(f"/api/v1/businesses/{self.w.b.pk}/suppliers/{self.supplier.pk}/")
            .status_code,
            404,
        )
        self.assertEqual(self.owner.get(detail).status_code, 200)


class OrderLifecycleTests(PurchasingCase):
    def test_a_new_order_is_a_draft_with_a_running_number_and_no_stock_effect(self):
        first = self.create_order()
        second = self.create_order([self.line(self.rotor, 2, "30")])
        self.assertEqual((first["number"], second["number"]), (1, 2))
        self.assertEqual(first["status"], "draft")
        self.assertEqual(first["total"], "500.00")
        self.assertEqual(first["lines"][0]["line_total"], "500.00")
        self.assertEqual(StockMovement.objects.count(), 0)  # an order never moves stock
        self.submit(first["id"])
        self.assertEqual(StockMovement.objects.count(), 0)

    def test_numbers_are_per_business(self):
        self.create_order()
        supplier_b = Supplier.objects.create(business=self.w.b, name="B supplier")
        response = self.w.b_api.post(
            f"/api/v1/businesses/{self.w.b.pk}/purchase-orders/",
            {
                "supplier": str(supplier_b.pk),
                "location": str(self.w.b_store.pk),
                "lines": [self.line(self.w.b_product, 1, "5")],
            },
            format="json",
        )
        self.assertEqual(response.json()["number"], 1)

    def test_draft_can_be_edited_then_submitted_and_is_then_fixed(self):
        order = self.create_order()
        url = f"{self.w.base}/purchase-orders/{order['id']}/"
        edit = self.owner.patch(
            url,
            {
                "notes": "Urgent",
                "expected_date": "2026-11-01",
                "lines": [self.line(self.w.pad, 4, "55"), self.line(self.rotor, 1, "20")],
            },
            format="json",
        )
        self.assertEqual(edit.status_code, 200, edit.content)
        self.assertEqual([line["quantity"] for line in edit.json()["lines"]], ["4.000", "1.000"])
        self.assertEqual(edit.json()["total"], "240.00")
        self.assertEqual(self.submit(order["id"]).json()["status"], "ordered")
        locked = self.owner.patch(url, {"notes": "Too late"}, format="json")
        self.assertEqual(
            (locked.status_code, locked.json()["error"]["code"]), (409, "order_not_draft")
        )
        again = self.submit(order["id"])
        self.assertEqual(
            (again.status_code, again.json()["error"]["code"]), (409, "order_not_draft")
        )

    def test_an_order_without_lines_cannot_be_submitted(self):
        order = self.create_order(lines=[])
        response = self.submit(order["id"])
        self.assertEqual(
            (response.status_code, response.json()["error"]["code"]), (409, "order_has_no_lines")
        )

    def test_line_validation(self):
        for name, lines in {
            "zero quantity": [self.line(self.w.pad, 0, "1")],
            "negative cost": [self.line(self.w.pad, 1, "-1")],
            "half a piece": [self.line(self.w.pad, "1.5", "1")],
            "duplicate product": [self.line(self.w.pad, 1, "1"), self.line(self.w.pad, 2, "1")],
            "other business's product": [self.line(self.w.b_product, 1, "1")],
        }.items():
            with self.subTest(name):
                response = self.owner.post(
                    f"{self.w.base}/purchase-orders/",
                    {
                        "supplier": str(self.supplier.pk),
                        "location": str(self.w.warehouse.pk),
                        "lines": lines,
                    },
                    format="json",
                )
                self.assertEqual(response.status_code, 400, response.content)
        self.assertEqual(PurchaseOrder.objects.count(), 0)

    def test_archived_products_and_foreign_suppliers_are_refused(self):
        Product.objects.filter(pk=self.rotor.pk).update(is_active=False)
        archived = self.owner.post(
            f"{self.w.base}/purchase-orders/",
            {
                "supplier": str(self.supplier.pk),
                "location": str(self.w.warehouse.pk),
                "lines": [self.line(self.rotor, 1, "1")],
            },
            format="json",
        )
        self.assertEqual(
            (archived.status_code, archived.json()["error"]["code"]), (409, "product_archived")
        )
        foreign = Supplier.objects.create(business=self.w.b, name="Foreign")
        response = self.owner.post(
            f"{self.w.base}/purchase-orders/",
            {"supplier": str(foreign.pk), "location": str(self.w.warehouse.pk), "lines": []},
            format="json",
        )
        self.assertEqual(response.status_code, 400)

    def test_cancel_a_draft_or_an_ordered_order_but_not_twice(self):
        draft = self.create_order()
        cancelled = self.owner.post(
            f"{self.w.base}/purchase-orders/{draft['id']}/cancel/",
            {"reason": "Changed mind"},
            format="json",
        )
        self.assertEqual(cancelled.json()["status"], "cancelled")
        self.assertEqual(cancelled.json()["cancel_reason"], "Changed mind")
        again = self.owner.post(
            f"{self.w.base}/purchase-orders/{draft['id']}/cancel/", {}, format="json"
        )
        self.assertEqual(
            (again.status_code, again.json()["error"]["code"]), (409, "order_not_cancellable")
        )
        ordered = self.submitted()
        self.assertEqual(
            self.owner.post(
                f"{self.w.base}/purchase-orders/{ordered['id']}/cancel/", {}, format="json"
            ).json()["status"],
            "cancelled",
        )

    def test_listing_and_filters(self):
        self.create_order()
        ordered = self.submitted()
        everything = self.owner.get(f"{self.w.base}/purchase-orders/").json()
        self.assertEqual(everything["count"], 2)
        self.assertEqual(everything["results"][0]["number"], 2)  # newest first
        self.assertEqual(everything["results"][0]["ordered_quantity"], "10.000")
        self.assertEqual(everything["results"][0]["total"], "500.00")
        only = self.owner.get(f"{self.w.base}/purchase-orders/?status=ordered").json()
        self.assertEqual([o["id"] for o in only["results"]], [ordered["id"]])

    def test_roles_and_isolation(self):
        base = f"{self.w.base}/purchase-orders/"
        body = {"supplier": str(self.supplier.pk), "location": str(self.w.warehouse.pk)}
        self.assertEqual(self.w.api[Role.MANAGER].post(base, body, format="json").status_code, 201)
        for role in (Role.WAREHOUSE, Role.SALES):
            self.assertEqual(self.w.api[role].post(base, body, format="json").status_code, 403)
        self.assertEqual(self.w.api[Role.SALES].get(base).status_code, 403)
        order = self.create_order()
        self.assertEqual(
            self.submit(order["id"], client=self.w.api[Role.WAREHOUSE]).status_code, 403
        )
        self.assertEqual(
            self.w.b_api.get(f"{self.w.base}/purchase-orders/{order['id']}/").status_code, 404
        )
        wrong_business = f"/api/v1/businesses/{self.w.b.pk}/purchase-orders/{order['id']}/"
        self.assertEqual(self.w.b_api.get(wrong_business).status_code, 404)  # not B's order


class ReceivingTests(PurchasingCase):
    def setUp(self):
        super().setUp()
        self.order = self.submitted(
            lines=[self.line(self.w.pad, 10, "50.00"), self.line(self.rotor, 4, "30.00")]
        )
        self.pad_line, self.rotor_line = (line["id"] for line in self.order["lines"])

    def test_a_full_receipt_adds_stock_at_the_orders_location_at_line_cost(self):
        response = self.receive(
            self.order["id"],
            [
                {"order_line": self.pad_line, "quantity": "10"},
                {"order_line": self.rotor_line, "quantity": "4"},
            ],
            note="Truck 7",
        )
        self.assertEqual(response.status_code, 201, response.content)
        body = response.json()
        self.assertEqual(body["delivery_number"], 1)
        self.assertEqual(body["order"]["status"], "received")
        self.assertEqual(self.on_hand(self.w.pad), D(10))
        self.assertEqual(self.on_hand(self.rotor), D(4))
        self.assertEqual(self.on_hand(self.w.pad, self.w.store), D(0))
        movement = StockMovement.objects.get(product=self.w.pad)
        self.assertEqual(
            (movement.movement_type, movement.unit_cost, movement.reason),
            ("receipt", D("50.00"), "Truck 7"),
        )
        self.assertEqual(movement.document_id, Delivery.objects.get().pk)
        self.assertEqual(AuditEvent.objects.filter(action="purchase_order.received").count(), 1)

    def test_partial_then_final_delivery(self):
        first = self.receive(self.order["id"], [{"order_line": self.pad_line, "quantity": "4"}])
        self.assertEqual(first.json()["order"]["status"], "partially_received")
        line = next(x for x in first.json()["order"]["lines"] if x["id"] == self.pad_line)
        self.assertEqual((line["received_quantity"], line["outstanding"]), ("4.000", "6.000"))
        second = self.receive(
            self.order["id"],
            [
                {"order_line": self.pad_line, "quantity": "6"},
                {"order_line": self.rotor_line, "quantity": "4"},
            ],
        )
        self.assertEqual(second.json()["delivery_number"], 2)
        self.assertEqual(second.json()["order"]["status"], "received")
        self.assertEqual(self.on_hand(self.w.pad), D(10))
        self.assertEqual(len(self.get_order(self.order["id"])["deliveries"]), 2)
        done = self.receive(self.order["id"], [{"order_line": self.pad_line, "quantity": "1"}])
        self.assertEqual(
            (done.status_code, done.json()["error"]["code"]), (409, "order_not_receivable")
        )

    def test_more_than_is_outstanding_is_refused(self):
        self.receive(self.order["id"], [{"order_line": self.pad_line, "quantity": "8"}])
        over = self.receive(self.order["id"], [{"order_line": self.pad_line, "quantity": "3"}])
        self.assertEqual((over.status_code, over.json()["error"]["code"]), (409, "over_receipt"))
        self.assertEqual(over.json()["error"]["params"]["outstanding"], "2.000")
        self.assertEqual(self.on_hand(self.w.pad), D(8))
        self.assertEqual(Delivery.objects.count(), 1)  # the refused attempt left nothing behind

    def test_one_bad_line_stops_the_whole_delivery(self):
        response = self.receive(
            self.order["id"],
            [
                {"order_line": self.pad_line, "quantity": "5"},
                {"order_line": self.rotor_line, "quantity": "9"},
            ],
        )
        self.assertEqual(response.status_code, 409)
        self.assertEqual(self.on_hand(self.w.pad), D(0))
        self.assertEqual(Delivery.objects.count(), 0)
        self.assertEqual(PurchaseOrderLine.objects.get(pk=self.pad_line).received_quantity, D(0))

    def test_malformed_deliveries(self):
        cases = {
            "no lines": [],
            "zero": [{"order_line": self.pad_line, "quantity": "0"}],
            "half a piece": [{"order_line": self.pad_line, "quantity": "1.5"}],
            "unknown line": [{"order_line": str(uuid.uuid4()), "quantity": "1"}],
            "same line twice": [{"order_line": self.pad_line, "quantity": "1"}] * 2,
        }
        for name, lines in cases.items():
            with self.subTest(name):
                response = self.receive(self.order["id"], lines)
                self.assertIn(response.status_code, (400,), response.content)
        self.assertEqual(Delivery.objects.count(), 0)

    def test_a_line_of_another_order_is_not_accepted(self):
        other = self.submitted(lines=[self.line(self.w.pad, 5, "40")])
        stranger = other["lines"][0]["id"]
        response = self.receive(self.order["id"], [{"order_line": stranger, "quantity": "1"}])
        self.assertEqual(response.status_code, 400)
        self.assertEqual(Delivery.objects.count(), 0)

    def test_drafts_and_cancelled_orders_cannot_be_received(self):
        draft = self.create_order()
        response = self.receive(
            draft["id"], [{"order_line": draft["lines"][0]["id"], "quantity": "1"}]
        )
        self.assertEqual(
            (response.status_code, response.json()["error"]["code"]), (409, "order_not_receivable")
        )
        self.owner.post(
            f"{self.w.base}/purchase-orders/{self.order['id']}/cancel/", {}, format="json"
        )
        cancelled = self.receive(self.order["id"], [{"order_line": self.pad_line, "quantity": "1"}])
        self.assertEqual(cancelled.json()["error"]["code"], "order_not_receivable")

    def test_cancelling_after_a_partial_receipt_keeps_what_arrived(self):
        self.receive(self.order["id"], [{"order_line": self.pad_line, "quantity": "4"}])
        cancelled = self.owner.post(
            f"{self.w.base}/purchase-orders/{self.order['id']}/cancel/",
            {"reason": "Supplier out of stock"},
            format="json",
        )
        self.assertEqual(cancelled.json()["status"], "cancelled")
        self.assertEqual(self.on_hand(self.w.pad), D(4))
        self.assertEqual(len(cancelled.json()["deliveries"]), 1)

    def test_goods_of_two_orders_at_different_prices_are_used_oldest_first(self):
        """Owner's rule: 10 bought at 50, 10 bought at 60; selling 15 costs 10x50 + 5x60."""
        self.receive(self.order["id"], [{"order_line": self.pad_line, "quantity": "10"}])
        second = self.submitted(lines=[self.line(self.w.pad, 10, "60.00")])
        self.receive(second["id"], [{"order_line": second["lines"][0]["id"], "quantity": "10"}])
        response = self.owner.post(
            f"{self.w.base}/stock/adjustments/",
            {
                "location": str(self.w.warehouse.pk),
                "reason": "Sold on account",
                "lines": [{"product": str(self.w.pad.pk), "direction": "out", "quantity": "15"}],
            },
            format="json",
            HTTP_IDEMPOTENCY_KEY=str(uuid.uuid4()),
        )
        slices = [(m["quantity"], m["unit_cost"]) for m in response.json()["movements"]]
        self.assertEqual(slices, [("-10.000", "50.00"), ("-5.000", "60.00")])
        self.assertEqual(
            CostLayer.objects.filter(quantity_remaining__gt=0).get().unit_cost, D("60.00")
        )

    def test_the_warehouse_sees_quantities_but_never_a_cost(self):
        self.receive(self.order["id"], [{"order_line": self.pad_line, "quantity": "4"}])
        warehouse = self.w.api[Role.WAREHOUSE]
        detail = warehouse.get(f"{self.w.base}/purchase-orders/{self.order['id']}/")
        self.assertEqual(detail.status_code, 200)
        text = detail.content.decode()
        for forbidden in ("unit_cost", "line_total", '"total"', "50.00", "30.00"):
            self.assertNotIn(forbidden, text)
        self.assertIn('"outstanding"', text)
        listing = warehouse.get(f"{self.w.base}/purchase-orders/").content.decode()
        self.assertNotIn('"total"', listing)
        receive = self.receive(self.order["id"], [{"order_line": self.rotor_line, "quantity": "1"}])
        self.assertNotIn("unit_cost", receive.content.decode())
        manager = (
            self.w.api[Role.MANAGER]
            .get(f"{self.w.base}/purchase-orders/{self.order['id']}/")
            .json()
        )
        self.assertEqual(manager["lines"][0]["unit_cost"], "50.00")

    def test_a_warehouse_user_works_only_at_their_own_location(self):
        at_store = self.submitted(location=self.w.store)  # not the warehouse user's location
        line = at_store["lines"][0]["id"]
        hidden = self.receive(at_store["id"], [{"order_line": line, "quantity": "1"}])
        self.assertEqual(hidden.status_code, 404)
        listed = self.w.api[Role.WAREHOUSE].get(f"{self.w.base}/purchase-orders/").json()
        self.assertNotIn(at_store["id"], [o["id"] for o in listed["results"]])
        manager_receipt = self.receive(
            at_store["id"], [{"order_line": line, "quantity": "1"}], client=self.w.api[Role.MANAGER]
        )
        self.assertEqual(manager_receipt.status_code, 201)

    def test_roles_that_may_not_receive_are_refused(self):
        response = self.receive(
            self.order["id"],
            [{"order_line": self.pad_line, "quantity": "1"}],
            client=self.w.api[Role.SALES],
        )
        self.assertEqual(response.status_code, 403)
        outsider = self.receive(
            self.order["id"], [{"order_line": self.pad_line, "quantity": "1"}], client=self.w.b_api
        )
        self.assertEqual(outsider.status_code, 404)
        self.assertEqual(Delivery.objects.count(), 0)


class ReceivingRetryTests(PurchasingCase):
    """The same receipt sent twice - after a timeout, or after the app restarted - counts once."""

    def setUp(self):
        super().setUp()
        self.order = self.submitted()
        self.line_id = self.order["lines"][0]["id"]

    def test_same_key_same_request_replays_the_stored_result(self):
        key = uuid.uuid4()
        lines = [{"order_line": self.line_id, "quantity": "4"}]
        first = self.receive(self.order["id"], lines, key)
        second = self.receive(self.order["id"], lines, key)
        self.assertEqual((first.status_code, second.status_code), (201, 201))
        self.assertEqual(first.json(), second.json())
        self.assertEqual(second["Idempotent-Replay"], "true")
        self.assertEqual(Delivery.objects.count(), 1)
        self.assertEqual(StockMovement.objects.count(), 1)
        self.assertEqual(self.on_hand(self.w.pad), D(4))

    def test_same_key_with_a_different_quantity_is_rejected(self):
        key = uuid.uuid4()
        self.receive(self.order["id"], [{"order_line": self.line_id, "quantity": "4"}], key)
        clash = self.receive(self.order["id"], [{"order_line": self.line_id, "quantity": "5"}], key)
        self.assertEqual(
            (clash.status_code, clash.json()["error"]["code"]), (422, "idempotency_key_reused")
        )
        self.assertEqual(self.on_hand(self.w.pad), D(4))

    def test_the_restart_scenario(self):
        """The server committed, the answer never reached the tablet, the app restarted. It asks
        the operation-status endpoint for its saved key, finds the stored result, and a resend
        with the same key still produces exactly one delivery."""
        key = uuid.uuid4()
        lines = [{"order_line": self.line_id, "quantity": "6"}]
        self.receive(self.order["id"], lines, key)  # answer "lost": we ignore it
        status = self.w.api[Role.WAREHOUSE].get(f"{self.w.base}/operations/purchase_receive/{key}/")
        self.assertEqual(status.status_code, 200)
        self.assertEqual(status.json()["status"], "completed")
        self.assertEqual(status.json()["response"]["delivery_number"], 1)
        self.assertEqual(status.json()["response"]["order"]["status"], "partially_received")
        resend = self.receive(self.order["id"], lines, key)
        self.assertEqual(resend.json()["delivery"], status.json()["response"]["delivery"])
        self.assertEqual(Delivery.objects.count(), 1)
        self.assertEqual(self.on_hand(self.w.pad), D(6))

    def test_an_unknown_key_is_reported_as_not_completed(self):
        status = self.w.api[Role.WAREHOUSE].get(
            f"{self.w.base}/operations/purchase_receive/{uuid.uuid4()}/"
        )
        self.assertEqual(
            (status.status_code, status.json()["error"]["code"]), (404, "operation_not_found")
        )

    def test_a_refused_receipt_does_not_burn_the_key(self):
        key = uuid.uuid4()
        too_many = self.receive(
            self.order["id"], [{"order_line": self.line_id, "quantity": "11"}], key
        )
        self.assertEqual(too_many.status_code, 409)
        corrected = self.receive(
            self.order["id"], [{"order_line": self.line_id, "quantity": "10"}], key
        )
        self.assertEqual(corrected.status_code, 201)


class ReceivingConcurrencyTests(APITransactionTestCase):
    """Real commits and real threads against PostgreSQL."""

    def setUp(self):
        super().setUp()
        self.w = World()
        self.supplier = Supplier.objects.create(business=self.w.a, name="Parts")
        response = self.w.api[Role.OWNER].post(
            f"{self.w.base}/purchase-orders/",
            {
                "supplier": str(self.supplier.pk),
                "location": str(self.w.warehouse.pk),
                "lines": [{"product": str(self.w.pad.pk), "quantity": "10", "unit_cost": "50.00"}],
            },
            format="json",
        )
        self.order = response.json()
        self.w.api[Role.OWNER].post(f"{self.w.base}/purchase-orders/{self.order['id']}/submit/")
        self.line_id = self.order["lines"][0]["id"]

    def tearDown(self):
        self.assertEqual(ledger_differences(), [])
        super().tearDown()

    def receive(self, quantity, key):
        try:
            return client_for(self.w.users[Role.WAREHOUSE]).post(
                f"{self.w.base}/purchase-orders/{self.order['id']}/deliveries/",
                {"lines": [{"order_line": self.line_id, "quantity": str(quantity)}]},
                format="json",
                HTTP_IDEMPOTENCY_KEY=str(key),
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

    def test_eight_simultaneous_copies_of_one_receipt_produce_one_delivery(self):
        key = uuid.uuid4()
        responses = self.parallel([lambda: self.receive(4, key)] * 8)
        self.assertEqual({r.status_code for r in responses}, {201})
        self.assertEqual(Delivery.objects.count(), 1)
        self.assertEqual(StockBalance.objects.get().quantity, D(4))
        self.assertEqual(len({r.json()["delivery"] for r in responses}), 1)

    def test_simultaneous_different_receipts_cannot_exceed_the_order(self):
        """Six clerks each receive 3 of an order for 10, each with their own key."""
        responses = self.parallel([lambda: self.receive(3, uuid.uuid4()) for _ in range(6)])
        statuses = sorted(r.status_code for r in responses)
        self.assertEqual(statuses, [201, 201, 201, 409, 409, 409])
        self.assertEqual(StockBalance.objects.get().quantity, D(9))
        self.assertEqual(Delivery.objects.count(), 3)
        order = PurchaseOrder.objects.get()
        self.assertEqual(order.lines.get().received_quantity, D(9))
        self.assertEqual(order.status, "partially_received")
