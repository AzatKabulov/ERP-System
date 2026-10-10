import threading
import uuid
from concurrent.futures import ThreadPoolExecutor
from decimal import Decimal

from django.db import connections

from apps.audit.models import AuditEvent
from apps.businesses.models import Role
from apps.common.testing import APITestCase, APITransactionTestCase, client_for
from apps.inventory.models import CostLayer, StockBalance, StockMovement
from apps.inventory.tests.support import World, ledger_differences
from apps.stockops.models import Transfer

D = Decimal


def quantity(product, location, condition="sellable"):
    row = StockBalance.objects.filter(
        product=product, location=location, condition=condition
    ).first()
    return row.quantity if row else D(0)


class TransferCase(APITestCase):
    def setUp(self):
        super().setUp()
        self.w = World()
        self.owner = self.w.api[Role.OWNER]
        self.warehouse_user = self.w.api[Role.WAREHOUSE]  # works at A Warehouse only
        self.w.stock(self.w.pad, self.w.warehouse, 10, "50.00")
        self.w.stock(self.w.pad, self.w.warehouse, 10, "60.00")  # two layers, oldest first

    def tearDown(self):
        self.assertEqual(ledger_differences(), [])  # includes the transfers' own check
        super().tearDown()

    @staticmethod
    def line(product, quantity=1):
        return {"product": str(product.pk), "quantity": str(quantity)}

    def send(self, lines=None, *, client=None, source=None, destination=None, key=None, **extra):
        return (client or self.warehouse_user).post(
            f"{self.w.base}/transfers/",
            {
                "from_location": str((source or self.w.warehouse).pk),
                "to_location": str((destination or self.w.store).pk),
                "lines": lines if lines is not None else [self.line(self.w.pad, 15)],
                **extra,
            },
            format="json",
            HTTP_IDEMPOTENCY_KEY=str(key or uuid.uuid4()),
        )

    def sent(self, **kwargs):
        response = self.send(**kwargs)
        self.assertEqual(response.status_code, 201, response.content)
        return response.json()

    def act(self, transfer, action, body=None, *, client=None, key=None):
        return (client or self.owner).post(
            f"{self.w.base}/transfers/{transfer['id']}/{action}/",
            body or {},
            format="json",
            HTTP_IDEMPOTENCY_KEY=str(key or uuid.uuid4()),
        )

    def layers(self, product, location, condition):
        return [
            (layer.unit_cost, layer.quantity_remaining)
            for layer in CostLayer.objects.filter(
                balance__product=product, balance__location=location, balance__condition=condition
            ).order_by("layer_no")
        ]


