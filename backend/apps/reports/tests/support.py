"""A small, fully known shop history for the report tests, built through the real services with
the clock set for every step. All times are local (Asia/Ashgabat, UTC+5, no daylight saving).

Prices, quantities and costs were chosen so every figure can be worked out by hand; the tests
state the expected values literally. The story, in order:

  09-20  PO-0 (Turkmen supplier, store): oil 10 @ 7.50, ordered
  09-30  stock: store pad 10 @ 50 and 10 @ 60, store oil 20 @ 8; warehouse pad 4 @ 55;
         expense E1 rent 1000.00 (store)
  10-01  08:00 PO-1 (Ashgabat supplier, warehouse): pad 10 @ 60, oil 20 @ 8, ordered
         10:00 S1 (sales user, store, cash): pad 3 @ 100 + oil 2.5 @ 25 = 362.50
         10:30 E2 transport 45.50 (store)
         23:30 S2 (owner, store, card): pad 2 @ 90 = 180.00
  10-02  00:30 S3 (sales user, store, card): pad 7 @ 95 = 665.00
         09:00 E3 rent 200.00 (warehouse); E4 transport 30.00 (store), voided at 09:05
         11:00 R1 on S1 "Wrong size": pad 1 + oil 0.5, both sellable = 112.50
         14:00 PO-0 delivery (oil 10), PO-1 delivery 1 (pad 6, oil 20)
  10-03  09:00 R2 on S3 "Defective": pad 2 damaged = 190.00
         09:30 PO-2 (Turkmen supplier, warehouse): oil 15 @ 9, ordered
         09:45 PO-3 (Ashgabat supplier, store): pad 1 @ 70, left as a draft
         10:00 R3 on S3 "Wrong size": pad 1 awaiting inspection = 95.00
         11:00 PO-1 delivery 2 (pad 2)
         12:00 transfer store -> warehouse, pad 2 (received at 15:00)
         13:00 S4 (owner, warehouse, cash): pad 1 @ 110 = 110.00
         16:00 supplier return of PO-1 delivery 1: pad 2 sellable "Wrong model"

Another business (B) has a sale, an expense and an audit event on 10-02, which must never show
up in business A's figures.
"""

import uuid
from datetime import date, datetime
from decimal import Decimal
from types import SimpleNamespace
from unittest import mock
from zoneinfo import ZoneInfo

from apps.audit import services as audit
from apps.businesses.models import Membership, Role
from apps.catalog.models import Product, ReorderSetting
from apps.common.testing import APITestCase
from apps.expenses import services as expense_services
from apps.expenses.models import ExpenseCategory
from apps.inventory import services as inventory
from apps.inventory.models import MovementType
from apps.inventory.tests.support import World, ledger_differences, make_product
from apps.purchasing import returns as supplier_returns
from apps.purchasing import services as purchasing
from apps.purchasing.models import Supplier
from apps.sales import returns as sale_returns
from apps.sales import services as sales
from apps.stockops import services as transfers

D = Decimal
ZONE = ZoneInfo("Asia/Ashgabat")
BASE = "/api/v1/businesses"


def at(day: str, clock: str = "12:00"):
    """The clock stands still at this local time while the `with` block runs."""
    moment = datetime.fromisoformat(f"{day}T{clock}").replace(tzinfo=ZONE)
    return mock.patch("django.utils.timezone.now", return_value=moment)


