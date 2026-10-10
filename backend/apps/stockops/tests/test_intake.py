import uuid
from decimal import Decimal

from apps.audit.models import AuditEvent
from apps.businesses.models import Role
from apps.common.testing import APITestCase
from apps.inventory.models import CostLayer, MovementType, StockBalance, StockMovement
from apps.inventory.tests.support import World, ledger_differences
from apps.stockops.models import StockIntake, StockIntakeLine

D = Decimal


def on_shelf(product, location, condition="sellable"):
    row = StockBalance.objects.filter(
        product=product, location=location, condition=condition
    ).first()
    return row.quantity if row else D(0)


class IntakeCase(APITestCase):
    def setUp(self):
        super().setUp()
        self.w = World()
        self.owner = self.w.api[Role.OWNER]
        self.keeper = self.w.api[Role.WAREHOUSE]  # works at A Warehouse only
        self.seller = self.w.api[Role.SALES]
        self.url = f"{self.w.base}/intakes/"

    def tearDown(self):
        self.assertEqual(ledger_differences(), [])  # includes the intakes' own check
        super().tearDown()

    @staticmethod
    def line(product, quantity=1, unit_cost=None):
        row = {"product": str(product.pk), "quantity": str(quantity)}
        if unit_cost is not None:
            row["unit_cost"] = str(unit_cost)
        return row

    def receive(self, lines=None, *, client=None, location=None, key=None, **extra):
        return (client or self.keeper).post(
            self.url,
            {
                "location": str((location or self.w.warehouse).pk),
                "lines": lines if lines is not None else [self.line(self.w.pad, 15)],
                **extra,
            },
            format="json",
            HTTP_IDEMPOTENCY_KEY=str(key or uuid.uuid4()),
        )

    def received(self, **kwargs):
        response = self.receive(**kwargs)
        self.assertEqual(response.status_code, 201, response.content)
        return response.json()


class ReceivingTests(IntakeCase):
    def test_counted_goods_arrive_in_one_document(self):
        data = self.received(
            lines=[self.line(self.w.pad, 15), self.line(self.w.oil, "2.5")], note="Box 1"
        )
        self.assertEqual((data["number"], data["note"]), (1, "Box 1"))
        self.assertEqual((data["line_count"], data["units"]), (2, "17.500"))
        self.assertEqual([x["product"]["sku"] for x in data["lines"]], ["BP-1", "OIL-1"])
        self.assertEqual(on_shelf(self.w.pad, self.w.warehouse), D(15))
        self.assertEqual(on_shelf(self.w.oil, self.w.warehouse), D("2.5"))
        moves = StockMovement.objects.filter(document_id=data["id"])
        self.assertEqual({m.movement_type for m in moves}, {MovementType.INTAKE})
        self.assertEqual({m.document_type for m in moves}, {"intake"})
        self.assertEqual(
            AuditEvent.objects.filter(action="stock.intake_posted", business=self.w.a).count(), 1
        )

    def test_numbers_run_on_per_business(self):
        self.assertEqual(self.received()["number"], 1)
        self.assertEqual(self.received()["number"], 2)

    def test_the_same_request_twice_receives_once(self):
        key = uuid.uuid4()
        first = self.receive(key=key)
        again = self.receive(key=key)
        self.assertEqual((first.status_code, again.status_code), (201, 201))
        self.assertEqual(first.json()["id"], again.json()["id"])
        self.assertEqual(StockIntake.objects.count(), 1)
        self.assertEqual(on_shelf(self.w.pad, self.w.warehouse), D(15))

    def test_a_keeper_receives_without_money_and_costs_stay_hidden_from_them(self):
        data = self.received()
        self.assertNotIn("unit_cost", data["lines"][0])
        self.assertNotIn("cost_known", data["lines"][0])
        line = StockIntakeLine.objects.get()
        self.assertEqual((line.unit_cost, line.cost_known), (D("0"), False))
        seen = self.keeper.get(f"{self.url}{data['id']}/").json()
        self.assertNotIn("unit_cost", seen["lines"][0])


class CostTests(IntakeCase):
    def test_an_owner_can_enter_a_cost_and_it_becomes_the_fifo_layer(self):
        data = self.received(
            client=self.owner,
            location=self.w.store,
            lines=[self.line(self.w.pad, 4, "35.50")],
        )
        self.assertEqual(
            (data["lines"][0]["unit_cost"], data["lines"][0]["cost_known"]), ("35.50", True)
        )
        layer = CostLayer.objects.get(balance__product=self.w.pad)
        self.assertEqual((layer.unit_cost, layer.quantity_remaining), (D("35.50"), D(4)))

    def test_without_a_cost_the_default_purchase_cost_is_used_but_not_counted_as_known(self):
        self.w.pad.default_purchase_cost = D("40.00")
        self.w.pad.save()
        data = self.received(client=self.owner)
        self.assertEqual(
            (data["lines"][0]["unit_cost"], data["lines"][0]["cost_known"]), ("40.00", False)
        )
        self.assertEqual(CostLayer.objects.get().unit_cost, D("40.00"))

    def test_without_any_cost_the_layer_costs_zero_and_says_so(self):
        data = self.received(client=self.owner)
        self.assertEqual(
            (data["lines"][0]["unit_cost"], data["lines"][0]["cost_known"]), ("0.00", False)
        )

    def test_a_role_that_cannot_see_costs_cannot_enter_one(self):
        response = self.receive(lines=[self.line(self.w.pad, 5, "10.00")])
        self.assertEqual(response.status_code, 403)
        self.assertEqual(response.json()["error"]["code"], "permission_denied")
        self.assertEqual(StockIntake.objects.count(), 0)
        self.assertEqual(on_shelf(self.w.pad, self.w.warehouse), D(0))

    def test_a_negative_cost_is_refused(self):
        response = self.receive(client=self.owner, lines=[self.line(self.w.pad, 5, "-1")])
        self.assertEqual(response.status_code, 400)


