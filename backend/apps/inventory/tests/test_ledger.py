import re
import threading
import uuid
from concurrent.futures import ThreadPoolExecutor
from decimal import Decimal
from pathlib import Path

from django.conf import settings
from django.db import DatabaseError, IntegrityError, connection, connections, transaction

from apps.common.errors import ApiError
from apps.common.testing import APITestCase, APITransactionTestCase
from apps.inventory import services
from apps.inventory.models import Condition, CostLayer, MovementType, StockBalance, StockMovement

from .support import World, ledger_differences, make_product

D = Decimal


class LedgerCase(APITestCase):
    def setUp(self):
        super().setUp()
        self.w = World()

    def tearDown(self):
        self.assertEqual(ledger_differences(), [])  # reconcile() == 0 after every scenario
        super().tearDown()

    def balance(self, product, location, condition=Condition.SELLABLE) -> Decimal:
        row = StockBalance.objects.filter(
            product=product, location=location, condition=condition
        ).first()
        return row.quantity if row else D(0)


class PostingTests(LedgerCase):
    def test_incoming_goods_create_a_layer_a_movement_and_a_balance(self):
        self.w.stock(self.w.pad, self.w.store, 10, "50.00")
        self.assertEqual(self.balance(self.w.pad, self.w.store), D(10))
        layer = CostLayer.objects.get()
        self.assertEqual((layer.quantity_initial, layer.quantity_remaining), (D(10), D(10)))
        self.assertEqual(layer.unit_cost, D("50.00"))
        movement = StockMovement.objects.get()
        self.assertEqual(
            (movement.quantity, movement.unit_cost, movement.layer), (D(10), D("50.00"), layer)
        )
        self.assertEqual(movement.actor, self.w.owner)

    def test_oldest_cost_is_used_first_across_several_layers(self):
        """The owner's example: 10 bought at 50, then 10 at 60. Selling 15 costs 10x50 + 5x60."""
        self.w.stock(self.w.pad, self.w.store, 10, "50.00")
        self.w.stock(self.w.pad, self.w.store, 10, "60.00")
        posted = self.w.remove(self.w.pad, self.w.store, 15)
        slices = [(m.quantity, m.unit_cost) for m in posted.movements]
        self.assertEqual(slices, [(D(-10), D("50.00")), (D(-5), D("60.00"))])
        self.assertEqual(posted.cost, D("800.00"))
        self.assertEqual(
            list(
                CostLayer.objects.order_by("layer_no").values_list("quantity_remaining", flat=True)
            ),
            [D(0), D(5)],
        )
        self.assertEqual(self.balance(self.w.pad, self.w.store), D(5))
        # what is left is valued at the newer cost
        again = self.w.remove(self.w.pad, self.w.store, 5)
        self.assertEqual(again.cost, D("300.00"))

    def test_a_partly_used_layer_is_used_up_before_the_next(self):
        self.w.stock(self.w.pad, self.w.store, 10, "50.00")
        self.w.stock(self.w.pad, self.w.store, 10, "60.00")
        self.assertEqual(self.w.remove(self.w.pad, self.w.store, 4).cost, D("200.00"))
        self.assertEqual(self.w.remove(self.w.pad, self.w.store, 8).cost, D("6") * 50 + D("2") * 60)

    def test_removing_more_than_is_there_is_refused_and_writes_nothing(self):
        self.w.stock(self.w.pad, self.w.store, 3, "50.00")
        before = StockMovement.objects.count()
        with self.assertRaises(ApiError) as caught:
            self.w.remove(self.w.pad, self.w.store, 4)
        self.assertEqual(caught.exception.code, "insufficient_stock")
        self.assertEqual(caught.exception.status_code, 409)
        self.assertEqual(caught.exception.params["available"], "3.000")
        self.assertEqual(StockMovement.objects.count(), before)
        self.assertEqual(self.balance(self.w.pad, self.w.store), D(3))

    def test_one_bad_line_rolls_back_the_whole_posting(self):
        self.w.stock(self.w.pad, self.w.store, 3, "50.00")
        lines = [
            services.Line(self.w.pad, self.w.store, D(5), MovementType.ADJUSTMENT_IN, D("10.00")),
            services.Line(self.w.pad, self.w.store, D(-9), MovementType.ADJUSTMENT_OUT),
        ]
        with self.assertRaises(ApiError):
            services.post(
                self.w.a, self.w.owner, lines, document_type="adjustment", document_id=uuid.uuid4()
            )
        self.assertEqual(self.balance(self.w.pad, self.w.store), D(3))
        self.assertEqual(StockMovement.objects.count(), 1)
        self.assertEqual(CostLayer.objects.count(), 1)

    def test_conditions_and_locations_are_separate_buckets(self):
        self.w.stock(self.w.pad, self.w.store, 5, "50.00")
        self.w.stock(self.w.pad, self.w.store, 2, "50.00", Condition.DAMAGED)
        self.w.stock(self.w.pad, self.w.warehouse, 7, "50.00")
        with self.assertRaises(ApiError):
            self.w.remove(self.w.pad, self.w.store, 6)  # damaged and warehouse stock do not count
        self.assertEqual(self.balance(self.w.pad, self.w.store, Condition.DAMAGED), D(2))
        self.assertEqual(self.balance(self.w.pad, self.w.warehouse), D(7))

    def test_quantities_follow_the_unit_precision(self):
        with self.assertRaises(ApiError) as caught:
            self.w.stock(self.w.pad, self.w.store, "2.5", "10.00")  # pieces are whole
        self.assertEqual(caught.exception.status_code, 400)
        self.w.stock(self.w.oil, self.w.store, "2.5", "10.00")  # litres allow two decimals
        with self.assertRaises(ApiError):
            self.w.stock(self.w.oil, self.w.store, "2.555", "10.00")
        self.assertEqual(self.balance(self.w.oil, self.w.store), D("2.5"))

    def test_fractional_quantities_are_costed_exactly(self):
        self.w.stock(self.w.oil, self.w.store, "10.00", "7.33")
        posted = self.w.remove(self.w.oil, self.w.store, "3.25")
        self.assertEqual(posted.cost, D("3.25") * D("7.33"))

    def test_other_businesses_records_cannot_be_posted_to(self):
        with self.assertRaises(ApiError):
            services.post(
                self.w.a,
                self.w.owner,
                [
                    services.Line(
                        self.w.b_product, self.w.store, D(1), MovementType.ADJUSTMENT_IN, D(1)
                    )
                ],
                document_type="adjustment",
                document_id=uuid.uuid4(),
            )

    def test_an_inactive_location_cannot_receive_goods(self):
        self.w.store.is_active = False
        self.w.store.save()
        with self.assertRaises(ApiError) as caught:
            self.w.stock(self.w.pad, self.w.store, 1, "1.00")
        self.assertEqual(caught.exception.code, "location_inactive")

    def test_zero_and_unpriced_incoming_lines_are_refused(self):
        with self.assertRaises(ApiError):
            self.w.stock(self.w.pad, self.w.store, 0, "1.00")
        with self.assertRaises(ApiError):
            services.post(
                self.w.a,
                self.w.owner,
                [services.Line(self.w.pad, self.w.store, D(1), MovementType.ADJUSTMENT_IN, None)],
                document_type="adjustment",
                document_id=uuid.uuid4(),
            )


