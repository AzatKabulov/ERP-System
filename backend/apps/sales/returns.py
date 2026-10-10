"""Customer returns. A return is linked to the sale it came from and can only bring back what is
still returnable (sold minus returned before). It refunds what the customer was charged for
those goods, and puts the goods back on the shelf, into the damaged pile, or aside "awaiting
inspection", each batch at the cost it was sold at, so FIFO costs survive the round trip.

Callers wrap `create_return` and `inspect_return` in `run_idempotent`; the sale row is locked
while the returnable quantity is worked out, so two returns of the same sale can never bring
back more than was sold.
"""

from datetime import date, timedelta
from decimal import Decimal
from zoneinfo import ZoneInfo

from django.db import transaction
from django.db.models import Sum
from django.shortcuts import get_object_or_404
from django.utils import timezone

from apps.audit import services as audit
from apps.businesses.access import require_location
from apps.catalog.services import check_quantity_precision
from apps.common.errors import ApiError
from apps.inventory import services as inventory
from apps.inventory.models import MovementType, StockMovement
from apps.purchasing.services import next_number

from .models import (
    ReturnCondition,
    ReturnInspection,
    Sale,
    SaleReturn,
    SaleReturnLine,
)
from .services import _money

ZERO = Decimal("0")


def _today(business) -> date:
    return timezone.now().astimezone(ZoneInfo(business.timezone)).date()


def sale_day(business, sale) -> date:
    """The day of the sale in the business's time zone (the return window counts from it)."""
    return sale.created_at.astimezone(ZoneInfo(business.timezone)).date()


def return_until(business, sale, line) -> date | None:
    """The last day this line may be returned, or None when there is no limit."""
    if line.return_days is None:
        return None
    return sale_day(business, sale) + timedelta(days=line.return_days)


def _check_window(business, sale, line) -> None:
    until = return_until(business, sale, line)
    if until is None:
        return
    if line.return_days == 0:
        raise ApiError(
            "returns_not_accepted",
            "This product cannot be returned",
            status_code=409,
            params={"product": str(line.product_id)},
        )
    if _today(business) > until:
        raise ApiError(
            "return_window_expired",
            "The time to return this product has passed",
            status_code=409,
            params={"product": str(line.product_id), "until": until.isoformat()},
        )


def _slices(business, sale, line, skip: Decimal, quantity: Decimal) -> list[tuple]:
    """(quantity, unit cost) pieces to bring back: the sale's own FIFO slices of this product
    in the order they were taken, leaving out what earlier returns already brought back."""
    rows = (
        StockMovement.objects.filter(
            business=business,
            document_type="sale",
            document_id=sale.pk,
            product_id=line.product_id,
            quantity__lt=0,
        )
        .order_by("layer__layer_no", "id")
        .values_list("quantity", "unit_cost")
    )
    pieces: list[tuple] = []
    need = quantity
    for movement_quantity, unit_cost in rows:
        available = -movement_quantity
        if skip >= available:
            skip -= available
            continue
        available -= skip
        skip = ZERO
        take = min(available, need)
        pieces.append((take, unit_cost))
        need -= take
        if need == ZERO:
            break
    if need != ZERO:  # cannot happen while the sale row is locked; refuse rather than guess
        raise ApiError("over_return", "Nothing left to return", status_code=409)
    return pieces