class DispatchTests(TransferCase):
    def test_goods_leave_the_source_and_wait_in_transit_at_the_destination(self):
        transfer = self.sent()
        self.assertEqual((transfer["number"], transfer["status"]), (1, "dispatched"))
        self.assertEqual(transfer["from_location"]["name"], "A Warehouse")
        self.assertEqual(quantity(self.w.pad, self.w.warehouse), D(5))
        self.assertEqual(quantity(self.w.pad, self.w.store), D(0))  # not sellable there yet
        self.assertEqual(quantity(self.w.pad, self.w.store, "in_transit"), D(15))
        self.assertEqual(transfer["lines"][0]["received_quantity"], None)
        self.assertEqual(
            AuditEvent.objects.filter(action="transfer.dispatched", business=self.w.a).count(), 1
        )

    def test_the_cost_layers_travel_with_the_goods(self):
        self.sent()  # 15 of 10 @50 + 10 @60: takes 10 @50 and 5 @60
        self.assertEqual(
            self.layers(self.w.pad, self.w.store, "in_transit"),
            [(D("50.00"), D(10)), (D("60.00"), D(5))],
        )
        self.assertEqual(
            self.layers(self.w.pad, self.w.warehouse, "sellable")[-1], (D("60.00"), D(5))
        )

    def test_goods_in_transit_cannot_be_sold_at_the_destination(self):
        self.sent()
        sale = self.owner.post(
            f"{self.w.base}/sales/",
            {
                "location": str(self.w.store.pk),
                "lines": [{"product": str(self.w.pad.pk), "quantity": "1", "unit_price": "100"}],
            },
            format="json",
            HTTP_IDEMPOTENCY_KEY=str(uuid.uuid4()),
        )
        self.assertEqual(
            (sale.status_code, sale.json()["error"]["code"]), (409, "insufficient_stock")
        )

    def test_more_than_there_is_is_refused_and_changes_nothing(self):
        response = self.send(lines=[self.line(self.w.pad, 21)])
        self.assertEqual(
            (response.status_code, response.json()["error"]["code"]), (409, "insufficient_stock")
        )
        self.assertEqual(Transfer.objects.count(), 0)
        self.assertEqual(quantity(self.w.pad, self.w.warehouse), D(20))

    def test_numbers_have_no_gaps_after_a_refusal(self):
        self.sent(lines=[self.line(self.w.pad, 1)])
        self.send(lines=[self.line(self.w.pad, 99)])
        self.assertEqual(self.sent(lines=[self.line(self.w.pad, 1)])["number"], 2)

    def test_input_is_validated(self):
        cases = {
            "same place": dict(destination=self.w.warehouse),
            "no lines": dict(lines=[]),
            "same product twice": dict(lines=[self.line(self.w.pad), self.line(self.w.pad)]),
            "zero quantity": dict(lines=[self.line(self.w.pad, 0)]),
            "fraction of a piece": dict(lines=[self.line(self.w.pad, "1.5")]),
            "another business's product": dict(lines=[self.line(self.w.b_product)]),
            "another business's place": dict(destination=self.w.b_store),
        }
        for name, kwargs in cases.items():
            with self.subTest(name):
                self.assertEqual(self.send(**kwargs).status_code, 400)
        self.assertEqual(Transfer.objects.count(), 0)

    def test_an_archived_product_or_an_inactive_destination_is_refused(self):
        self.w.pad.is_active = False
        self.w.pad.save()
        self.assertEqual(self.send().json()["error"]["code"], "product_archived")
        self.w.pad.is_active = True
        self.w.pad.save()
        self.w.store.is_active = False
        self.w.store.save()
        self.assertEqual(self.send().json()["error"]["code"], "location_inactive")

    def test_who_may_send_from_where(self):
        self.assertEqual(self.send(client=self.w.api[Role.SALES]).status_code, 403)
        # the warehouse user works at the warehouse only: they cannot send from the store
        self.w.stock(self.w.pad, self.w.store, 3, "50.00")
        denied = self.send(source=self.w.store, destination=self.w.warehouse)
        self.assertEqual(
            (denied.status_code, denied.json()["error"]["code"]), (403, "location_not_permitted")
        )
        self.assertEqual(
            self.send(
                source=self.w.store,
                destination=self.w.warehouse,
                client=self.owner,
                lines=[self.line(self.w.pad, 1)],
            ).status_code,
            201,
        )
        self.assertEqual(self.send(client=self.w.b_api).status_code, 404)

    def test_no_cost_appears_in_a_transfer(self):
        text = str(self.sent())
        self.assertNotIn("unit_cost", text)
        self.assertNotIn("50.00", text)


