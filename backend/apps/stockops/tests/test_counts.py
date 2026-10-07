import threading
import uuid
from concurrent.futures import ThreadPoolExecutor
from decimal import Decimal

from django.db import connections

from apps.businesses.models import Role
from apps.common.testing import APITestCase, APITransactionTestCase, client_for
from apps.inventory.models import CostLayer, StockBalance, StockMovement
from apps.inventory.tests.support import World, ledger_differences
from apps.stockops.models import StockCount

D = Decimal


def on_hand(product, location):
    row = StockBalance.objects.filter(
        product=product, location=location, condition="sellable"
    ).first()
    return row.quantity if row else D(0)


class CountCase(APITestCase):
    def setUp(self):
        super().setUp()
        self.w = World()
        self.owner = self.w.api[Role.OWNER]
        self.manager = self.w.api[Role.MANAGER]
        self.keeper = self.w.api[Role.WAREHOUSE]  # counts at A Warehouse only
        self.w.stock(self.w.pad, self.w.warehouse, 10, "50.00")
        self.w.stock(self.w.oil, self.w.warehouse, 20, "8.00")

    def tearDown(self):
        self.assertEqual(ledger_differences(), [])
        super().tearDown()

    def url(self, count, tail=""):
        return f"{self.w.base}/counts/{count['id']}/{tail}"

    def start(self, *, client=None, location=None, scope="full", products=None):
        body = {"location": str((location or self.w.warehouse).pk), "scope": scope}
        if products is not None:
            body["products"] = [str(p.pk) for p in products]
        return (client or self.keeper).post(f"{self.w.base}/counts/", body, format="json")

    def started(self, **kwargs):
        response = self.start(**kwargs)
        self.assertEqual(response.status_code, 201, response.content)
        return response.json()

    def enter(self, count, counted, *, client=None):
        """counted: {product: quantity}"""
        return (client or self.keeper).put(
            self.url(count, "lines/"),
            {
                "lines": [
                    {"product": str(p.pk), "counted_quantity": str(q)} for p, q in counted.items()
                ]
            },
            format="json",
        )

    def post(self, count, tail, body=None, *, client=None, key=None):
        return (client or self.owner).post(
            self.url(count, tail),
            body or {},
            format="json",
            **({"HTTP_IDEMPOTENCY_KEY": str(key or uuid.uuid4())} if tail == "approve/" else {}),
        )

    def counted(self, count, counted, *, submit=True):
        self.assertEqual(self.enter(count, counted).status_code, 200)
        if submit:
            self.assertEqual(self.post(count, "submit/", client=self.keeper).status_code, 200)

    def line(self, count, product):
        data = self.owner.get(self.url(count)).json()
        return next(row for row in data["lines"] if row["product"]["id"] == str(product.pk))

    def sell(self, product, quantity):
        response = self.owner.post(
            f"{self.w.base}/sales/",
            {
                "location": str(self.w.warehouse.pk),
                "lines": [
                    {"product": str(product.pk), "quantity": str(quantity), "unit_price": "10"}
                ],
            },
            format="json",
            HTTP_IDEMPOTENCY_KEY=str(uuid.uuid4()),
        )
        self.assertEqual(response.status_code, 201, response.content)


