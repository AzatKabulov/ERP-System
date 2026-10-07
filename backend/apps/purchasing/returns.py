"""Returns to a supplier. A return is linked to the delivery the goods came with and can only
send back what that delivery brought and has not been returned already. Stock leaves through
the inventory service (so it cannot go below zero, and the oldest cost layers are used); the
credit shown is what the delivery charged for the goods.

Callers wrap `return_to_supplier` in `run_idempotent`.
"""

from django.db import transaction
from django.db.models import Sum
from django.shortcuts import get_object_or_404

from apps.audit import services as audit
from apps.businesses.access import require_location
from apps.catalog.services import check_quantity_precision
from apps.common.errors import ApiError
from apps.inventory import services as inventory
from apps.inventory.models import MovementType, StockMovement

from .models import Delivery, DeliveryLine, SupplierReturn, SupplierReturnLine
from .services import ZERO, line_total, next_number


def return_to_supplier(business, actor, membership, data: dict) -> SupplierReturn:
    """`data`: {"delivery", "lines": [{"delivery_line", "quantity", "condition"}], "reason",
    "note"}; `condition` is where the goods are taken from (sellable or damaged)."""
    reason = (data.get("reason") or "").strip()
    if not reason:
        raise ApiError(
            "validation_error",
            "A reason is required",
            fields={"reason": [{"code": "required", "message": "Required"}]},
        )
    rows = data["lines"]
    if len({str(r["delivery_line"]) for r in rows}) != len(rows):
        raise ApiError(
            "validation_error",
            "A line appears twice",
            fields={"lines": [{"code": "duplicate_line", "message": "Duplicate line"}]},
        )
    with transaction.atomic():
        delivery = get_object_or_404(
            Delivery.objects.select_for_update().select_related(
                "order__supplier", "order__location"
            ),
            pk=data["delivery"].pk,
            business=business,
        )
        location = delivery.order.location
        require_location(membership, location.pk)
        lines = {
            str(line.pk): line
            for line in DeliveryLine.objects.filter(delivery=delivery).select_related(
                "order_line__product__unit"
            )
        }
        returned = {
            r["delivery_line_id"]: r["total"]
            for r in SupplierReturnLine.objects.filter(delivery_line__delivery=delivery)
            .values("delivery_line_id")
            .annotate(total=Sum("quantity"))
        }
        stock_lines: list[inventory.Line] = []
        credit = ZERO
        built = []
        for row in rows:
            line = lines.get(str(row["delivery_line"]))
            if line is None:
                raise ApiError(
                    "validation_error",
                    "This line is not part of the delivery",
                    fields={"lines": [{"code": "invalid_line", "message": "Invalid line"}]},
                )
            product = line.order_line.product
            quantity = row["quantity"]
            check_quantity_precision(quantity, product.unit)
            remaining = line.quantity - (returned.get(line.pk) or ZERO)
            if quantity > remaining:
                raise ApiError(
                    "over_return",
                    "More than can still be returned",
                    status_code=409,
                    params={"product": str(product.pk), "returnable": str(remaining)},
                )
            stock_lines.append(
                inventory.Line(
                    product=product,
                    location=location,
                    quantity=-quantity,
                    movement_type=MovementType.SUPPLIER_RETURN,
                    condition=row["condition"],
                )
            )
            credit += line_total(quantity, line.unit_cost)
            built.append((line, product, quantity, row["condition"]))
        supplier_return = SupplierReturn(
            business=business,
            supplier=delivery.order.supplier,
            delivery=delivery,
            location=location,
            created_by=actor,
            reason=reason,
            note=(data.get("note") or "").strip(),
            credit_total=credit,
        )
        posted = inventory.post(
            business,
            actor,
            stock_lines,
            document_type="supplier_return",
            document_id=supplier_return.pk,
            reason=reason,
        )
        cost_by_product: dict = {}
        for m in posted.movements:
            cost_by_product[m.product_id] = cost_by_product.get(m.product_id, ZERO) + (
                -m.quantity * m.unit_cost
            )
        supplier_return.number = next_number(business, "supplier_return")
        supplier_return.save(force_insert=True)
        SupplierReturnLine.objects.bulk_create(
            [
                SupplierReturnLine(
                    supplier_return=supplier_return,
                    delivery_line=line,
                    product=product,
                    quantity=quantity,
                    condition=condition,
                    unit_cost=line.unit_cost,
                    cost_total=cost_by_product[product.pk],
                )
                for line, product, quantity, condition in built
            ]
        )
        audit.record(
            "supplier_return.created",
            actor=actor,
            business=business,
            obj=supplier_return,
            metadata={
                "number": supplier_return.number,
                "delivery": delivery.pk,
                "credit_total": credit,
                "lines": len(built),
            },
        )
    return supplier_return


def reconcile(business=None) -> list[str]:
    """Each credit is the sum of its lines, nothing was sent back beyond what a delivery
    brought, and the stock movements of a return equal what it sent back."""
    scope = {"business": business} if business is not None else {}
    differences: list[str] = []
    returns = SupplierReturn.objects.filter(**scope)
    sums = {
        r["supplier_return_id"]: r["quantity"]
        for r in SupplierReturnLine.objects.filter(supplier_return__in=returns)
        .values("supplier_return_id")
        .annotate(quantity=Sum("quantity"))
    }
    moved = {
        r["document_id"]: r["total"]
        for r in StockMovement.objects.filter(document_type="supplier_return", **scope)
        .values("document_id")
        .annotate(total=Sum("quantity"))
    }
    for ret in returns:
        if -(moved.get(ret.pk) or ZERO) != (sums.get(ret.pk) or ZERO):
            differences.append(
                f"SR-{ret.number:04d}: returned={sums.get(ret.pk)} movements={moved.get(ret.pk)}"
            )
    over = (
        SupplierReturnLine.objects.filter(supplier_return__in=returns)
        .values("delivery_line_id", "delivery_line__quantity")
        .annotate(quantity=Sum("quantity"))
    )
    for r in over:
        if r["quantity"] > r["delivery_line__quantity"]:
            differences.append(
                f"delivery line {r['delivery_line_id']}: returned={r['quantity']} "
                f"of {r['delivery_line__quantity']}"
            )
    return differences