class ReceiveTests(TransferCase):
    def test_receiving_in_full_makes_the_goods_sellable_with_their_costs(self):
        transfer = self.sent()
        response = self.act(transfer, "receive")
        self.assertEqual(response.status_code, 200, response.content)
        done = response.json()
        self.assertEqual(done["status"], "received")
        self.assertEqual(done["lines"][0]["received_quantity"], "15.000")
        self.assertEqual(quantity(self.w.pad, self.w.store), D(15))
        self.assertEqual(quantity(self.w.pad, self.w.store, "in_transit"), D(0))
        self.assertEqual(
            self.layers(self.w.pad, self.w.store, "sellable"),
            [(D("50.00"), D(10)), (D("60.00"), D(5))],
        )
        self.assertEqual(done["received_by"]["name"], "a-owner")

    def test_what_arrives_can_be_sold_at_the_destination_afterwards(self):
        self.act(self.sent(), "receive")
        sale = self.owner.post(
            f"{self.w.base}/sales/",
            {
                "location": str(self.w.store.pk),
                "lines": [{"product": str(self.w.pad.pk), "quantity": "12", "unit_price": "100"}],
            },
            format="json",
            HTTP_IDEMPOTENCY_KEY=str(uuid.uuid4()),
        )
        self.assertEqual(sale.status_code, 201, sale.content)

    def test_arriving_short_needs_a_reason_and_writes_the_missing_goods_off(self):
        transfer = self.sent()
        line = transfer["lines"][0]["id"]
        no_reason = self.act(transfer, "receive", {"lines": [{"line": line, "quantity": "12"}]})
        self.assertEqual(no_reason.status_code, 400)
        self.assertIn("reason", no_reason.json()["error"]["fields"])
        self.assertEqual(quantity(self.w.pad, self.w.store, "in_transit"), D(15))  # nothing changed
        response = self.act(
            transfer,
            "receive",
            {"lines": [{"line": line, "quantity": "12"}], "reason": "Box damaged on the road"},
        )
        done = response.json()
        self.assertEqual(done["status"], "partially_received")
        self.assertEqual(done["discrepancy_reason"], "Box damaged on the road")
        self.assertEqual(quantity(self.w.pad, self.w.store), D(12))
        self.assertEqual(quantity(self.w.pad, self.w.store, "in_transit"), D(0))
        losses = StockMovement.objects.filter(movement_type="transfer_loss")
        self.assertEqual(sum(-m.quantity for m in losses), D(3))
        self.assertTrue(all(m.reason == "Box damaged on the road" for m in losses))

    def test_nothing_arrived_at_all(self):
        transfer = self.sent(lines=[self.line(self.w.pad, 4)])
        line = transfer["lines"][0]["id"]
        response = self.act(
            transfer, "receive", {"lines": [{"line": line, "quantity": "0"}], "reason": "Lost"}
        )
        self.assertEqual(response.json()["status"], "partially_received")
        self.assertEqual(quantity(self.w.pad, self.w.store), D(0))

    def test_cannot_receive_more_than_was_sent_or_an_unknown_line(self):
        transfer = self.sent()
        line = transfer["lines"][0]["id"]
        for lines in (
            [{"line": line, "quantity": "16"}],
            [{"line": str(uuid.uuid4()), "quantity": "1"}],
            [{"line": line, "quantity": "5"}, {"line": line, "quantity": "5"}],
            [{"line": line, "quantity": "-1"}],
        ):
            with self.subTest(lines=lines):
                response = self.act(transfer, "receive", {"lines": lines, "reason": "x"})
                self.assertEqual(response.status_code, 400)
        self.assertEqual(quantity(self.w.pad, self.w.store, "in_transit"), D(15))

    def test_only_somebody_at_the_destination_may_receive(self):
        transfer = self.sent()  # warehouse -> store; the warehouse user works at the warehouse
        denied = self.act(transfer, "receive", client=self.warehouse_user)
        self.assertEqual(
            (denied.status_code, denied.json()["error"]["code"]), (403, "location_not_permitted")
        )
        self.assertEqual(
            self.act(transfer, "receive", client=self.w.api[Role.SALES]).status_code, 403
        )
        self.assertEqual(self.act(transfer, "receive", client=self.w.b_api).status_code, 404)
        self.assertEqual(self.act(transfer, "receive", client=self.owner).status_code, 200)

    def test_a_transfer_is_received_once(self):
        transfer = self.sent()
        self.act(transfer, "receive")
        again = self.act(transfer, "receive")
        self.assertEqual(
            (again.status_code, again.json()["error"]["code"]), (409, "transfer_not_receivable")
        )
        self.assertEqual(quantity(self.w.pad, self.w.store), D(15))


class CancelTests(TransferCase):
    def test_cancelling_sends_everything_back_with_its_costs(self):
        transfer = self.sent()
        response = self.act(
            transfer, "cancel", {"reason": "Wrong shop"}, client=self.warehouse_user
        )
        self.assertEqual(response.status_code, 200, response.content)
        self.assertEqual(response.json()["status"], "cancelled")
        self.assertEqual(response.json()["cancel_reason"], "Wrong shop")
        self.assertEqual(quantity(self.w.pad, self.w.warehouse), D(20))
        self.assertEqual(quantity(self.w.pad, self.w.store, "in_transit"), D(0))
        self.assertEqual(
            self.layers(self.w.pad, self.w.warehouse, "sellable"),
            [(D("50.00"), D(0)), (D("60.00"), D(5)), (D("50.00"), D(10)), (D("60.00"), D(5))],
        )

    def test_cancelling_needs_a_reason_and_a_transfer_still_in_transit(self):
        transfer = self.sent()
        self.assertEqual(self.act(transfer, "cancel", {"reason": " "}).status_code, 400)
        self.act(transfer, "receive")
        late = self.act(transfer, "cancel", {"reason": "Too late"})
        self.assertEqual(
            (late.status_code, late.json()["error"]["code"]), (409, "transfer_not_cancellable")
        )

    def test_a_cancelled_transfer_cannot_be_received(self):
        transfer = self.sent()
        self.act(transfer, "cancel", {"reason": "Mistake"})
        response = self.act(transfer, "receive")
        self.assertEqual(response.json()["error"]["code"], "transfer_not_receivable")

    def test_only_the_sending_side_may_cancel(self):
        self.w.stock(self.w.pad, self.w.store, 2, "50.00")
        transfer = self.sent(
            source=self.w.store,
            destination=self.w.warehouse,
            client=self.owner,
            lines=[self.line(self.w.pad, 1)],
        )
        # the warehouse user is at the destination, not the sender
        denied = self.act(transfer, "cancel", {"reason": "No"}, client=self.warehouse_user)
        self.assertEqual(denied.status_code, 403)
        self.assertEqual(self.act(transfer, "cancel", {"reason": "Yes"}).status_code, 200)