def create_return(
    business,
    actor,
    membership,
    sale_id,
    data: dict,
    *,
    warranty_claim_id=None,
    ignore_window: bool = False,
) -> SaleReturn:
    """`data`: {"lines": [{"sale_line", "quantity", "condition"}], "reason", "note"}."""
    reason = (data.get("reason") or "").strip()
    if not reason:
        raise ApiError(
            "validation_error",
            "A reason is required",
            fields={"reason": [{"code": "required", "message": "Required"}]},
        )
    rows = data["lines"]
    if len({str(r["sale_line"]) for r in rows}) != len(rows):
        raise ApiError(
            "validation_error",
            "A line appears twice",
            fields={"lines": [{"code": "duplicate_line", "message": "Duplicate line"}]},
        )
    with transaction.atomic():
        sale = get_object_or_404(Sale.objects.select_for_update(), pk=sale_id, business=business)
        require_location(membership, sale.location_id)
        lines = {str(line.pk): line for line in sale.lines.select_related("product__unit")}
        prior = {
            r["sale_line_id"]: r
            for r in SaleReturnLine.objects.filter(sale_line__sale=sale)
            .values("sale_line_id")
            .annotate(quantity=Sum("quantity"), refunded=Sum("refund_amount"))
        }
        stock_lines: list[inventory.Line] = []
        built: list[dict] = []
        for row in rows:
            line = lines.get(str(row["sale_line"]))
            if line is None:
                raise ApiError(
                    "validation_error",
                    "This line is not part of the sale",
                    fields={"lines": [{"code": "invalid_line", "message": "Invalid line"}]},
                )
            quantity = row["quantity"]
            check_quantity_precision(quantity, line.product.unit)
            before = prior.get(line.pk, {})
            returned = before.get("quantity") or ZERO
            refunded = before.get("refunded") or ZERO
            remaining = line.quantity - returned
            if quantity > remaining:
                raise ApiError(
                    "over_return",
                    "More than can still be returned",
                    status_code=409,
                    params={"product": str(line.product_id), "returnable": str(remaining)},
                )
            if not ignore_window:
                _check_window(business, sale, line)
            if quantity == remaining:
                refund = line.line_total - refunded  # the last piece takes the remainder
            else:
                refund = min(_money(quantity * line.unit_price), line.line_total - refunded)
            refund = max(refund, ZERO)
            pieces = _slices(business, sale, line, returned, quantity)
            for take, unit_cost in pieces:
                stock_lines.append(
                    inventory.Line(
                        product=line.product,
                        location=sale.location,
                        quantity=take,
                        unit_cost=unit_cost,
                        movement_type=MovementType.RETURN_IN,
                        condition=row["condition"],
                    )
                )
            built.append(
                {
                    "line": line,
                    "quantity": quantity,
                    "condition": row["condition"],
                    "refund": refund,
                    "cost": sum((take * cost for take, cost in pieces), ZERO),
                }
            )
        sale_return = SaleReturn(
            business=business,
            sale=sale,
            location=sale.location,
            created_by=actor,
            reason=reason,
            note=(data.get("note") or "").strip(),
            refund_total=sum((b["refund"] for b in built), ZERO),
            payment_method=sale.payment_method,
            warranty_claim_id=warranty_claim_id,
        )
        inventory.post(
            business,
            actor,
            stock_lines,
            document_type="return",
            document_id=sale_return.pk,
            reason=reason,
        )
        sale_return.number = next_number(business, "return")
        sale_return.save(force_insert=True)
        SaleReturnLine.objects.bulk_create(
            [
                SaleReturnLine(
                    sale_return=sale_return,
                    sale_line=b["line"],
                    position=index,
                    product=b["line"].product,
                    sku=b["line"].sku,
                    name=b["line"].name,
                    unit_symbol=b["line"].unit_symbol,
                    unit_decimals=b["line"].unit_decimals,
                    quantity=b["quantity"],
                    condition=b["condition"],
                    refund_amount=b["refund"],
                    cost_total=b["cost"],
                )
                for index, b in enumerate(built)
            ]
        )
        audit.record(
            "sale.returned",
            actor=actor,
            business=business,
            obj=sale_return,
            metadata={
                "number": sale_return.number,
                "sale": sale.number,
                "refund_total": sale_return.refund_total,
                "lines": len(built),
            },
        )
    return sale_return


