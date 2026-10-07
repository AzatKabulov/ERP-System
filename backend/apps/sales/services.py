"""Selling. `complete_sale` is the one command that turns a cart into a sale: it prices every
line on the server, takes the goods out of stock through the inventory service (FIFO, never below
zero), records the payments, and numbers the sale, all in one transaction. Callers wrap it in
`run_idempotent`, so a retry (a timeout, a crash, a tablet restart) never sells twice."""

import uuid
from decimal import ROUND_HALF_UP, Decimal

from django.db import transaction
from django.db.models import Sum

from apps.audit import services as audit
from apps.businesses.permissions import has_permission
from apps.businesses.rates import current_rate, to_tmt
from apps.catalog.services import check_quantity_precision
from apps.common.errors import ApiError
from apps.inventory import services as inventory
from apps.inventory.models import Condition, MovementType, StockMovement
from apps.purchasing.services import next_number

from .models import Customer, PaymentMethod, Sale, SaleLine, SalePayment

CENT = Decimal("0.01")
ZERO = Decimal("0")


def _money(value: Decimal) -> Decimal:
    return value.quantize(CENT, rounding=ROUND_HALF_UP)


def rebuild_customer_search_key(customer: Customer) -> None:
    key = " ".join(part.casefold() for part in (customer.name, customer.phone) if part)
    if key != customer.search_key:
        Customer.objects.filter(pk=customer.pk).update(search_key=key)
        customer.search_key = key


@transaction.atomic
def save_customer(business, actor, data: dict, instance: Customer | None = None) -> Customer:
    if instance is None:
        instance = Customer(business=business)
        action = "customer.created"
    else:
        action = "customer.updated"
    for field in ("name", "phone", "notes", "is_active"):
        if field in data:
            setattr(instance, field, data[field])
    instance.save()
    rebuild_customer_search_key(instance)
    audit.record(
        action, actor=actor, business=business, obj=instance, metadata={"name": instance.name}
    )
    return instance


def _price_lines(business, rows: list[dict], role: str):
    """Look every product up and price the line. Returns (priced lines, rate used or None)."""
    products = [r["product"].pk for r in rows]
    if len(set(products)) != len(products):
        raise ApiError(
            "validation_error",
            "A product appears twice",
            fields={"lines": [{"code": "duplicate_product", "message": "Duplicate product"}]},
        )
    if any(r["discount"] > 0 for r in rows) and not has_permission(role, "sales.discount"):
        raise ApiError("permission_denied", "You may not give discounts", status_code=403)
    rate = None
    if any(r["product"].price_currency != "TMT" for r in rows):
        rate = current_rate(business)
        if rate is None:
            missing = next(r["product"] for r in rows if r["product"].price_currency != "TMT")
            raise ApiError(
                "rate_missing",
                "No USD rate has been entered",
                status_code=409,
                params={"product": str(missing.pk)},
            )
    priced = []
    for index, row in enumerate(rows):
        product = row["product"]
        if not product.is_active:
            raise ApiError(
                "product_archived",
                "Archived products cannot be sold",
                status_code=409,
                params={"product": str(product.pk)},
            )
        quantity = row["quantity"]
        check_quantity_precision(quantity, product.unit)
        unit_price = to_tmt(product.price_amount, product.price_currency, rate)
        gross = _money(quantity * unit_price)
        discount = row["discount"]
        if discount > gross:
            raise ApiError(
                "validation_error",
                "The discount is larger than the line",
                fields={
                    f"lines.{index}.discount": [
                        {"code": "discount_too_large", "message": str(gross)}
                    ]
                },
            )
        priced.append(
            {
                "product": product,
                "quantity": quantity,
                "unit_price": unit_price,
                "gross": gross,
                "discount": discount,
                "line_total": gross - discount,
            }
        )
    return priced, rate


def _check_payments(total: Decimal, payments: list[dict]) -> Decimal:
    """The payments must cover the total. Anything above it is change, and only cash can give
    change. Returns the change."""
    paid = sum((p["amount"] for p in payments), ZERO)
    cash = sum((p["amount"] for p in payments if p["method"] == PaymentMethod.CASH), ZERO)
    change = paid - total
    if paid < total or change > cash or (total == 0 and paid != 0):
        raise ApiError(
            "payment_mismatch",
            "The payments do not match the total",
            params={"total": str(total), "paid": str(paid)},
            fields={"payments": [{"code": "payment_mismatch", "message": str(paid)}]},
        )
    return change