class DatabaseGuardTests(LedgerCase):
    """The rules hold even if the application code is bypassed."""

    def test_the_database_refuses_a_negative_balance(self):
        self.w.stock(self.w.pad, self.w.store, 3, "50.00")
        with self.assertRaises(IntegrityError), transaction.atomic():
            with connection.cursor() as cursor:
                cursor.execute("UPDATE inventory_stockbalance SET quantity = -1")

    def test_the_database_refuses_a_layer_below_zero_or_above_its_start(self):
        self.w.stock(self.w.pad, self.w.store, 3, "50.00")
        for value in ("-1", "99"):
            with self.subTest(value=value):
                with self.assertRaises(IntegrityError), transaction.atomic():
                    with connection.cursor() as cursor:
                        cursor.execute(
                            f"UPDATE inventory_costlayer SET quantity_remaining = {value}"
                        )

    def test_movements_cannot_be_edited_or_deleted_even_with_raw_sql(self):
        self.w.stock(self.w.pad, self.w.store, 3, "50.00")
        for sql in (
            "UPDATE inventory_stockmovement SET quantity = 99",
            "DELETE FROM inventory_stockmovement",
        ):
            with self.subTest(sql=sql):
                with self.assertRaises(DatabaseError), transaction.atomic():
                    with connection.cursor() as cursor:
                        cursor.execute(sql)
        self.assertEqual(StockMovement.objects.get().quantity, D(3))

    def test_the_orm_refuses_to_edit_or_delete_a_movement(self):
        self.w.stock(self.w.pad, self.w.store, 3, "50.00")
        movement = StockMovement.objects.get()
        movement.quantity = D(9)
        with self.assertRaises(RuntimeError):
            movement.save()
        with self.assertRaises(RuntimeError):
            movement.delete()

    def test_reconcile_notices_a_balance_that_was_changed_behind_the_ledgers_back(self):
        self.w.stock(self.w.pad, self.w.store, 3, "50.00")
        StockBalance.objects.update(quantity=D(5))  # what the service never does
        found = services.reconcile(self.w.a)
        self.assertEqual(len(found), 1)
        self.assertIn("balance=5", found[0])
        StockBalance.objects.update(quantity=D(3))  # put it right so tearDown passes

    def test_reconcile_notices_a_layer_that_was_changed_behind_the_ledgers_back(self):
        self.w.stock(self.w.pad, self.w.store, 3, "50.00")
        CostLayer.objects.update(quantity_remaining=D(2))
        self.assertTrue(services.reconcile(self.w.a))
        CostLayer.objects.update(quantity_remaining=D(3))