def build(w: World) -> SimpleNamespace:
    a, b = w.a, w.b
    owner = w.users[Role.OWNER]
    seller = w.users[Role.SALES]  # works at the store only
    keeper = w.users[Role.WAREHOUSE]  # works at the warehouse only
    member = {u: Membership.objects.get(user=u, business=a) for u in (owner, seller, keeper)}
    s = SimpleNamespace(owner=owner, seller=seller, keeper=keeper)
    s.spark = make_product(a, "SP-1", "Spark plug", w.unit, "30.00")
    s.old = make_product(a, "OLD-1", "Old filter", w.unit, "20.00")
    Product.objects.filter(pk=s.old.pk).update(is_active=False)
    s.ashgabat = Supplier.objects.create(business=a, name="Ashgabat Parts")
    s.tmt = Supplier.objects.create(business=a, name="Türkmen Täze")
    s.rent = ExpenseCategory.objects.create(business=a, name="Аренда")
    s.transport = ExpenseCategory.objects.create(business=a, name="Транспорт")

    def order(supplier, location, lines, submit=True):
        rows = [{"product": p, "quantity": D(q), "unit_cost": D(c)} for p, q, c in lines]
        placed = purchasing.create_order(
            a, owner, {"supplier": supplier, "location": location, "lines": rows}
        )
        if submit:
            purchasing.submit_order(a, owner, placed.pk)
        return placed

    def receive(placed, user, quantities):
        by_product = {line.product_id: line for line in placed.lines.all()}
        rows = [{"order_line": by_product[p.pk].pk, "quantity": D(q)} for p, q in quantities]
        return purchasing.receive(a, user, placed.pk, rows)

    def sell(user, location, lines, method="cash"):
        rows = [{"product": p, "quantity": D(q), "unit_price": D(price)} for p, q, price in lines]
        return sales.complete_sale(
            a, user, {"location": location, "lines": rows, "payment_method": method}
        )

    def give_back(user, sale, reason, lines):
        rows = [
            {
                "sale_line": sale.lines.get(product=p).pk,
                "quantity": D(q),
                "condition": condition,
            }
            for p, q, condition in lines
        ]
        return sale_returns.create_return(
            a, user, member[user], sale.pk, {"lines": rows, "reason": reason}
        )

    def spend(category, location, day, amount, text=""):
        return expense_services.create_expense(
            a,
            owner,
            member[owner],
            {
                "category": category,
                "location": location,
                "amount": D(amount),
                "spent_on": date.fromisoformat(day),
                "description": text,
            },
        )

    with at("2026-09-20", "12:00"):
        s.po0 = order(s.tmt, w.store, [(w.oil, 10, "7.50")])
    with at("2026-09-30", "10:00"):
        w.stock(w.pad, w.store, 10, "50.00")
        w.stock(w.pad, w.store, 10, "60.00")
        w.stock(w.oil, w.store, 20, "8.00")
        w.stock(w.pad, w.warehouse, 4, "55.00")
        for product, location, minimum, target in (
            (w.pad, w.store, 10, 30),
            (w.pad, w.warehouse, 5, 20),
            (w.oil, w.store, 28, 60),
            (w.oil, w.warehouse, 30, 50),
            (s.spark, w.store, 4, 10),
            (s.old, w.store, 100, 200),  # archived: never listed
        ):
            ReorderSetting.objects.create(
                business=a, product=product, location=location, minimum=minimum, target=target
            )
        s.e1 = spend(s.rent, w.store, "2026-09-30", "1000.00", "September rent")
    with at("2026-10-01", "08:00"):
        s.po1 = order(s.ashgabat, w.warehouse, [(w.pad, 10, "60.00"), (w.oil, 20, "8.00")])
    with at("2026-10-01", "10:00"):
        s.s1 = sell(seller, w.store, [(w.pad, 3, "100.00"), (w.oil, "2.5", "25.00")])
    with at("2026-10-01", "10:30"):
        s.e2 = spend(s.transport, w.store, "2026-10-01", "45.50", "Delivery to the market")
    with at("2026-10-01", "23:30"):
        s.s2 = sell(owner, w.store, [(w.pad, 2, "90.00")], "card")
    with at("2026-10-02", "00:30"):
        s.s3 = sell(seller, w.store, [(w.pad, 7, "95.00")], "card")
    with at("2026-10-02", "09:00"):
        s.e3 = spend(s.rent, w.warehouse, "2026-10-02", "200.00", "Warehouse rent")
        s.e4 = spend(s.transport, w.store, "2026-10-02", "30.00", "Entered by mistake")
    with at("2026-10-02", "09:05"):
        expense_services.void_expense(a, owner, member[owner], s.e4.pk, "Entered twice")
    with at("2026-10-02", "11:00"):
        s.r1 = give_back(
            seller, s.s1, "Wrong size", [(w.pad, 1, "sellable"), (w.oil, "0.5", "sellable")]
        )
    with at("2026-10-02", "14:00"):
        s.d0 = receive(s.po0, keeper, [(w.oil, 10)])
        s.d1 = receive(s.po1, keeper, [(w.pad, 6), (w.oil, 20)])
    with at("2026-10-03", "09:00"):
        s.r2 = give_back(owner, s.s3, "Defective", [(w.pad, 2, "damaged")])
    with at("2026-10-03", "09:30"):
        s.po2 = order(s.tmt, w.warehouse, [(w.oil, 15, "9.00")])
    with at("2026-10-03", "09:45"):
        s.po3 = order(s.ashgabat, w.store, [(w.pad, 1, "70.00")], submit=False)
    with at("2026-10-03", "10:00"):
        s.r3 = give_back(seller, s.s3, "Wrong size", [(w.pad, 1, "inspection")])
    with at("2026-10-03", "11:00"):
        s.d2 = receive(s.po1, keeper, [(w.pad, 2)])
    with at("2026-10-03", "12:00"):
        s.transfer = transfers.dispatch_transfer(
            a,
            owner,
            member[owner],
            {
                "from_location": w.store,
                "to_location": w.warehouse,
                "lines": [{"product": w.pad, "quantity": D(2)}],
            },
        )
    with at("2026-10-03", "13:00"):
        s.s4 = sell(owner, w.warehouse, [(w.pad, 1, "110.00")])
    with at("2026-10-03", "15:00"):
        transfers.receive_transfer(a, owner, member[owner], s.transfer.pk, {})
    with at("2026-10-03", "16:00"):
        line = s.d1.lines.get(order_line__product=w.pad)  # delivery 1: pad 6 and oil 20
        s.sr1 = supplier_returns.return_to_supplier(
            a,
            keeper,
            member[keeper],
            {
                "delivery": s.d1,
                "reason": "Wrong model",
                "lines": [{"delivery_line": line.pk, "quantity": D(2), "condition": "sellable"}],
            },
        )

    # business B: a sale, an expense and an audit event that must never reach business A
    b_owner = w.b_owner
    b_membership = Membership.objects.get(user=b_owner, business=b)
    b_category = ExpenseCategory.objects.create(business=b, name="Аренда")
    with at("2026-10-02", "12:00"):
        inventory.post(
            b,
            b_owner,
            [
                inventory.Line(
                    product=w.b_product,
                    location=w.b_store,
                    quantity=D(5),
                    unit_cost=D("10.00"),
                    movement_type=MovementType.ADJUSTMENT_IN,
                )
            ],
            document_type="adjustment",
            document_id=uuid.uuid4(),
        )
        sales.complete_sale(
            b,
            b_owner,
            {
                "location": w.b_store,
                "lines": [{"product": w.b_product, "quantity": D(2), "unit_price": D("500.00")}],
                "payment_method": "cash",
            },
        )
        expense_services.create_expense(
            b,
            b_owner,
            b_membership,
            {
                "category": b_category,
                "location": w.b_store,
                "amount": D("777.00"),
                "spent_on": date(2026, 10, 2),
                "description": "Business B only",
            },
        )
        audit.record("secret.b_only", actor=b_owner, business=b, metadata={"marker": "B-SECRET"})
    audit.record("auth.login", actor=owner)  # an event that belongs to no business
    return s


PERIOD = {"from": "2026-10-01", "to": "2026-10-03"}
WHOLE = {"date_from": "2026-10-01", "date_to": "2026-10-03"}


class ReportsCase(APITestCase):
    """Business A with the story above, one client per role, and the clock at the end of it."""

    def setUp(self):
        super().setUp()
        self.w = World()
        self.s = build(self.w)
        self.owner = self.w.api[Role.OWNER]
        self.manager = self.w.api[Role.MANAGER]
        self.sales = self.w.api[Role.SALES]
        self.warehouse = self.w.api[Role.WAREHOUSE]

    def tearDown(self):
        self.assertEqual(ledger_differences(), [])  # the story itself must be consistent
        super().tearDown()

    def get(self, client, path, **params):
        return client.get(f"{self.w.base}/{path}", params)

    def ok(self, path, client=None, **params):
        response = self.get(client or self.owner, path, **params)
        self.assertEqual(response.status_code, 200, response.content)
        return response.json()

    def error(self, response, status, code):
        self.assertEqual(response.status_code, status, response.content)
        self.assertEqual(response.json()["error"]["code"], code)
        return response.json()["error"]

    @staticmethod
    def place(obj):
        return {"id": str(obj.pk), "name": obj.name}