@transaction.atomic
def complete_sale(business, actor, membership, data: dict) -> Sale:
    rows = data["lines"]
    location = data["location"]
    priced, rate = _price_lines(business, rows, membership.role)
    total = sum((line["line_total"] for line in priced), ZERO)
    expected = data.get("expected_total")
    if expected is not None and expected != total:
        raise ApiError(
            "price_changed",
            "The total changed since the cart was prepared",
            status_code=409,
            params={"expected": str(expected), "total": str(total)},
        )
    change = _check_payments(total, data["payments"])

    sale_id = uuid.uuid4()
    posted = inventory.post(
        business,
        actor,
        [
            inventory.Line(
                product=line["product"],
                location=location,
                quantity=-line["quantity"],
                movement_type=MovementType.SALE,
                condition=Condition.SELLABLE,
            )
            for line in priced
        ],
        document_type="sale",
        document_id=sale_id,
    )
    cost_by_product: dict = {}
    for movement in posted.movements:
        cost_by_product[movement.product_id] = cost_by_product.get(movement.product_id, ZERO) + (
            -movement.quantity * movement.unit_cost
        )

    customer = data.get("customer")
    # The number is taken last so the counter row is held only briefly.
    sale = Sale.objects.create(
        id=sale_id,
        business=business,
        number=next_number(business, "sale"),
        location=location,
        cashier=actor,
        customer=customer,
        customer_name=customer.name if customer else "",
        customer_phone=customer.phone if customer else "",
        total=total,
        change_given=change,
        usd_rate=rate.rate if rate is not None else None,
        note=data.get("note", ""),
    )
    SaleLine.objects.bulk_create(
        [
            SaleLine(
                sale=sale,
                position=index,
                product=line["product"],
                sku=line["product"].sku,
                name=line["product"].name,
                unit_symbol=line["product"].unit.symbol,
                unit_decimals=line["product"].unit.decimal_places,
                quantity=line["quantity"],
                price_amount=line["product"].price_amount,
                price_currency=line["product"].price_currency,
                unit_price=line["unit_price"],
                gross=line["gross"],
                discount=line["discount"],
                line_total=line["line_total"],
                cost_total=cost_by_product[line["product"].pk],
                warranty_months=line["product"].warranty_months,
                warranty_terms=line["product"].warranty_terms,
            )
            for index, line in enumerate(priced)
        ]
    )
    SalePayment.objects.bulk_create(
        [
            SalePayment(sale=sale, position=index, method=p["method"], amount=p["amount"])
            for index, p in enumerate(data["payments"])
        ]
    )
    audit.record(
        "sale.completed",
        actor=actor,
        business=business,
        obj=sale,
        metadata={
            "number": sale.number,
            "location": location.pk,
            "total": total,
            "discount": sum((line["discount"] for line in priced), ZERO),
            "lines": len(priced),
            "methods": sorted({p["method"] for p in data["payments"]}),
        },
    )
    return sale


def reconcile(business=None) -> list[str]:
    """Sales-level checks: totals follow from the lines, payments cover the total, and the stock
    movements of every sale equal what its lines sold."""
    scope = {"business": business} if business is not None else {}
    differences: list[str] = []
    line_sums = {
        r["sale_id"]: r
        for r in SaleLine.objects.filter(
            **({"sale__business": business} if business is not None else {})
        )
        .values("sale_id")
        .annotate(total=Sum("line_total"), quantity=Sum("quantity"))
    }
    pay_sums = {
        r["sale_id"]: r["total"]
        for r in SalePayment.objects.filter(
            **({"sale__business": business} if business is not None else {})
        )
        .values("sale_id")
        .annotate(total=Sum("amount"))
    }
    moved = {
        r["document_id"]: r["total"]
        for r in StockMovement.objects.filter(document_type="sale", **scope)
        .values("document_id")
        .annotate(total=Sum("quantity"))
    }
    for sale in Sale.objects.filter(**scope):
        lines = line_sums.get(sale.pk)
        total = (lines["total"] if lines else ZERO) or ZERO
        quantity = (lines["quantity"] if lines else ZERO) or ZERO
        paid = pay_sums.get(sale.pk, ZERO) or ZERO
        if total != sale.total:
            differences.append(f"S-{sale.number:06d}: total={sale.total} lines={total}")
        if paid - sale.total != sale.change_given:
            differences.append(
                f"S-{sale.number:06d}: paid={paid} total={sale.total} change={sale.change_given}"
            )
        if (moved.get(sale.pk, ZERO) or ZERO) != -quantity:
            differences.append(
                f"S-{sale.number:06d}: sold={quantity} movements={moved.get(sale.pk, ZERO)}"
            )
    return differences
