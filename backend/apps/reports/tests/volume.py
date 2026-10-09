"""Bulk-built shop data for the volume test. The history tables are append-only (updates and
deletes are refused) but plain inserts are allowed, so this writes straight to the tables with
`bulk_create`. The data is synthetic: it is NOT consistent with the stock ledger (do not run
`reconcile()` on it), only realistic in size and shape.

Everything falls between `FIRST_DAY` and `LAST_DAY` (local days), so a report over that period
covers all of it and the totals kept in `Built` are the figures the reports must give."""

import random
import uuid
from contextlib import ExitStack, contextmanager
from datetime import date, datetime, timedelta
from decimal import ROUND_HALF_UP, Decimal
from types import SimpleNamespace
from unittest import mock
from zoneinfo import ZoneInfo

from django.db import connection

from apps.audit.models import AuditEvent
from apps.businesses.models import Business, Location, Membership, Role
from apps.catalog.models import Product, ReorderSetting, Unit
from apps.common.testing import make_member
from apps.expenses.models import Expense, ExpenseCategory
from apps.inventory.models import Condition, CostLayer, MovementType, StockBalance, StockMovement
from apps.purchasing.models import (
    Delivery,
    DeliveryLine,
    PurchaseOrder,
    PurchaseOrderLine,
    Supplier,
    SupplierReturn,
    SupplierReturnLine,
)
from apps.sales.models import Sale, SaleLine, SaleReturn, SaleReturnLine

D = Decimal
ZONE = ZoneInfo("Asia/Ashgabat")
FIRST_DAY = date(2026, 7, 1)
DAYS = 90
LAST_DAY = FIRST_DAY + timedelta(days=DAYS - 1)
START = datetime(2026, 7, 1, tzinfo=ZONE)
SECONDS = DAYS * 86400 - 1
CENT = D("0.01")
BATCH = 2000
REASONS = [f"Reason {n:02d}" for n in range(14)]
OUTGOING = ("sale", "adjustment_out", "transfer_out", "supplier_return")
ACTIONS = [
    f"{group}.{verb}"
    for group in ("sale", "expense", "stock", "transfer", "purchase_order", "catalog", "staff")
    for verb in ("created", "updated", "voided", "approved", "exported", "completed", "returned")
]


@contextmanager
def explicit_timestamps():
    """`created_at` / `received_at` are filled in by `auto_now_add`, which would overwrite the
    spread-out dates; switch that off while the rows are inserted."""
    fields = [
        Sale._meta.get_field("created_at"),
        SaleReturn._meta.get_field("created_at"),
        StockMovement._meta.get_field("created_at"),
        PurchaseOrder._meta.get_field("created_at"),
        Delivery._meta.get_field("received_at"),
        SupplierReturn._meta.get_field("created_at"),
    ]
    with ExitStack() as stack:
        for field in fields:
            stack.enter_context(mock.patch.object(field, "auto_now_add", False))
        yield


