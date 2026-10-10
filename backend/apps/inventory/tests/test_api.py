import uuid
from decimal import Decimal

from apps.audit.models import AuditEvent, IdempotencyRecord
from apps.businesses.models import Role
from apps.catalog.models import Product
from apps.common.testing import APITestCase
from apps.inventory.models import Condition, StockBalance, StockMovement

from .support import World, ledger_differences

D = Decimal


class ApiCase(APITestCase):
    def setUp(self):
        super().setUp()
        self.w = World()
        self.owner = self.w.api[Role.OWNER]

    def tearDown(self):
        self.assertEqual(ledger_differences(), [])
        super().tearDown()

    def post(self, path, body, key=None, client=None):
        key = key or uuid.uuid4()
        return (client or self.owner).post(
            f"{self.w.base}{path}", body, format="json", HTTP_IDEMPOTENCY_KEY=str(key)
        )

    def opening(self, lines, location=None, **extra):
        return self.post(
            "/stock/opening/",
            {"location": str((location or self.w.store).pk), "lines": lines, **extra},
        )

    def adjust(self, lines, reason="count correction", location=None, **extra):
        return self.post(
            "/stock/adjustments/",
            {"location": str((location or self.w.store).pk), "reason": reason, "lines": lines},
            **extra,
        )


class OpeningStockTests(ApiCase):
    def line(self, product=None, quantity="10", cost="50.00"):
        return {
            "product": str((product or self.w.pad).pk),
            "quantity": quantity,
            "unit_cost": cost,
        }

    def test_opening_stock_records_quantity_and_cost(self):
        response = self.opening([self.line(), self.line(self.w.oil, "12.5", "8.20")], note="Start")
        self.assertEqual(response.status_code, 201, response.content)
        body = response.json()
        self.assertEqual(len(body["movements"]), 2)
        self.assertEqual(StockBalance.objects.get(product=self.w.pad).quantity, D("10"))
        movement = StockMovement.objects.get(product=self.w.oil)
        self.assertEqual((movement.movement_type, movement.unit_cost), ("opening", D("8.20")))
        self.assertEqual(movement.actor, self.w.owner)
        self.assertEqual(movement.reason, "Start")
        self.assertEqual(
            AuditEvent.objects.filter(action="stock.opening_posted", business=self.w.a).count(), 1
        )

    def test_a_retry_with_the_same_key_posts_once(self):
        key = uuid.uuid4()
        body = {"location": str(self.w.store.pk), "lines": [self.line()]}
        first = self.post("/stock/opening/", body, key)
        second = self.post("/stock/opening/", body, key)
        self.assertEqual((first.status_code, second.status_code), (201, 201))
        self.assertEqual(first.json(), second.json())
        self.assertEqual(second["Idempotent-Replay"], "true")
        self.assertEqual(StockMovement.objects.count(), 1)
        self.assertEqual(StockBalance.objects.get().quantity, D("10"))

    def test_the_same_key_with_other_quantities_is_rejected(self):
        key = uuid.uuid4()
        self.post(
            "/stock/opening/", {"location": str(self.w.store.pk), "lines": [self.line()]}, key
        )
        clash = self.post(
            "/stock/opening/",
            {"location": str(self.w.store.pk), "lines": [self.line(quantity="99")]},
            key,
        )
        self.assertEqual(
            (clash.status_code, clash.json()["error"]["code"]), (422, "idempotency_key_reused")
        )
        self.assertEqual(StockBalance.objects.get().quantity, D("10"))

    def test_a_key_is_required(self):
        response = self.owner.post(
            f"{self.w.base}/stock/opening/",
            {"location": str(self.w.store.pk), "lines": [self.line()]},
            format="json",
        )
        self.assertEqual(response.json()["error"]["code"], "idempotency_key_required")
        self.assertEqual(StockMovement.objects.count(), 0)

    def test_opening_stock_is_only_for_a_product_with_no_history_there(self):
        self.assertEqual(self.opening([self.line()]).status_code, 201)
        again = self.opening([self.line()])
        self.assertEqual(
            (again.status_code, again.json()["error"]["code"]), (409, "opening_stock_exists")
        )
        self.assertEqual(StockMovement.objects.count(), 1)
        # another location is a different history
        self.assertEqual(self.opening([self.line()], location=self.w.warehouse).status_code, 201)

    def test_validation(self):
        cases = {
            "zero quantity": [self.line(quantity="0")],
            "negative quantity": [self.line(quantity="-1")],
            "no cost": [{"product": str(self.w.pad.pk), "quantity": "1"}],
            "negative cost": [self.line(cost="-1")],
            "fraction of a piece": [self.line(quantity="1.5")],
            "too many decimals": [self.line(self.w.oil, quantity="1.5555")],
            "no lines": [],
            "same product twice": [self.line(), self.line()],
            "other business's product": [self.line(self.w.b_product)],
        }
        for name, lines in cases.items():
            with self.subTest(name):
                response = self.opening(lines)
                self.assertEqual(response.status_code, 400, response.content)
        self.assertEqual(StockMovement.objects.count(), 0)

    def test_an_archived_product_cannot_be_stocked(self):
        Product.objects.filter(pk=self.w.pad.pk).update(is_active=False)
        response = self.opening([self.line()])
        self.assertEqual(
            (response.status_code, response.json()["error"]["code"]), (409, "product_archived")
        )

    def test_a_failed_line_posts_nothing_and_frees_the_key(self):
        key = uuid.uuid4()
        bad = {
            "location": str(self.w.store.pk),
            "lines": [self.line(), self.line(self.w.oil, quantity="1.5555")],
        }
        self.assertEqual(self.post("/stock/opening/", bad, key).status_code, 400)
        self.assertEqual(StockMovement.objects.count(), 0)
        self.assertEqual(IdempotencyRecord.objects.count(), 0)

    def test_roles_and_isolation(self):
        body = {"location": str(self.w.store.pk), "lines": [self.line()]}
        self.assertEqual(
            self.post("/stock/opening/", body, client=self.w.api[Role.MANAGER]).status_code, 201
        )
        for role in (Role.SALES, Role.WAREHOUSE):
            with self.subTest(role=role):
                response = self.post("/stock/opening/", body, client=self.w.api[role])
                self.assertEqual(response.status_code, 403)
        outsider = self.post("/stock/opening/", body, client=self.w.b_api)
        self.assertEqual(outsider.status_code, 404)  # business A does not exist for B's owner
        # a location from another business is not accepted from A's own owner
        foreign = self.post(
            "/stock/opening/",
            {"location": str(self.w.b_store.pk), "lines": [self.line()]},
        )
        self.assertEqual(foreign.status_code, 400)
        self.assertEqual(StockMovement.objects.count(), 1)