class RefusalTests(IntakeCase):
    def assertNothingChanged(self):
        self.assertEqual(StockIntake.objects.count(), 0)
        self.assertEqual(StockMovement.objects.count(), 0)

    def test_roles_without_the_right_cannot_receive_or_read(self):
        response = self.receive(client=self.seller, location=self.w.store)
        self.assertEqual(response.status_code, 403)
        self.assertEqual(self.seller.get(self.url).status_code, 403)
        self.assertNothingChanged()

    def test_a_keeper_cannot_receive_at_a_place_they_do_not_work(self):
        response = self.receive(location=self.w.store)
        self.assertEqual(response.status_code, 403)
        self.assertEqual(response.json()["error"]["code"], "location_not_permitted")
        self.assertNothingChanged()

    def test_products_and_places_of_another_business_are_refused(self):
        self.assertEqual(self.receive(lines=[self.line(self.w.b_product)]).status_code, 400)
        self.assertEqual(self.receive(location=self.w.b_store).status_code, 400)
        self.assertEqual(self.w.b_api.get(self.url).status_code, 404)  # not their business
        self.assertNothingChanged()

    def test_bad_lists_are_refused_as_a_whole(self):
        for lines in (
            [],
            [self.line(self.w.pad, 0)],
            [self.line(self.w.pad, -2)],
            [self.line(self.w.pad, 1), self.line(self.w.pad, 2)],  # the same product twice
            [self.line(self.w.pad, "1.5")],  # pieces are whole
        ):
            with self.subTest(lines=lines):
                self.assertGreaterEqual(self.receive(lines=lines).status_code, 400)
        self.assertNothingChanged()

    def test_one_bad_line_receives_nothing_of_the_good_ones(self):
        response = self.receive(lines=[self.line(self.w.pad, 3), self.line(self.w.oil, "1.2345")])
        self.assertGreaterEqual(response.status_code, 400)
        self.assertNothingChanged()
        self.assertEqual(on_shelf(self.w.pad, self.w.warehouse), D(0))

    def test_an_archived_product_cannot_be_received(self):
        self.w.pad.is_active = False
        self.w.pad.save()
        response = self.receive()
        self.assertEqual(response.status_code, 409)
        self.assertEqual(response.json()["error"]["code"], "product_archived")
        self.assertNothingChanged()

    def test_too_many_lines_are_refused(self):
        lines = [self.line(self.w.pad, 1)] * 301
        self.assertEqual(self.receive(lines=lines).status_code, 400)


class ReadingTests(IntakeCase):
    def test_list_and_detail_show_only_the_callers_places(self):
        mine = self.received()
        elsewhere = self.received(client=self.owner, location=self.w.store)
        keeper_sees = self.keeper.get(self.url).json()
        self.assertEqual([x["id"] for x in keeper_sees["results"]], [mine["id"]])
        self.assertEqual(self.keeper.get(f"{self.url}{elsewhere['id']}/").status_code, 404)
        owner_sees = self.owner.get(self.url).json()
        self.assertEqual(owner_sees["count"], 2)
        self.assertEqual(owner_sees["results"][0]["number"], 2)  # newest first

    def test_search_by_number_and_filter_by_place(self):
        self.received()
        self.received(client=self.owner, location=self.w.store)
        self.assertEqual(self.owner.get(f"{self.url}?q=IN-0002").json()["count"], 1)
        self.assertEqual(self.owner.get(f"{self.url}?q=nonsense").json()["count"], 0)
        by_place = self.owner.get(f"{self.url}?location={self.w.warehouse.pk}").json()
        self.assertEqual(by_place["count"], 1)

    def test_documents_cannot_be_changed_afterwards(self):
        data = self.received()
        intake = StockIntake.objects.get(pk=data["id"])
        intake.note = "edited"
        with self.assertRaises(RuntimeError):
            intake.save()
        with self.assertRaises(RuntimeError):
            intake.delete()


class LedgerCheckTests(IntakeCase):
    def tearDown(self):
        # these tests break the ledger on purpose, so skip the usual "ledger is clean" check
        super(IntakeCase, self).tearDown()

    def test_the_ledger_check_notices_a_document_that_disagrees_with_the_shelf(self):
        from apps.inventory import services as ledger
        from apps.stockops.services import reconcile

        self.received()
        self.assertEqual(reconcile(self.w.a), [])
        # a document line that never reached the shelf
        ghost = StockIntake.objects.create(
            business=self.w.a,
            number=99,
            location=self.w.warehouse,
            created_by=self.w.owner,
        )
        StockIntakeLine.objects.create(
            intake=ghost, position=1, product=self.w.oil, quantity=D("3"), unit_cost=D("1")
        )
        found = reconcile(self.w.a)
        self.assertEqual(len(found), 1)
        self.assertIn("IN-0099", found[0])
        # goods that reached the shelf under an intake that has no such line
        ledger.post(
            self.w.a,
            self.w.owner,
            [
                ledger.Line(
                    product=self.w.oil,
                    location=self.w.store,
                    quantity=D("2"),
                    unit_cost=D("1"),
                    movement_type=MovementType.INTAKE,
                )
            ],
            document_type="intake",
            document_id=uuid.uuid4(),
        )
        self.assertEqual(len(reconcile(self.w.a)), 2)