def inspect_return(business, actor, membership, return_id, rows: list[dict]) -> SaleReturn:
    """Decide what happens to goods that came back "awaiting inspection": each row is
    {"return_line", "outcome" (sellable or damaged), "quantity"}."""
    if not rows:
        raise ApiError(
            "validation_error",
            "Nothing to decide",
            fields={"lines": [{"code": "required", "message": "Required"}]},
        )
    if len({str(r["return_line"]) for r in rows}) != len(rows):
        raise ApiError(
            "validation_error",
            "A line appears twice",
            fields={"lines": [{"code": "duplicate_line", "message": "Duplicate line"}]},
        )
    with transaction.atomic():
        inventory.lock_business_stock(business)
        sale_return = get_object_or_404(
            SaleReturn.objects.select_for_update(), pk=return_id, business=business
        )
        require_location(membership, sale_return.location_id)
        lines = {str(line.pk): line for line in sale_return.lines.select_related("product__unit")}
        decided = {
            r["return_line_id"]: r["total"]
            for r in ReturnInspection.objects.filter(return_line__sale_return=sale_return)
            .values("return_line_id")
            .annotate(total=Sum("quantity"))
        }
        out_lines: list[inventory.Line] = []
        outcome_by_product: dict = {}
        for row in rows:
            line = lines.get(str(row["return_line"]))
            if line is None:
                raise ApiError(
                    "validation_error",
                    "This line is not part of the return",
                    fields={"lines": [{"code": "invalid_line", "message": "Invalid line"}]},
                )
            if line.condition != ReturnCondition.INSPECTION:
                raise ApiError(
                    "not_awaiting_inspection",
                    "These goods were not waiting for inspection",
                    status_code=409,
                    params={"product": str(line.product_id)},
                )
            waiting = line.quantity - (decided.get(line.pk) or ZERO)
            if row["quantity"] > waiting:
                raise ApiError(
                    "over_inspection",
                    "More than is waiting for inspection",
                    status_code=409,
                    params={"product": str(line.product_id), "waiting": str(waiting)},
                )
            check_quantity_precision(row["quantity"], line.product.unit)
            out_lines.append(
                inventory.Line(
                    product=line.product,
                    location=sale_return.location,
                    quantity=-row["quantity"],
                    movement_type=MovementType.INSPECTION_OUT,
                    condition=ReturnCondition.INSPECTION,
                )
            )
            outcome_by_product[line.product_id] = row["outcome"]
        out = inventory.post(
            business,
            actor,
            out_lines,
            document_type="return",
            document_id=sale_return.pk,
            reason="inspection decided",
        )
        inventory.post(
            business,
            actor,
            [
                inventory.Line(
                    product=m.product,
                    location=sale_return.location,
                    quantity=-m.quantity,
                    unit_cost=m.unit_cost,
                    movement_type=MovementType.INSPECTION_IN,
                    condition=outcome_by_product[m.product_id],
                )
                for m in out.movements
                if m.quantity < 0
            ],
            document_type="return",
            document_id=sale_return.pk,
            reason="inspection decided",
        )
        ReturnInspection.objects.bulk_create(
            [
                ReturnInspection(
                    return_line=lines[str(r["return_line"])],
                    outcome=r["outcome"],
                    quantity=r["quantity"],
                    decided_by=actor,
                )
                for r in rows
            ]
        )
        audit.record(
            "return.inspected",
            actor=actor,
            business=business,
            obj=sale_return,
            metadata={"number": sale_return.number, "lines": len(rows)},
        )
    return sale_return


def reconcile(business=None) -> list[str]:
    """Return-level checks: every refund is the sum of its lines, nothing was returned beyond
    what was sold or refunded beyond what was charged, goods awaiting inspection were only
    decided once, and the stock movements of a return equal what it brought back."""
    scope = {"business": business} if business is not None else {}
    differences: list[str] = []
    returns = SaleReturn.objects.filter(**scope)
    sums = {
        r["sale_return_id"]: r
        for r in SaleReturnLine.objects.filter(sale_return__in=returns)
        .values("sale_return_id")
        .annotate(refund=Sum("refund_amount"), quantity=Sum("quantity"))
    }
    moved = {
        r["document_id"]: r["total"]
        for r in StockMovement.objects.filter(document_type="return", **scope)
        .values("document_id")
        .annotate(total=Sum("quantity"))
    }
    for ret in returns:
        line_sums = sums.get(ret.pk, {})
        refund = line_sums.get("refund") or ZERO
        quantity = line_sums.get("quantity") or ZERO
        if refund != ret.refund_total:
            differences.append(f"R-{ret.number:04d}: refund={ret.refund_total} lines={refund}")
        if (moved.get(ret.pk) or ZERO) != quantity:
            differences.append(
                f"R-{ret.number:04d}: returned={quantity} movements={moved.get(ret.pk)}"
            )
    over = (
        SaleReturnLine.objects.filter(sale_return__in=returns)
        .values("sale_line_id", "sale_line__quantity", "sale_line__line_total")
        .annotate(quantity=Sum("quantity"), refund=Sum("refund_amount"))
    )
    for r in over:
        if r["quantity"] > r["sale_line__quantity"] or r["refund"] > r["sale_line__line_total"]:
            differences.append(
                f"sale line {r['sale_line_id']}: returned={r['quantity']} "
                f"of {r['sale_line__quantity']}, refunded={r['refund']}"
            )
    waiting = (
        SaleReturnLine.objects.filter(sale_return__in=returns, condition="inspection")
        .values("pk", "quantity", "sale_return__number")
        .annotate(decided=Sum("inspections__quantity"))
    )
    for r in waiting:
        if (r["decided"] or ZERO) > r["quantity"]:
            differences.append(f"R-{r['sale_return__number']:04d}: inspected more than returned")
    return differences