class StartAndEnterTests(CountCase):
    def test_a_full_count_lists_what_the_system_has_with_its_baseline(self):
        count = self.started()
        self.assertEqual((count["number"], count["status"], count["scope"]), (1, "open", "full"))
        rows = {r["product"]["sku"]: r for r in count["lines"]}
        self.assertEqual(set(rows), {"BP-1", "OIL-1"})
        self.assertEqual(rows["BP-1"]["baseline_quantity"], "10.000")
        self.assertIsNone(rows["BP-1"]["counted_quantity"])
        self.assertIsNone(rows["BP-1"]["variance"])

    def test_products_with_no_stock_are_not_listed_but_can_be_added(self):
        extra = self.w.pad.__class__.objects.create(
            business=self.w.a, sku="X-1", name="Extra", unit=self.w.unit, price_amount=D(5)
        )
        count = self.started()
        self.assertNotIn("X-1", {r["product"]["sku"] for r in count["lines"]})
        self.assertEqual(self.enter(count, {extra: 3}).status_code, 200)
        row = self.line(count, extra)
        self.assertEqual((row["baseline_quantity"], row["counted_quantity"]), ("0.000", "3.000"))

    def test_a_partial_count_covers_only_the_chosen_products(self):
        count = self.started(scope="partial", products=[self.w.oil])
        self.assertEqual([r["product"]["sku"] for r in count["lines"]], ["OIL-1"])
        self.assertEqual(self.start(scope="partial").status_code, 400)  # no products chosen
        self.assertEqual(self.start(scope="partial", products=[]).status_code, 400)

    def test_counted_quantities_are_validated(self):
        count = self.started()
        for counted in ({self.w.pad: "1.5"}, {self.w.pad: "-1"}):
            with self.subTest(counted=counted):
                self.assertEqual(self.enter(count, counted).status_code, 400)
        self.assertEqual(self.enter(count, {self.w.b_product: 1}).status_code, 400)
        self.assertIsNone(self.line(count, self.w.pad)["counted_quantity"])

    def test_entries_can_be_corrected_until_the_count_is_submitted(self):
        count = self.started()
        self.enter(count, {self.w.pad: 9})
        self.enter(count, {self.w.pad: 8})
        self.assertEqual(self.line(count, self.w.pad)["counted_quantity"], "8.000")
        self.post(count, "submit/", client=self.keeper)
        late = self.enter(count, {self.w.pad: 7})
        self.assertEqual((late.status_code, late.json()["error"]["code"]), (409, "count_not_open"))

    def test_nothing_to_submit_until_something_is_counted(self):
        count = self.started()
        response = self.post(count, "submit/", client=self.keeper)
        self.assertEqual(
            (response.status_code, response.json()["error"]["code"]), (409, "count_empty")
        )

    def test_who_may_count_where(self):
        self.assertEqual(self.start(client=self.w.api[Role.SALES]).status_code, 403)
        denied = self.start(location=self.w.store)  # the keeper works at the warehouse
        self.assertEqual(
            (denied.status_code, denied.json()["error"]["code"]), (403, "location_not_permitted")
        )
        self.assertEqual(self.start(location=self.w.store, client=self.manager).status_code, 201)
        self.assertEqual(self.start(client=self.w.b_api).status_code, 404)
        self.w.warehouse.is_active = False
        self.w.warehouse.save()
        self.assertEqual(self.start(client=self.owner).status_code, 409)


class ApprovalTests(CountCase):
    def test_approving_posts_the_differences_as_adjustments(self):
        count = self.started()
        self.counted(count, {self.w.pad: 8, self.w.oil: "21"})
        self.assertEqual(self.line(count, self.w.pad)["variance"], "-2.000")
        response = self.post(count, "approve/", {"reason": "Two pads were broken"})
        self.assertEqual(response.status_code, 200, response.content)
        done = response.json()
        self.assertEqual(
            (done["status"], done["decision_reason"]), ("approved", "Two pads were broken")
        )
        self.assertEqual(done["decided_by"]["name"], "a-owner")
        self.assertEqual(on_hand(self.w.pad, self.w.warehouse), D(8))
        self.assertEqual(on_hand(self.w.oil, self.w.warehouse), D(21))
        moves = StockMovement.objects.filter(document_type="count", document_id=count["id"])
        self.assertEqual(
            sorted((m.movement_type, m.quantity) for m in moves),
            [("adjustment_in", D(1)), ("adjustment_out", D(-2))],
        )
        self.assertTrue(all("C-0001" in m.reason and "Two pads" in m.reason for m in moves))

    def test_goods_found_that_the_system_did_not_know_cost_what_the_latest_layer_cost(self):
        self.w.stock(self.w.oil, self.w.warehouse, 5, "9.50")  # the latest layer here
        count = self.started()
        self.counted(count, {self.w.oil: 30})  # baseline 25
        self.post(count, "approve/", {"reason": "Found a box"})
        newest = (
            CostLayer.objects.filter(balance__product=self.w.oil).order_by("-created_at").first()
        )
        self.assertEqual((newest.unit_cost, newest.quantity_initial), (D("9.50"), D(5)))

    def test_an_explanation_is_needed_when_something_differs(self):
        count = self.started()
        self.counted(count, {self.w.pad: 9})
        for body in ({}, {"reason": "  "}):
            self.assertEqual(self.post(count, "approve/", body).status_code, 400)
        self.assertEqual(on_hand(self.w.pad, self.w.warehouse), D(10))
        self.assertEqual(StockCount.objects.get().status, "submitted")

    def test_a_count_with_no_differences_needs_no_reason_and_posts_nothing(self):
        count = self.started()
        self.counted(count, {self.w.pad: 10, self.w.oil: 20})
        response = self.post(count, "approve/")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(StockMovement.objects.filter(document_type="count").count(), 0)

    def test_products_nobody_counted_are_left_alone(self):
        count = self.started()
        self.counted(count, {self.w.pad: 9})  # the oil was not counted
        self.post(count, "approve/", {"reason": "Lost one"})
        self.assertEqual(on_hand(self.w.oil, self.w.warehouse), D(20))

    def test_only_an_approver_approves_and_only_once(self):
        count = self.started()
        self.counted(count, {self.w.pad: 9})
        self.assertEqual(
            self.post(count, "approve/", {"reason": "x"}, client=self.keeper).status_code, 403
        )
        self.assertEqual(
            self.post(
                count, "approve/", {"reason": "x"}, client=self.w.api[Role.SALES]
            ).status_code,
            403,
        )
        self.assertEqual(
            self.post(count, "approve/", {"reason": "x"}, client=self.w.b_api).status_code, 404
        )
        self.assertEqual(
            self.post(count, "approve/", {"reason": "ok"}, client=self.manager).status_code, 200
        )
        again = self.post(count, "approve/", {"reason": "ok"})
        self.assertEqual(
            (again.status_code, again.json()["error"]["code"]), (409, "count_not_submitted")
        )
        self.assertEqual(on_hand(self.w.pad, self.w.warehouse), D(9))

    def test_an_open_count_cannot_be_approved(self):
        count = self.started()
        response = self.post(count, "approve/", {"reason": "x"})
        self.assertEqual(response.json()["error"]["code"], "count_not_submitted")