class ReadingTests(TransferCase):
    def setUp(self):
        super().setUp()
        self.w.stock(self.w.pad, self.w.store, 5, "50.00")
        self.first = self.sent(lines=[self.line(self.w.pad, 2)])  # warehouse -> store
        self.second = self.sent(
            source=self.w.store,
            destination=self.w.warehouse,
            client=self.owner,
            lines=[self.line(self.w.pad, 1)],
        )  # store -> warehouse

    def listing(self, client, query=""):
        return client.get(f"{self.w.base}/transfers/{query}").json()

    def test_lists_and_filters(self):
        self.assertEqual([t["number"] for t in self.listing(self.owner)["results"]], [2, 1])
        self.assertEqual(self.listing(self.owner, "?status=dispatched")["count"], 2)
        self.assertEqual(self.listing(self.owner, "?status=received")["count"], 0)
        for text in ("T-0002", "2", "t-0002"):
            self.assertEqual(
                [t["number"] for t in self.listing(self.owner, f"?q={text}")["results"]], [2]
            )
        self.assertEqual(self.listing(self.owner, "?q=nonsense")["count"], 0)
        row = self.listing(self.owner)["results"][0]
        self.assertEqual((row["line_count"], row["status"]), (1, "dispatched"))

    def test_a_location_user_sees_transfers_into_and_out_of_their_place(self):
        self.assertEqual(self.listing(self.warehouse_user)["count"], 2)  # both touch the warehouse
        detail = self.warehouse_user.get(f"{self.w.base}/transfers/{self.first['id']}/")
        self.assertEqual(detail.status_code, 200)

    def test_denied_to_sales_and_other_businesses(self):
        self.assertEqual(self.w.api[Role.SALES].get(f"{self.w.base}/transfers/").status_code, 403)
        self.assertEqual(self.w.b_api.get(f"{self.w.base}/transfers/").status_code, 404)
        self.assertEqual(
            self.w.b_api.get(f"{self.w.base}/transfers/{self.first['id']}/").status_code, 404
        )


class RetryTests(TransferCase):
    def test_same_key_replays_the_same_transfer(self):
        key = uuid.uuid4()
        first, second = self.send(key=key), self.send(key=key)
        self.assertEqual((first.status_code, second.status_code), (201, 201))
        self.assertEqual(first.json(), second.json())
        self.assertEqual(second["Idempotent-Replay"], "true")
        self.assertEqual(Transfer.objects.count(), 1)
        self.assertEqual(quantity(self.w.pad, self.w.warehouse), D(5))

    def test_same_key_with_another_transfer_is_refused(self):
        key = uuid.uuid4()
        self.send(key=key)
        clash = self.send(key=key, lines=[self.line(self.w.pad, 2)])
        self.assertEqual(clash.status_code, 422)

    def test_the_restart_scenario_for_receiving(self):
        transfer = self.sent()
        key = uuid.uuid4()
        self.act(transfer, "receive", key=key)  # the answer is "lost"
        status = self.owner.get(f"{self.w.base}/operations/transfer_receive/{key}/")
        self.assertEqual(status.status_code, 200)
        self.assertEqual(status.json()["response"]["status"], "received")
        resend = self.act(transfer, "receive", key=key)
        self.assertEqual(resend.status_code, 200)
        self.assertEqual(quantity(self.w.pad, self.w.store), D(15))