class SingleWriterTests(APITestCase):
    def test_only_the_inventory_service_writes_the_ledger_tables(self):
        """Search the code base: nothing but apps/inventory/services.py may create or change
        stock movements, balances or cost layers."""
        root = Path(settings.BASE_DIR) / "apps"
        write = re.compile(
            r"(StockMovement|StockBalance|CostLayer)\.objects\.(create|bulk_create|update|"
            r"get_or_create|update_or_create|filter\([^)]*\)\.(update|delete)|all\(\)\.(update|delete))"
        )
        offenders = []
        for path in root.rglob("*.py"):
            relative = path.relative_to(root)
            parts = relative.parts
            if (
                "tests" in parts
                or "migrations" in parts
                or str(relative) == "inventory/services.py"
            ):
                continue
            if write.search(path.read_text()):
                offenders.append(str(relative))
        self.assertEqual(offenders, [])


class ConcurrencyTests(APITransactionTestCase):
    """Real commits and real threads against PostgreSQL."""

    def setUp(self):
        super().setUp()
        self.w = World()

    def tearDown(self):
        self.assertEqual(ledger_differences(), [])
        super().tearDown()

    def parallel(self, calls):
        barrier = threading.Barrier(len(calls))

        def worker(call):
            try:
                barrier.wait(timeout=10)
                return call()
            except ApiError as exc:
                return exc
            finally:
                connections.close_all()

        with ThreadPoolExecutor(max_workers=len(calls)) as pool:
            return list(pool.map(worker, calls))

    def test_two_simultaneous_outflows_of_the_last_unit_only_one_succeeds(self):
        self.w.stock(self.w.pad, self.w.store, 1, "50.00")
        results = self.parallel([lambda: self.w.remove(self.w.pad, self.w.store, 1)] * 2)
        failures = [r for r in results if isinstance(r, ApiError)]
        self.assertEqual(len(failures), 1)
        self.assertEqual(failures[0].code, "insufficient_stock")
        self.assertEqual(StockBalance.objects.get().quantity, D(0))
        self.assertEqual(StockMovement.objects.filter(quantity__lt=0).count(), 1)

    def test_many_simultaneous_outflows_never_oversell(self):
        self.w.stock(self.w.pad, self.w.store, 5, "50.00")
        results = self.parallel([lambda: self.w.remove(self.w.pad, self.w.store, 1)] * 12)
        succeeded = [r for r in results if not isinstance(r, ApiError)]
        self.assertEqual(len(succeeded), 5)
        self.assertEqual(StockBalance.objects.get().quantity, D(0))
        self.assertEqual(CostLayer.objects.get().quantity_remaining, D(0))

    def test_simultaneous_first_receipts_of_a_new_product_both_succeed(self):
        """Both create the same balance row at the same moment; neither may fail or be lost."""
        results = self.parallel(
            [
                lambda: self.w.stock(self.w.pad, self.w.store, 3, "10.00"),
                lambda: self.w.stock(self.w.pad, self.w.store, 4, "20.00"),
                lambda: self.w.stock(self.w.pad, self.w.store, 5, "30.00"),
            ]
        )
        self.assertFalse([r for r in results if isinstance(r, Exception)])
        self.assertEqual(StockBalance.objects.get().quantity, D(12))
        self.assertEqual(sorted(CostLayer.objects.values_list("layer_no", flat=True)), [1, 2, 3])

    def test_postings_that_touch_the_same_rows_in_opposite_order_do_not_deadlock(self):
        other = make_product(self.w.a, "BP-2", "Rotor", self.w.unit)
        for product in (self.w.pad, other):
            self.w.stock(product, self.w.store, 100, "10.00")

        def posting(first, second):
            def run():
                lines = [
                    services.Line(first, self.w.store, D(-1), MovementType.ADJUSTMENT_OUT),
                    services.Line(second, self.w.store, D(-1), MovementType.ADJUSTMENT_OUT),
                ]
                return services.post(
                    self.w.a,
                    self.w.owner,
                    lines,
                    document_type="adjustment",
                    document_id=uuid.uuid4(),
                )

            return run

        calls = [posting(self.w.pad, other), posting(other, self.w.pad)] * 6
        results = self.parallel(calls)
        self.assertFalse([r for r in results if isinstance(r, Exception)])
        self.assertEqual(
            sorted(StockBalance.objects.values_list("quantity", flat=True)), [D(88), D(88)]
        )