class DuringACountTests(CountCase):
    def test_sales_during_a_count_are_kept_and_the_line_is_flagged(self):
        count = self.started()  # the system said 10
        self.sell(self.w.pad, 3)  # a sale while the keeper is counting: now 7
        self.counted(count, {self.w.pad: 9})  # the keeper found 9 against the 10 shown
        row = self.line(count, self.w.pad)
        self.assertEqual((row["baseline_quantity"], row["variance"]), ("10.000", "-1.000"))
        self.assertTrue(row["moved_since_start"])
        self.assertFalse(self.line(count, self.w.oil)["moved_since_start"])
        self.post(count, "approve/", {"reason": "One missing"})
        self.assertEqual(on_hand(self.w.pad, self.w.warehouse), D(6))  # 7 - 1: the sale stays

    def test_a_product_added_during_the_count_gets_its_start_of_count_baseline(self):
        count = self.started()
        self.w.stock(self.w.oil, self.w.warehouse, 4, "8.00")  # receipt after the start: now 24
        self.enter(count, {self.w.oil: 20})
        self.assertEqual(self.line(count, self.w.oil)["baseline_quantity"], "20.000")

    def test_the_approval_is_refused_if_the_goods_were_sold_meanwhile(self):
        count = self.started()
        self.counted(count, {self.w.pad: 4})  # 6 fewer than shown
        self.sell(self.w.pad, 8)  # only 2 are left now
        response = self.post(count, "approve/", {"reason": "Missing"})
        self.assertEqual(
            (response.status_code, response.json()["error"]["code"]), (409, "insufficient_stock")
        )
        self.assertEqual(on_hand(self.w.pad, self.w.warehouse), D(2))  # nothing was posted
        self.assertEqual(StockCount.objects.get().status, "submitted")
        self.assertEqual(self.post(count, "cancel/", {"reason": "Recount"}).status_code, 200)