class TransferConcurrencyTests(APITransactionTestCase):
    """Real commits and real threads against PostgreSQL."""

    def setUp(self):
        super().setUp()
        self.w = World()
        self.w.stock(self.w.pad, self.w.warehouse, 5, "50.00")

    def tearDown(self):
        self.assertEqual(ledger_differences(), [])
        super().tearDown()

    def call(self, path, body, user=Role.OWNER, key=None):
        try:
            return client_for(self.w.users[user]).post(
                f"{self.w.base}/{path}",
                body,
                format="json",
                HTTP_IDEMPOTENCY_KEY=str(key or uuid.uuid4()),
            )
        finally:
            connections.close_all()

    def send(self, quantity, key=None):
        return self.call(
            "transfers/",
            {
                "from_location": str(self.w.warehouse.pk),
                "to_location": str(self.w.store.pk),
                "lines": [{"product": str(self.w.pad.pk), "quantity": str(quantity)}],
            },
            key=key,
        )

    def parallel(self, calls):
        barrier = threading.Barrier(len(calls))

        def worker(call):
            barrier.wait(timeout=10)
            return call()

        with ThreadPoolExecutor(max_workers=len(calls)) as pool:
            return list(pool.map(worker, calls))

    def test_two_tablets_sending_the_last_unit_only_one_transfer_happens(self):
        self.w.remove(self.w.pad, self.w.warehouse, 4)  # one left
        responses = self.parallel([lambda: self.send(1), lambda: self.send(1)])
        self.assertEqual(sorted(r.status_code for r in responses), [201, 409])
        self.assertEqual(Transfer.objects.count(), 1)
        self.assertEqual(quantity(self.w.pad, self.w.warehouse), D(0))
        self.assertEqual(quantity(self.w.pad, self.w.store, "in_transit"), D(1))

    def test_a_transfer_and_a_sale_cannot_both_take_the_last_unit(self):
        self.w.remove(self.w.pad, self.w.warehouse, 4)
        sale = lambda: self.call(  # noqa: E731
            "sales/",
            {
                "location": str(self.w.warehouse.pk),
                "lines": [{"product": str(self.w.pad.pk), "quantity": "1", "unit_price": "100"}],
            },
        )
        responses = self.parallel([lambda: self.send(1), sale])
        self.assertEqual(sorted(r.status_code for r in responses), [201, 409])
        self.assertEqual(quantity(self.w.pad, self.w.warehouse), D(0))

    def test_eight_copies_of_one_dispatch_make_one_transfer(self):
        key = uuid.uuid4()
        responses = self.parallel([lambda: self.send(2, key=key) for _ in range(8)])
        self.assertEqual({r.status_code for r in responses}, {201})
        self.assertEqual(len({r.json()["id"] for r in responses}), 1)
        self.assertEqual(Transfer.objects.count(), 1)
        self.assertEqual(quantity(self.w.pad, self.w.warehouse), D(3))

    def test_receiving_and_cancelling_at_the_same_moment_one_wins(self):
        transfer = self.send(3).json()
        path = f"transfers/{transfer['id']}"
        responses = self.parallel(
            [
                lambda: self.call(f"{path}/receive/", {}),
                lambda: self.call(f"{path}/cancel/", {"reason": "x"}),
            ]
        )
        self.assertEqual(sorted(r.status_code for r in responses), [200, 409])
        status = Transfer.objects.get().status
        self.assertIn(status, ("received", "cancelled"))
        total = quantity(self.w.pad, self.w.store) + quantity(self.w.pad, self.w.warehouse)
        self.assertEqual(total, D(5))  # nothing lost, nothing doubled
        self.assertEqual(quantity(self.w.pad, self.w.store, "in_transit"), D(0))

    def test_opposite_transfers_do_not_deadlock(self):
        self.w.stock(self.w.pad, self.w.store, 5, "50.00")
        back = lambda: self.call(  # noqa: E731
            "transfers/",
            {
                "from_location": str(self.w.store.pk),
                "to_location": str(self.w.warehouse.pk),
                "lines": [{"product": str(self.w.pad.pk), "quantity": "2"}],
            },
        )
        responses = self.parallel([lambda: self.send(2), back, lambda: self.send(1), back])
        self.assertEqual({r.status_code for r in responses}, {201})
        self.assertEqual(Transfer.objects.count(), 4)

    def test_a_cancel_racing_a_dispatch_over_the_same_goods_never_deadlocks(self):
        """Cancel takes the destination's in-transit row and then the source's shelf; a dispatch
        takes them the other way round. Without one queue per business PostgreSQL would have to
        abort one of them."""
        self.w.stock(self.w.pad, self.w.warehouse, 40, "50.00")
        for _ in range(12):
            cancel_path = f"transfers/{self.send(1).json()['id']}/cancel/"
            responses = self.parallel(
                [
                    lambda path=cancel_path: self.call(path, {"reason": "x"}),
                    lambda: self.send(1),
                ]
            )
            self.assertEqual(
                {r.status_code for r in responses}, {200, 201}, [r.content for r in responses]
            )