def build_shop(
    name: str,
    *,
    sales: int,
    returns: int,
    expenses: int,
    events: int,
    orders: int,
    movements: int,
    seed: int,
) -> SimpleNamespace:
    """A business with three locations, an owner, a seller (first store) and a keeper, and
    this much history. Returns the objects and the exact totals of what was written."""
    rng = random.Random(seed)
    business = Business.objects.create(name=name)
    stores = [
        Location.objects.create(business=business, name="V Store 1", kind="store"),
        Location.objects.create(business=business, name="V Store 2", kind="store"),
    ]
    warehouse = Location.objects.create(business=business, name="V Warehouse", kind="warehouse")
    places = [*stores, warehouse]
    tag = name.lower().replace(" ", "-")
    owner = make_member(business, Role.OWNER, username=f"{tag}-owner")
    seller = make_member(business, Role.SALES, username=f"{tag}-seller", locations=[stores[0]])
    keeper = make_member(business, Role.WAREHOUSE, username=f"{tag}-keeper", locations=[warehouse])
    owner_member = Membership.objects.get(user=owner, business=business)
    cashiers = [owner, seller]

    def moment() -> datetime:
        return START + timedelta(seconds=rng.randrange(SECONDS))

    def money(low: int, high: int) -> Decimal:
        return D(rng.randint(low, high)) / 100

    unit = Unit.objects.create(business=business, name="Piece", symbol="pc", decimal_places=0)
    products = Product.objects.bulk_create(
        [
            Product(
                business=business,
                sku=f"V-{n:03d}",
                name=f"Part number {n:03d}",
                unit=unit,
                price_amount=money(1000, 20000),
            )
            for n in range(40)
        ]
    )
    suppliers = Supplier.objects.bulk_create(
        [Supplier(business=business, name=f"Supplier {n:02d}") for n in range(15)]
    )
    categories = ExpenseCategory.objects.bulk_create(
        [ExpenseCategory(business=business, name=f"Category {n}") for n in range(8)]
    )

    built = SimpleNamespace(
        business=business,
        owner=owner,
        seller=seller,
        keeper=keeper,
        stores=stores,
        warehouse=warehouse,
        products=products,
        suppliers=suppliers,
        categories=categories,
        sales=sales,
        returns=returns,
        sales_total=D(0),
        refund_total=D(0),
        sold_cost=D(0),
        returned_cost=D(0),
        expense_total=D(0),
        expense_count=0,
        events=events,
        orders=orders,
    )

    # stock: balances with cost layers (one consumed, two with something left), reorder levels
    balances = []
    for product in products:
        for place in places:
            balances.append(
                StockBalance(
                    business=business,
                    product=product,
                    location=place,
                    condition=Condition.SELLABLE,
                    quantity=D(rng.randint(0, 40)),
                )
            )
    balances = StockBalance.objects.bulk_create(balances, batch_size=BATCH)
    layers = CostLayer.objects.bulk_create(
        [
            CostLayer(
                business=business,
                balance=balance,
                layer_no=number,
                unit_cost=money(100, 9000),
                quantity_initial=D(20),
                quantity_remaining=D(0) if number == 1 else D(rng.randint(1, 20)),
            )
            for balance in balances
            for number in (1, 2, 3)
        ],
        batch_size=BATCH,
    )
    ReorderSetting.objects.bulk_create(
        [
            ReorderSetting(
                business=business, product=product, location=place, minimum=D(15), target=D(40)
            )
            for product in products
            for place in places
        ],
        batch_size=BATCH,
    )
    balance_of = {balance.pk: balance for balance in balances}

    with explicit_timestamps():
        # ledger movements of every type
        kinds = list(MovementType.values)
        rows = []
        for _ in range(movements):
            layer = rng.choice(layers)
            balance = balance_of[layer.balance_id]
            kind = rng.choice(kinds)
            sign = -1 if kind in OUTGOING else 1
            rows.append(
                StockMovement(
                    business=business,
                    product_id=balance.product_id,
                    location_id=balance.location_id,
                    condition=balance.condition,
                    movement_type=kind,
                    quantity=D(sign * rng.randint(1, 9)),
                    unit_cost=layer.unit_cost,
                    layer=layer,
                    document_type="volume",
                    document_id=uuid.uuid4(),
                    actor=owner,
                    created_at=moment(),
                )
            )
        StockMovement.objects.bulk_create(rows, batch_size=BATCH)

        # sales, with 2-4 lines each, in two stores and now and then the warehouse
        sale_rows, line_rows, lines_of = [], [], {}
        for number in range(1, sales + 1):
            place = rng.choice([*stores, *stores, warehouse])
            lines, total = [], D(0)
            for position, product in enumerate(rng.sample(products, rng.choice((2, 3, 3, 4)))):
                quantity = D(rng.randint(1, 5))
                price = money(500, 20000)
                cost = (quantity * D(rng.randint(100, 15000)) / D(300)).quantize(D("0.00001"))
                line_total = (quantity * price).quantize(CENT, rounding=ROUND_HALF_UP)
                total += line_total
                built.sold_cost += cost
                lines.append(
                    SaleLine(
                        product=product,
                        position=position,
                        sku=product.sku,
                        name=product.name,
                        unit_symbol="pc",
                        unit_decimals=0,
                        quantity=quantity,
                        price_amount=product.price_amount,
                        price_currency="TMT",
                        unit_price=price,
                        line_total=line_total,
                        cost_total=cost,
                    )
                )
            sale = Sale(
                id=uuid.uuid4(),
                business=business,
                number=number,
                location=place,
                cashier=rng.choice(cashiers),
                total=total,
                payment_method=rng.choice(("cash", "cash", "card")),
                created_at=moment(),
            )
            for line in lines:
                line.sale = sale
            sale_rows.append(sale)
            line_rows.extend(lines)
            lines_of[sale.pk] = lines
            built.sales_total += total
        Sale.objects.bulk_create(sale_rows, batch_size=BATCH)
        sale_lines = SaleLine.objects.bulk_create(line_rows, batch_size=BATCH)
        built.sale_lines = len(sale_lines)

        # returns of one or two pieces of one or two lines of a sale
        return_rows, return_line_rows = [], []
        last = START + timedelta(seconds=SECONDS)
        for number in range(1, returns + 1):
            sale = rng.choice(sale_rows)
            picked = rng.sample(lines_of[sale.pk], rng.choice((1, 2)))
            given = SaleReturn(
                id=uuid.uuid4(),
                business=business,
                number=number,
                sale=sale,
                location=sale.location,
                created_by=owner,
                reason=rng.choice(REASONS),
                refund_total=D(0),
                payment_method=sale.payment_method,
                created_at=min(sale.created_at + timedelta(days=rng.randint(0, 9)), last),
            )
            for position, line in enumerate(picked):
                refund = line.unit_price  # one piece back
                cost = (line.cost_total / line.quantity).quantize(D("0.00001"))
                given.refund_total += refund
                built.returned_cost += cost
                return_line_rows.append(
                    SaleReturnLine(
                        sale_return=given,
                        sale_line=line,
                        position=position,
                        product=line.product,
                        sku=line.sku,
                        name=line.name,
                        unit_symbol="pc",
                        unit_decimals=0,
                        quantity=D(1),
                        condition=rng.choice(("sellable", "sellable", "damaged", "inspection")),
                        refund_amount=refund,
                        cost_total=cost,
                    )
                )
            return_rows.append(given)
            built.refund_total += given.refund_total
        SaleReturn.objects.bulk_create(return_rows, batch_size=BATCH)
        SaleReturnLine.objects.bulk_create(return_line_rows, batch_size=BATCH)

        # purchase orders with two lines, a delivery or two against most, a few supplier returns
        order_rows, order_lines, delivery_rows, delivery_lines = [], [], [], []
        for number in range(1, orders + 1):
            place = rng.choice(places)
            status = rng.choice(
                ("draft", "ordered", "ordered", "partially_received", "received", "received")
            )
            order = PurchaseOrder(
                id=uuid.uuid4(),
                business=business,
                number=number,
                supplier=rng.choice(suppliers),
                location=place,
                status=status,
                created_by=owner,
                created_at=moment(),
            )
            order_rows.append(order)
            lines = [
                PurchaseOrderLine(
                    order=order,
                    product=product,
                    position=position,
                    quantity=D(20),
                    unit_cost=money(100, 9000),
                    received_quantity=D(10) if status != "draft" else D(0),
                )
                for position, product in enumerate(rng.sample(products, 2))
            ]
            order_lines.extend(lines)
            if status in ("partially_received", "received"):
                for delivery_number in (1, 2) if rng.random() < 0.5 else (1,):
                    delivery = Delivery(
                        id=uuid.uuid4(),
                        business=business,
                        order=order,
                        number=delivery_number,
                        received_by=keeper,
                        received_at=moment(),
                    )
                    delivery_rows.append(delivery)
                    delivery_lines.extend(
                        DeliveryLine(
                            delivery=delivery,
                            order_line=line,
                            quantity=D(rng.randint(1, 10)),
                            unit_cost=line.unit_cost,
                        )
                        for line in lines
                    )
        PurchaseOrder.objects.bulk_create(order_rows, batch_size=BATCH)
        PurchaseOrderLine.objects.bulk_create(order_lines, batch_size=BATCH)
        Delivery.objects.bulk_create(delivery_rows, batch_size=BATCH)
        delivery_lines = DeliveryLine.objects.bulk_create(delivery_lines, batch_size=BATCH)
        built.deliveries = len(delivery_rows)

        supplier_return_rows, supplier_return_lines = [], []
        by_delivery = {d.pk: d for d in delivery_rows}
        order_of = {o.pk: o for o in order_rows}
        for number, line in enumerate(rng.sample(delivery_lines, min(300, len(delivery_lines)))):
            delivery = by_delivery[line.delivery_id]
            order = order_of[delivery.order_id]
            credit = (D(1) * line.unit_cost).quantize(CENT)
            returned = SupplierReturn(
                id=uuid.uuid4(),
                business=business,
                number=number + 1,
                supplier=order.supplier,
                delivery=delivery,
                location=order.location,
                created_by=keeper,
                reason="Wrong model",
                credit_total=credit,
                created_at=moment(),
            )
            supplier_return_rows.append(returned)
            supplier_return_lines.append(
                SupplierReturnLine(
                    supplier_return=returned,
                    delivery_line=line,
                    product_id=line.order_line.product_id,
                    quantity=D(1),
                    condition="sellable",
                    unit_cost=line.unit_cost,
                    cost_total=line.unit_cost,
                )
            )
        SupplierReturn.objects.bulk_create(supplier_return_rows, batch_size=BATCH)
        SupplierReturnLine.objects.bulk_create(supplier_return_lines, batch_size=BATCH)
        built.supplier_returns = len(supplier_return_rows)

    # expenses (5 % void) and the audit trail
    expense_rows = []
    for _ in range(expenses):
        void = rng.random() < 0.05
        amount = money(500, 150000)
        expense_rows.append(
            Expense(
                business=business,
                category=rng.choice(categories),
                location=rng.choice(places),
                amount=amount,
                spent_on=FIRST_DAY + timedelta(days=rng.randrange(DAYS)),
                created_by=owner,
                voided_at=moment() if void else None,
                voided_by=owner if void else None,
                void_reason="Entered twice" if void else "",
            )
        )
        if not void:
            built.expense_total += amount
            built.expense_count += 1
    Expense.objects.bulk_create(expense_rows, batch_size=BATCH)
    actors = [owner, seller, keeper, None]
    AuditEvent.objects.bulk_create(
        [
            AuditEvent(
                business=business,
                actor=rng.choice(actors),
                action=rng.choice(ACTIONS),
                object_type="Sale",
                object_id=str(uuid.uuid4()),
                metadata={"n": n, "total": str(money(100, 99999))},
                created_at=moment(),
            )
            for n in range(events)
        ],
        batch_size=BATCH,
    )
    built.membership = owner_member
    # Rows inserted in an open transaction have no statistics yet (autovacuum cannot see them);
    # a real database has had them analysed, so do the same before anything is measured.
    with connection.cursor() as cursor:
        cursor.execute("ANALYZE")
    return built