class CancelAndReadTests(CountCase):
    def test_an_open_or_submitted_count_can_be_cancelled_but_not_a_closed_one(self):
        first = self.started()
        self.assertEqual(
            self.post(first, "cancel/", {"reason": "Wrong shelf"}).json()["status"], "cancelled"
        )
        second = self.started()
        self.counted(second, {self.w.pad: 10})
        self.assertEqual(self.post(second, "cancel/", client=self.keeper).status_code, 200)
        third = self.started()
        self.counted(third, {self.w.pad: 10})
        self.post(third, "approve/")
        self.assertEqual(
            self.post(third, "cancel/").json()["error"]["code"], "count_not_cancellable"
        )
        self.assertEqual(on_hand(self.w.pad, self.w.warehouse), D(10))

    def test_lists_details_and_isolation(self):
        count = self.started()
        self.enter(count, {self.w.pad: 9})
        row = self.keeper.get(f"{self.w.base}/counts/").json()["results"][0]
        self.assertEqual(
            (row["number"], row["line_count"], row["counted_count"], row["difference_count"]),
            (1, 2, 1, 1),
        )
        self.assertEqual(self.keeper.get(f"{self.w.base}/counts/?status=open").json()["count"], 1)
        self.assertEqual(
            self.keeper.get(f"{self.w.base}/counts/?status=approved").json()["count"], 0
        )
        # a count at the store is invisible to the warehouse keeper
        self.w.stock(self.w.pad, self.w.store, 1, "50.00")
        other = self.started(location=self.w.store, client=self.owner)
        self.assertEqual(self.keeper.get(self.url(other)).status_code, 404)
        self.assertEqual(self.keeper.get(f"{self.w.base}/counts/").json()["count"], 1)
        self.assertEqual(self.w.api[Role.SALES].get(f"{self.w.base}/counts/").status_code, 403)
        self.assertEqual(self.w.b_api.get(self.url(count)).status_code, 404)


class RetryTests(CountCase):
    def test_the_same_key_approves_once(self):
        count = self.started()
        self.counted(count, {self.w.pad: 8})
        key = uuid.uuid4()
        first = self.post(count, "approve/", {"reason": "Two broken"}, key=key)
        second = self.post(count, "approve/", {"reason": "Two broken"}, key=key)
        self.assertEqual((first.status_code, second.status_code), (200, 200))
        self.assertEqual(second["Idempotent-Replay"], "true")
        self.assertEqual(on_hand(self.w.pad, self.w.warehouse), D(8))

    def test_the_restart_scenario(self):
        count = self.started()
        self.counted(count, {self.w.pad: 8})
        key = uuid.uuid4()
        self.post(count, "approve/", {"reason": "Two broken"}, key=key)  # the answer is "lost"
        status = self.owner.get(f"{self.w.base}/operations/count_approve/{key}/")
        self.assertEqual(status.json()["response"]["status"], "approved")
        self.post(count, "approve/", {"reason": "Two broken"}, key=key)
        self.assertEqual(on_hand(self.w.pad, self.w.warehouse), D(8))


class CountConcurrencyTests(APITransactionTestCase):
    def setUp(self):
        super().setUp()
        self.w = World()
        self.w.stock(self.w.pad, self.w.warehouse, 10, "50.00")

    def tearDown(self):
        self.assertEqual(ledger_differences(), [])
        super().tearDown()

    def call(self, method, path, body=None, user=Role.OWNER, key=None):
        try:
            return getattr(client_for(self.w.users[user]), method)(
                f"{self.w.base}/{path}",
                body or {},
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

    def submitted_count(self, counted):
        count = self.call(
            "post", "counts/", {"location": str(self.w.warehouse.pk), "scope": "full"}
        ).json()
        self.call(
            "put",
            f"counts/{count['id']}/lines/",
            {"lines": [{"product": str(self.w.pad.pk), "counted_quantity": str(counted)}]},
        )
        self.call("post", f"counts/{count['id']}/submit/")
        return count

    def test_eight_copies_of_one_approval_post_the_differences_once(self):
        count = self.submitted_count(7)
        key = uuid.uuid4()
        path = f"counts/{count['id']}/approve/"
        responses = self.parallel(
            [lambda: self.call("post", path, {"reason": "Three broken"}, key=key) for _ in range(8)]
        )
        self.assertEqual({r.status_code for r in responses}, {200})
        self.assertEqual(
            StockBalance.objects.get(product=self.w.pad, location=self.w.warehouse).quantity, D(7)
        )

    def test_two_approvers_at_once_only_one_posts(self):
        count = self.submitted_count(7)
        path = f"counts/{count['id']}/approve/"
        responses = self.parallel(
            [
                lambda: self.call("post", path, {"reason": "A"}),
                lambda: self.call("post", path, {"reason": "B"}, user=Role.MANAGER),
            ]
        )
        self.assertEqual(sorted(r.status_code for r in responses), [200, 409])
        self.assertEqual(
            StockBalance.objects.get(product=self.w.pad, location=self.w.warehouse).quantity, D(7)
        )