class AdjustmentTests(ApiCase):
    def setUp(self):
        super().setUp()
        self.w.stock(self.w.pad, self.w.store, 10, "50.00")
        self.w.stock(self.w.pad, self.w.store, 10, "60.00")

    def out(self, quantity, **extra):
        return {
            "product": str(self.w.pad.pk),
            "direction": "out",
            "quantity": str(quantity),
            **extra,
        }

    def test_a_write_off_uses_the_oldest_cost_and_records_the_reason(self):
        response = self.adjust([self.out(15)], reason="Water damage")
        self.assertEqual(response.status_code, 201, response.content)
        slices = [(m["quantity"], m["unit_cost"]) for m in response.json()["movements"]]
        self.assertEqual(slices, [("-10.000", "50.00"), ("-5.000", "60.00")])
        reasons = set(
            StockMovement.objects.filter(movement_type="adjustment_out").values_list(
                "reason", flat=True
            )
        )
        self.assertEqual(reasons, {"Water damage"})
        self.assertEqual(StockBalance.objects.get().quantity, D(5))

    def test_a_reason_is_mandatory(self):
        for reason in ("", "   "):
            with self.subTest(reason=reason):
                self.assertEqual(self.adjust([self.out(1)], reason=reason).status_code, 400)
        self.assertEqual(StockBalance.objects.get().quantity, D(20))

    def test_cannot_write_off_more_than_is_there(self):
        response = self.adjust([self.out(21)])
        self.assertEqual(
            (response.status_code, response.json()["error"]["code"]), (409, "insufficient_stock")
        )
        self.assertEqual(StockBalance.objects.get().quantity, D(20))

    def test_an_increase_needs_a_cost_and_creates_its_own_layer(self):
        missing = self.adjust([{"product": str(self.w.pad.pk), "direction": "in", "quantity": "2"}])
        self.assertEqual(missing.status_code, 400)
        ok = self.adjust(
            [{"product": str(self.w.pad.pk), "direction": "in", "quantity": "2", "unit_cost": "70"}]
        )
        self.assertEqual(ok.status_code, 201)
        self.assertEqual(StockBalance.objects.get().quantity, D(22))

    def test_damaged_goods_are_a_separate_balance(self):
        response = self.adjust(
            [
                {
                    "product": str(self.w.pad.pk),
                    "direction": "in",
                    "quantity": "3",
                    "unit_cost": "55",
                    "condition": "damaged",
                }
            ],
            reason="Found damaged on delivery",
        )
        self.assertEqual(response.status_code, 201)
        self.assertEqual(StockBalance.objects.get(condition=Condition.DAMAGED).quantity, D(3))
        self.assertEqual(StockBalance.objects.get(condition=Condition.SELLABLE).quantity, D(20))

    def test_in_transit_is_reserved_for_transfers(self):
        response = self.adjust(
            [
                {
                    "product": str(self.w.pad.pk),
                    "direction": "in",
                    "quantity": "1",
                    "unit_cost": "1",
                    "condition": "in_transit",
                }
            ]
        )
        self.assertEqual(response.status_code, 400)

    def test_a_retry_with_the_same_key_adjusts_once(self):
        key = uuid.uuid4()
        body = {"location": str(self.w.store.pk), "reason": "x", "lines": [self.out(4)]}
        self.post("/stock/adjustments/", body, key)
        again = self.post("/stock/adjustments/", body, key)
        self.assertEqual(again["Idempotent-Replay"], "true")
        self.assertEqual(StockBalance.objects.get().quantity, D(16))

    def test_only_owner_and_manager_may_adjust(self):
        body = {"location": str(self.w.store.pk), "reason": "x", "lines": [self.out(1)]}
        for role, expected in (
            (Role.OWNER, 201),
            (Role.MANAGER, 201),
            (Role.SALES, 403),
            (Role.WAREHOUSE, 403),
        ):
            with self.subTest(role=role):
                response = self.post("/stock/adjustments/", body, client=self.w.api[role])
                self.assertEqual(response.status_code, expected)
        self.assertEqual(
            self.post("/stock/adjustments/", body, client=self.w.b_api).status_code, 404
        )


