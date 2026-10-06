"""Purchase orders and receiving.

A purchase order never changes stock. Only a delivery does, and only through the inventory
service, so the ledger, balances and FIFO cost layers stay in step. Every command locks the
order row first, which makes concurrent receipts of the same order take turns.
"""

from decimal import ROUND_HALF_UP, Decimal

from django.db import transaction
from django.db.models import Sum
from django.shortcuts import get_object_or_404
from django.utils import timezone

from apps.audit import services as audit
from apps.catalog.services import check_quantity_precision
from apps.common.errors import ApiError
from apps.inventory import services as inventory
from apps.inventory.models import Condition, MovementType, StockMovement

from .models import (
    Delivery,
    DeliveryLine,
    DocumentCounter,
    PurchaseOrder,
    PurchaseOrderLine,
    Supplier,
)

ZERO = Decimal("0")
CENT = Decimal("0.01")
Status = PurchaseOrder.Status
OPEN_STATUSES = (Status.ORDERED, Status.PARTIALLY_RECEIVED)


def line_total(quantity: Decimal, unit_cost: Decimal) -> Decimal:
    return (quantity * unit_cost).quantize(CENT, rounding=ROUND_HALF_UP)


def next_number(business, kind: str) -> int:
    DocumentCounter.objects.bulk_create(
        [DocumentCounter(business=business, kind=kind)], ignore_conflicts=True
    )
    counter = DocumentCounter.objects.select_for_update().get(business=business, kind=kind)
    counter.last_value += 1
    counter.save(update_fields=["last_value"])
    return counter.last_value


def _lock_order(business, order_id) -> PurchaseOrder:
    return get_object_or_404(
        PurchaseOrder.objects.select_for_update(), pk=order_id, business=business
    )


def _check_parties(supplier: Supplier, location) -> None:
    if not supplier.is_active:
        raise ApiError(
            "validation_error",
            "Inactive supplier",
            fields={"supplier": [{"code": "inactive_reference", "message": "Inactive"}]},
        )
    if not location.is_active:
        raise ApiError(
            "validation_error",
            "Inactive location",
            fields={"location": [{"code": "inactive_reference", "message": "Inactive"}]},
        )


def _check_lines(rows: list[dict]) -> None:
    products = [r["product"].pk for r in rows]
    if len(set(products)) != len(products):
        raise ApiError(
            "validation_error",
            "A product appears twice",
            fields={"lines": [{"code": "duplicate_product", "message": "Duplicate product"}]},
        )
    for row in rows:
        if not row["product"].is_active:
            raise ApiError(
                "product_archived",
                "Archived products cannot be ordered",
                status_code=409,
                params={"product": str(row["product"].pk)},
            )
        check_quantity_precision(row["quantity"], row["product"].unit)


def _write_lines(order: PurchaseOrder, rows: list[dict]) -> None:
    PurchaseOrderLine.objects.bulk_create(
        [
            PurchaseOrderLine(
                order=order,
                product=row["product"],
                position=index,
                quantity=row["quantity"],
                unit_cost=row["unit_cost"],
            )
            for index, row in enumerate(rows)
        ]
    )


@transaction.atomic
def create_order(business, actor, data: dict) -> PurchaseOrder:
    rows = data.get("lines", [])
    _check_parties(data["supplier"], data["location"])
    _check_lines(rows)
    order = PurchaseOrder.objects.create(
        business=business,
        number=next_number(business, "purchase_order"),
        supplier=data["supplier"],
        location=data["location"],
        expected_date=data.get("expected_date"),
        notes=data.get("notes", ""),
        created_by=actor,
    )
    _write_lines(order, rows)
    audit.record(
        "purchase_order.created",
        actor=actor,
        business=business,
        obj=order,
        metadata={"number": order.number, "lines": len(rows)},
    )
    return order


@transaction.atomic
def update_order(business, actor, order_id, data: dict) -> PurchaseOrder:
    order = _lock_order(business, order_id)
    if order.status != Status.DRAFT:
        raise ApiError(
            "order_not_draft",
            "Only a draft order can be edited",
            status_code=409,
            params={"status": order.status},
        )
    supplier = data.get("supplier", order.supplier)
    location = data.get("location", order.location)
    _check_parties(supplier, location)
    order.supplier, order.location = supplier, location
    for name in ("expected_date", "notes"):
        if name in data:
            setattr(order, name, data[name])
    order.save()
    if "lines" in data:
        _check_lines(data["lines"])
        order.lines.all().delete()
        _write_lines(order, data["lines"])
    audit.record(
        "purchase_order.updated",
        actor=actor,
        business=business,
        obj=order,
        metadata={"number": order.number},
    )
    return order


@transaction.atomic
def submit_order(business, actor, order_id) -> PurchaseOrder:
    order = _lock_order(business, order_id)
    if order.status != Status.DRAFT:
        raise ApiError(
            "order_not_draft",
            "Only a draft order can be submitted",
            status_code=409,
            params={"status": order.status},
        )
    if not order.lines.exists():
        raise ApiError("order_has_no_lines", "Add at least one line first", status_code=409)
    _check_parties(order.supplier, order.location)
    order.status = Status.ORDERED
    order.ordered_at = timezone.now()
    order.save(update_fields=["status", "ordered_at", "updated_at"])
    audit.record(
        "purchase_order.submitted",
        actor=actor,
        business=business,
        obj=order,
        metadata={"number": order.number},
    )
    return order