class StockReadTests(ApiCase):
    def setUp(self):
        super().setUp()
        self.w.stock(self.w.pad, self.w.store, 10, "50.00")
        self.w.stock(self.w.pad, self.w.store, 10, "60.00")
        self.w.stock(self.w.oil, self.w.warehouse, "4.5", "8.00")
        self.w.stock(self.w.oil, self.w.store, "1", "8.00")
        self.w.remove(self.w.oil, self.w.store, "1")  # leaves a zero balance

    def stock(self, role=Role.OWNER, query=""):
        return self.w.api[role].get(f"{self.w.base}/stock/{query}")

    def test_owner_sees_quantities_and_the_value_from_the_cost_layers(self):
        rows = self.stock().json()["results"]
        self.assertEqual(len(rows), 2)  # the zero balance is hidden
        pad = next(r for r in rows if r["product"]["sku"] == "BP-1")
        self.assertEqual(pad["quantity"], "20.000")
        self.assertEqual(pad["value"], "1100.00")  # 10x50 + 10x60
        self.assertEqual(pad["average_cost"], "55.00")
        self.assertEqual(pad["product"]["unit"]["symbol"], "pc")
        zero = self.stock(query="?include_zero=1").json()["results"]
        self.assertEqual(len(zero), 3)

    def test_the_value_follows_fifo_after_a_sale(self):
        self.w.remove(self.w.pad, self.w.store, 12)
        pad = next(r for r in self.stock().json()["results"] if r["product"]["sku"] == "BP-1")
        self.assertEqual((pad["quantity"], pad["value"]), ("8.000", "480.00"))  # 8 x 60

    def test_the_warehouse_sees_quantities_without_any_cost(self):
        response = self.stock(Role.WAREHOUSE)
        self.assertEqual(response.status_code, 200)
        rows = response.json()["results"]
        self.assertEqual([r["product"]["sku"] for r in rows], ["OIL-1"])  # only their location
        self.assertNotIn("value", rows[0])
        self.assertNotIn("average_cost", rows[0])
        self.assertNotIn("unit_cost", str(rows))

    def test_sales_only_see_their_own_location(self):
        rows = self.stock(Role.SALES).json()["results"]
        self.assertEqual({r["location"]["name"] for r in rows}, {"A Store"})
        self.assertNotIn("value", rows[0])

    def test_filters(self):
        by_location = self.stock(query=f"?location={self.w.warehouse.pk}").json()["results"]
        self.assertEqual([r["product"]["sku"] for r in by_location], ["OIL-1"])
        by_search = self.stock(query="?q=brake").json()["results"]
        self.assertEqual([r["product"]["sku"] for r in by_search], ["BP-1"])

    def test_other_businesses_do_not_see_this_stock(self):
        self.assertEqual(self.w.b_api.get(f"{self.w.base}/stock/").status_code, 404)

    def test_movement_history_hides_costs_from_the_warehouse_and_is_closed_to_sales(self):
        owner = self.w.api[Role.OWNER].get(f"{self.w.base}/stock/movements/").json()
        self.assertEqual(owner["count"], 5)
        newest = owner["results"][0]
        self.assertEqual(newest["quantity"], "-1.000")
        self.assertEqual(newest["unit_cost"], "8.00")
        self.assertEqual(newest["actor"]["name"], "a-owner")
        warehouse = self.w.api[Role.WAREHOUSE].get(f"{self.w.base}/stock/movements/")
        self.assertEqual(warehouse.status_code, 200)
        self.assertEqual(
            {r["location"]["name"] for r in warehouse.json()["results"]}, {"A Warehouse"}
        )
        self.assertNotIn("unit_cost", str(warehouse.json()))
        self.assertEqual(
            self.w.api[Role.SALES].get(f"{self.w.base}/stock/movements/").status_code, 403
        )

    def test_movement_filters_and_there_is_no_way_to_change_the_history(self):
        pad = f"?product={self.w.pad.pk}"
        self.assertEqual(
            self.w.api[Role.OWNER].get(f"{self.w.base}/stock/movements/{pad}").json()["count"], 2
        )
        only_out = self.w.api[Role.OWNER].get(f"{self.w.base}/stock/movements/?type=adjustment_out")
        self.assertEqual(only_out.json()["count"], 1)
        for method in ("put", "patch", "delete", "post"):
            with self.subTest(method=method):
                response = getattr(self.w.api[Role.OWNER], method)(
                    f"{self.w.base}/stock/movements/", {}, format="json"
                )
                self.assertEqual(response.status_code, 405)