@transaction.atomic
def cancel_order(business, actor, order_id, reason: str = "") -> PurchaseOrder:
    """Cancelling stops what is still outstanding; goods already received stay received."""
    order = _lock_order(business, order_id)
    if order.status not in (Status.DRAFT, *OPEN_STATUSES):
        raise ApiError(
            "order_not_cancellable",
            "This order can no longer be cancelled",
            status_code=409,
            params={"status": order.status},
        )
    order.status = Status.CANCELLED
    order.cancelled_at = timezone.now()
    order.cancel_reason = reason.strip()
    order.save(update_fields=["status", "cancelled_at", "cancel_reason", "updated_at"])
    audit.record(
        "purchase_order.cancelled",
        actor=actor,
        business=business,
        obj=order,
        metadata={"number": order.number, "reason": order.cancel_reason},
    )
    return order


@transaction.atomic
def receive(business, actor, order_id, rows: list[dict], note: str = "") -> Delivery:
    """Record a (possibly partial) delivery and add the goods to stock at the order's
    location, each line at the cost on the order. Receiving more than is outstanding is
    refused. Callers wrap this in run_idempotent so a retry never receives twice."""
    order = _lock_order(business, order_id)
    if order.status not in OPEN_STATUSES:
        raise ApiError(
            "order_not_receivable",
            "This order is not open for receiving",
            status_code=409,
            params={"status": order.status},
        )
    lines = {
        line.pk: line
        for line in order.lines.select_for_update().select_related("product__unit").order_by("id")
    }
    if not rows:
        raise ApiError("validation_error", "Nothing to receive")
    seen: set = set()
    stock_lines = []
    for row in rows:
        line = lines.get(row["order_line"])
        if line is None:
            raise ApiError(
                "validation_error",
                "Unknown order line",
                fields={"lines": [{"code": "unknown_line", "message": str(row["order_line"])}]},
            )
        if line.pk in seen:
            raise ApiError(
                "validation_error",
                "A line appears twice",
                fields={"lines": [{"code": "duplicate_line", "message": "Duplicate line"}]},
            )
        seen.add(line.pk)
        check_quantity_precision(row["quantity"], line.product.unit)
        if row["quantity"] > line.outstanding:
            raise ApiError(
                "over_receipt",
                "More than is still outstanding on this line",
                status_code=409,
                params={
                    "line": str(line.pk),
                    "product": str(line.product_id),
                    "outstanding": str(line.outstanding),
                    "requested": str(row["quantity"]),
                },
            )
    delivery = Delivery.objects.create(
        business=business,
        order=order,
        number=order.deliveries.count() + 1,
        received_by=actor,
        note=note,
    )
    for row in rows:
        line = lines[row["order_line"]]
        DeliveryLine.objects.create(
            delivery=delivery, order_line=line, quantity=row["quantity"], unit_cost=line.unit_cost
        )
        stock_lines.append(
            inventory.Line(
                product=line.product,
                location=order.location,
                quantity=row["quantity"],
                unit_cost=line.unit_cost,
                movement_type=MovementType.RECEIPT,
                condition=Condition.SELLABLE,
            )
        )
        line.received_quantity += row["quantity"]
        line.save(update_fields=["received_quantity"])
    inventory.post(
        business,
        actor,
        stock_lines,
        document_type="delivery",
        document_id=delivery.pk,
        reason=note,
    )
    order.status = (
        Status.RECEIVED
        if all(line.outstanding == 0 for line in lines.values())
        else Status.PARTIALLY_RECEIVED
    )
    order.save(update_fields=["status", "updated_at"])
    audit.record(
        "purchase_order.received",
        actor=actor,
        business=business,
        obj=order,
        metadata={
            "number": order.number,
            "delivery": delivery.number,
            "lines": len(rows),
            "status": order.status,
        },
    )
    return delivery


def reconcile(business=None) -> list[str]:
    """Order-level checks: received quantities equal what the deliveries recorded, the
    status follows from the quantities, and each delivery's stock movements match it."""
    scope = {"business": business} if business is not None else {}
    differences: list[str] = []
    delivered = {
        r["order_line_id"]: r["total"]
        for r in DeliveryLine.objects.filter(
            **({"delivery__business": business} if business is not None else {})
        )
        .values("order_line_id")
        .annotate(total=Sum("quantity"))
    }
    orders = PurchaseOrder.objects.filter(**scope).prefetch_related("lines")
    for order in orders:
        lines = list(order.lines.all())
        for line in lines:
            total = delivered.get(line.pk, ZERO) or ZERO
            if total != line.received_quantity:
                differences.append(
                    f"PO-{order.number} line={line.pk}: received={line.received_quantity} "
                    f"deliveries={total}"
                )
        if order.status in (Status.ORDERED, Status.PARTIALLY_RECEIVED, Status.RECEIVED):
            if lines and all(line.outstanding == 0 for line in lines):
                expected = Status.RECEIVED
            elif any(line.received_quantity > 0 for line in lines):
                expected = Status.PARTIALLY_RECEIVED
            else:
                expected = Status.ORDERED
            if order.status != expected:
                differences.append(f"PO-{order.number}: status={order.status} expected={expected}")
    moved = {
        r["document_id"]: r["total"]
        for r in StockMovement.objects.filter(document_type="delivery", **scope)
        .values("document_id")
        .annotate(total=Sum("quantity"))
    }
    per_delivery = {
        r["delivery_id"]: r["total"]
        for r in DeliveryLine.objects.filter(
            **({"delivery__business": business} if business is not None else {})
        )
        .values("delivery_id")
        .annotate(total=Sum("quantity"))
    }
    for delivery_id, total in per_delivery.items():
        if (moved.get(delivery_id, ZERO) or ZERO) != total:
            differences.append(
                f"delivery={delivery_id}: lines={total} movements={moved.get(delivery_id, ZERO)}"
            )
    return differences
