"""Transfers and stock counts. Every change of stock goes through `inventory.services.post`.

Transfers: dispatch takes the goods out of the source's sellable stock and puts them "in
transit" at the destination with the very same cost layers (so FIFO costs travel with the
goods); receiving moves what arrived into the destination's sellable stock and writes off what
is missing (with a reason); cancelling sends everything back. Goods in transit are not
sellable, so they are never available in two places.

Counts: the quantities the system showed when the count started are the baseline. Sales and
receipts continue during a count (nothing is frozen); lines that moved since the start are
flagged for the approver. Approval posts (counted - baseline) as an adjustment on top of the
current stock, so what happened during the count is kept.

All of it runs under one advisory lock per business: transfers and approvals touch several
stock rows in different orders, and a single queue is the simplest way to rule out deadlocks.
"""

import uuid
from decimal import Decimal

from django.db import transaction
from django.db.models import Sum
from django.shortcuts import get_object_or_404
from django.utils import timezone

from apps.audit import services as audit
from apps.businesses.access import require_location
from apps.businesses.permissions import has_permission
from apps.catalog.services import check_quantity_precision
from apps.common.errors import ApiError
from apps.inventory import services as inventory
from apps.inventory.models import Condition, CostLayer, MovementType, StockBalance, StockMovement
from apps.purchasing.services import next_number

from .models import StockCount, StockCountLine, StockIntake, StockIntakeLine, Transfer, TransferLine

ZERO = Decimal("0")


def _lock(business) -> None:
    """Queue behind any other transfer or count posting of this business (released at the end
    of the transaction)."""
    inventory.lock_business_stock(business)


def _need_reason(reason: str, field: str = "reason") -> str:
    reason = (reason or "").strip()
    if not reason:
        raise ApiError(
            "validation_error",
            "A reason is required",
            fields={field: [{"code": "required", "message": "Required"}]},
        )
    return reason


def _no_duplicates(products) -> None:
    ids = [p.pk for p in products]
    if len(set(ids)) != len(ids):
        raise ApiError(
            "validation_error",
            "A product appears twice",
            fields={"lines": [{"code": "duplicate_product", "message": "Duplicate product"}]},
        )


def _carry(posted, location, condition) -> list[inventory.Line]:
    """Incoming lines that mirror what a posting took out, slice by slice, so every layer keeps
    its own unit cost."""
    return [
        inventory.Line(
            product=m.product,
            location=location,
            quantity=-m.quantity,
            unit_cost=m.unit_cost,
            movement_type=MovementType.TRANSFER_IN,
            condition=condition,
        )
        for m in posted.movements
        if m.quantity < 0 and m.movement_type == MovementType.TRANSFER_OUT
    ]


# ---- transfers ------------------------------------------------------------------------------


def dispatch_transfer(business, actor, membership, data: dict) -> Transfer:
    source, destination = data["from_location"], data["to_location"]
    rows = data["lines"]
    _no_duplicates([r["product"] for r in rows])
    for row in rows:
        if not row["product"].is_active:
            raise ApiError(
                "product_archived",
                "Archived products cannot be moved",
                status_code=409,
                params={"product": str(row["product"].pk)},
            )
    with transaction.atomic():
        _lock(business)
        transfer_id = uuid.uuid4()
        out = inventory.post(
            business,
            actor,
            [
                inventory.Line(
                    product=r["product"],
                    location=source,
                    quantity=-r["quantity"],
                    movement_type=MovementType.TRANSFER_OUT,
                )
                for r in rows
            ],
            document_type="transfer",
            document_id=transfer_id,
        )
        inventory.post(
            business,
            actor,
            _carry(out, destination, Condition.IN_TRANSIT),
            document_type="transfer",
            document_id=transfer_id,
        )
        transfer = Transfer.objects.create(
            id=transfer_id,
            business=business,
            number=next_number(business, "transfer"),
            from_location=source,
            to_location=destination,
            note=data.get("note", ""),
            created_by=actor,
        )
        TransferLine.objects.bulk_create(
            [
                TransferLine(transfer=transfer, product=r["product"], quantity=r["quantity"])
                for r in rows
            ]
        )
        audit.record(
            "transfer.dispatched",
            actor=actor,
            business=business,
            obj=transfer,
            metadata={
                "number": transfer.number,
                "from": source.pk,
                "to": destination.pk,
                "lines": len(rows),
            },
        )
    return transfer


def _open_transfer(business, transfer_id) -> Transfer:
    return get_object_or_404(
        Transfer.objects.select_for_update(), pk=transfer_id, business=business
    )


def _must_be_in_transit(transfer: Transfer, code: str) -> None:
    if transfer.status != Transfer.Status.DISPATCHED:
        raise ApiError(code, "This transfer is no longer in transit", status_code=409)


def receive_transfer(business, actor, membership, transfer_id, data: dict) -> Transfer:
    """`data["lines"]`: optional [{line, quantity}]; lines not listed arrive in full. Anything
    short needs a reason, and the missing quantity is written off."""
    with transaction.atomic():
        _lock(business)
        transfer = _open_transfer(business, transfer_id)
        require_location(membership, transfer.to_location_id)
        _must_be_in_transit(transfer, "transfer_not_receivable")
        lines = list(transfer.lines.select_related("product__unit"))
        arrived = {str(line.pk): line.quantity for line in lines}
        seen = set()
        for row in data.get("lines") or []:
            key = str(row["line"])
            if key not in arrived or key in seen:
                raise ApiError(
                    "validation_error",
                    "Unknown or repeated transfer line",
                    fields={"lines": [{"code": "invalid_line", "message": "Invalid line"}]},
                )
            seen.add(key)
            arrived[key] = row["quantity"]
        short = False
        for line in lines:
            quantity = arrived[str(line.pk)]
            if quantity > line.quantity:
                raise ApiError(
                    "validation_error",
                    "More than was sent",
                    fields={"lines": [{"code": "over_receipt", "message": str(line.quantity)}]},
                )
            if quantity > 0:
                check_quantity_precision(quantity, line.product.unit)
            short = short or quantity < line.quantity
        reason = (data.get("reason") or "").strip()
        if short:
            reason = _need_reason(reason)
        out_lines = []
        for line in lines:
            quantity = arrived[str(line.pk)]
            if quantity > 0:
                out_lines.append(
                    inventory.Line(
                        product=line.product,
                        location=transfer.to_location,
                        quantity=-quantity,
                        movement_type=MovementType.TRANSFER_OUT,
                        condition=Condition.IN_TRANSIT,
                    )
                )
            if quantity < line.quantity:
                out_lines.append(
                    inventory.Line(
                        product=line.product,
                        location=transfer.to_location,
                        quantity=-(line.quantity - quantity),
                        movement_type=MovementType.TRANSFER_LOSS,
                        condition=Condition.IN_TRANSIT,
                    )
                )
        out = inventory.post(
            business,
            actor,
            out_lines,
            document_type="transfer",
            document_id=transfer.pk,
            reason=reason if short else "",
        )
        arrivals = _carry(out, transfer.to_location, Condition.SELLABLE)
        if arrivals:
            inventory.post(
                business, actor, arrivals, document_type="transfer", document_id=transfer.pk
            )
        for line in lines:
            line.received_quantity = arrived[str(line.pk)]
            line.save(update_fields=["received_quantity"])
        transfer.status = Transfer.Status.PARTIALLY_RECEIVED if short else Transfer.Status.RECEIVED
        transfer.received_by = actor
        transfer.received_at = timezone.now()
        transfer.discrepancy_reason = reason if short else ""
        transfer.save()
        audit.record(
            "transfer.received",
            actor=actor,
            business=business,
            obj=transfer,
            metadata={"number": transfer.number, "short": short, "reason": reason},
        )
    return transfer


def cancel_transfer(business, actor, membership, transfer_id, reason: str) -> Transfer:
    """Everything in transit goes back to the source with its own costs."""
    reason = _need_reason(reason)
    with transaction.atomic():
        _lock(business)
        transfer = _open_transfer(business, transfer_id)
        require_location(membership, transfer.from_location_id)
        _must_be_in_transit(transfer, "transfer_not_cancellable")
        lines = list(transfer.lines.select_related("product__unit"))
        out = inventory.post(
            business,
            actor,
            [
                inventory.Line(
                    product=line.product,
                    location=transfer.to_location,
                    quantity=-line.quantity,
                    movement_type=MovementType.TRANSFER_OUT,
                    condition=Condition.IN_TRANSIT,
                )
                for line in lines
            ],
            document_type="transfer",
            document_id=transfer.pk,
            reason=reason,
        )
        inventory.post(
            business,
            actor,
            _carry(out, transfer.from_location, Condition.SELLABLE),
            document_type="transfer",
            document_id=transfer.pk,
            reason=reason,
        )
        transfer.status = Transfer.Status.CANCELLED
        transfer.cancelled_by = actor
        transfer.cancelled_at = timezone.now()
        transfer.cancel_reason = reason
        transfer.save()
        audit.record(
            "transfer.cancelled",
            actor=actor,
            business=business,
            obj=transfer,
            metadata={"number": transfer.number, "reason": reason},
        )
    return transfer


# ---- stock counts ---------------------------------------------------------------------------


def _sellable_now(business, location, product_ids=None) -> dict:
    rows = StockBalance.objects.filter(
        business=business, location=location, condition=Condition.SELLABLE
    )
    if product_ids is not None:
        rows = rows.filter(product_id__in=product_ids)
    return {r.product_id: r.quantity for r in rows}


def moved_since(business, location, since, exclude_document=None) -> dict:
    """Net change of sellable stock per product at `location` since `since`."""
    rows = StockMovement.objects.filter(
        business=business, location=location, condition=Condition.SELLABLE, created_at__gte=since
    )
    if exclude_document is not None:
        rows = rows.exclude(document_id=exclude_document)
    return {
        r["product_id"]: r["total"]
        for r in rows.values("product_id").annotate(total=Sum("quantity"))
    }


def _baseline(business, count: StockCount, product_ids) -> dict:
    """What the system showed for each product when the count started: the stock now, less
    whatever moved since."""
    now = _sellable_now(business, count.location, product_ids)
    moved = moved_since(business, count.location, count.started_at, exclude_document=count.pk)
    return {pid: now.get(pid, ZERO) - moved.get(pid, ZERO) for pid in product_ids}


def start_count(business, actor, membership, data: dict) -> StockCount:
    location = data["location"]
    require_location(membership, location.pk)
    if not location.is_active:
        raise ApiError("location_inactive", "This location is not active", status_code=409)
    scope = data["scope"]
    products = list(data.get("products") or [])
    if scope == StockCount.Scope.PARTIAL:
        if not products:
            raise ApiError(
                "validation_error",
                "Choose the products to count",
                fields={"products": [{"code": "required", "message": "Required"}]},
            )
        _no_duplicates(products)
    with transaction.atomic():
        count = StockCount.objects.create(
            business=business,
            number=next_number(business, "count"),
            location=location,
            scope=scope,
            note=data.get("note", ""),
            created_by=actor,
            started_at=timezone.now(),
        )
        if scope == StockCount.Scope.FULL:
            ids = list(
                StockBalance.objects.filter(
                    business=business,
                    location=location,
                    condition=Condition.SELLABLE,
                    quantity__gt=0,
                    product__is_active=True,
                ).values_list("product_id", flat=True)
            )
        else:
            for product in products:
                if not product.is_active:
                    raise ApiError(
                        "product_archived",
                        "Archived products cannot be counted",
                        status_code=409,
                        params={"product": str(product.pk)},
                    )
            ids = [p.pk for p in products]
        baseline = _baseline(business, count, ids)
        StockCountLine.objects.bulk_create(
            [
                StockCountLine(count=count, product_id=pid, baseline_quantity=baseline[pid])
                for pid in ids
            ]
        )
        audit.record(
            "count.started",
            actor=actor,
            business=business,
            obj=count,
            metadata={"number": count.number, "location": location.pk, "lines": len(ids)},
        )
    return count


def _count_for_update(business, count_id) -> StockCount:
    return get_object_or_404(StockCount.objects.select_for_update(), pk=count_id, business=business)


def _must_be(count: StockCount, status: str, code: str) -> None:
    if count.status != status:
        raise ApiError(code, "This count is not in the right state", status_code=409)


def enter_counts(business, actor, membership, count_id, rows: list[dict]) -> StockCount:
    """Record counted quantities (by hand or scan). A product that was not on the list is
    added with the quantity the system showed at the start."""
    _no_duplicates([r["product"] for r in rows])
    with transaction.atomic():
        count = _count_for_update(business, count_id)
        require_location(membership, count.location_id)
        _must_be(count, StockCount.Status.OPEN, "count_not_open")
        existing = {line.product_id: line for line in count.lines.all()}
        fresh = [r["product"] for r in rows if r["product"].pk not in existing]
        baseline = _baseline(business, count, [p.pk for p in fresh]) if fresh else {}
        for row in rows:
            product = row["product"]
            if not product.is_active:
                raise ApiError(
                    "product_archived",
                    "Archived products cannot be counted",
                    status_code=409,
                    params={"product": str(product.pk)},
                )
            check_quantity_precision(row["counted_quantity"], product.unit)
            line = existing.get(product.pk)
            if line is None:
                line = StockCountLine(
                    count=count, product=product, baseline_quantity=baseline[product.pk]
                )
            line.counted_quantity = row["counted_quantity"]
            if row.get("note") is not None:
                line.note = row["note"]
            line.save()
    return count


def submit_count(business, actor, membership, count_id) -> StockCount:
    with transaction.atomic():
        count = _count_for_update(business, count_id)
        require_location(membership, count.location_id)
        _must_be(count, StockCount.Status.OPEN, "count_not_open")
        if not count.lines.filter(counted_quantity__isnull=False).exists():
            raise ApiError("count_empty", "Nothing has been counted yet", status_code=409)
        count.status = StockCount.Status.SUBMITTED
        count.submitted_by = actor
        count.submitted_at = timezone.now()
        count.save()
        audit.record(
            "count.submitted",
            actor=actor,
            business=business,
            obj=count,
            metadata={"number": count.number},
        )
    return count


def _surplus_cost(business, product, location) -> Decimal:
    """Unit cost for goods found that the system did not know about: the latest layer here,
    else the latest anywhere, else the product's default purchase cost, else zero (provisional,
    PLAN.md D7)."""
    layers = CostLayer.objects.filter(business=business, balance__product=product)
    here = layers.filter(balance__location=location).order_by("-created_at").first()
    layer = here or layers.order_by("-created_at").first()
    if layer is not None:
        return layer.unit_cost
    return product.default_purchase_cost or ZERO


def approve_count(business, actor, membership, count_id, reason: str) -> StockCount:
    """Post the differences (counted - baseline) as adjustments; the approver explains them."""
    with transaction.atomic():
        _lock(business)
        count = _count_for_update(business, count_id)
        require_location(membership, count.location_id)
        _must_be(count, StockCount.Status.SUBMITTED, "count_not_submitted")
        lines = list(count.lines.select_related("product__unit"))
        deltas = [
            (line, line.counted_quantity - line.baseline_quantity)
            for line in lines
            if line.counted_quantity is not None and line.counted_quantity != line.baseline_quantity
        ]
        reason = (reason or "").strip()
        if deltas:
            reason = _need_reason(reason)
            inventory.post(
                business,
                actor,
                [
                    inventory.Line(
                        product=line.product,
                        location=count.location,
                        quantity=delta,
                        unit_cost=(
                            _surplus_cost(business, line.product, count.location)
                            if delta > 0
                            else None
                        ),
                        movement_type=(
                            MovementType.ADJUSTMENT_IN if delta > 0 else MovementType.ADJUSTMENT_OUT
                        ),
                    )
                    for line, delta in deltas
                ],
                document_type="count",
                document_id=count.pk,
                reason=f"Stock count C-{count.number:04d}: {reason}",
            )
        count.status = StockCount.Status.APPROVED
        count.decided_by = actor
        count.decided_at = timezone.now()
        count.decision_reason = reason
        count.save()
        audit.record(
            "count.approved",
            actor=actor,
            business=business,
            obj=count,
            metadata={"number": count.number, "differences": len(deltas), "reason": reason},
        )
    return count


def cancel_count(business, actor, membership, count_id, reason: str = "") -> StockCount:
    with transaction.atomic():
        count = _count_for_update(business, count_id)
        require_location(membership, count.location_id)
        if count.status not in (StockCount.Status.OPEN, StockCount.Status.SUBMITTED):
            raise ApiError("count_not_cancellable", "This count is closed", status_code=409)
        count.status = StockCount.Status.CANCELLED
        count.decided_by = actor
        count.decided_at = timezone.now()
        count.decision_reason = (reason or "").strip()
        count.save()
        audit.record(
            "count.cancelled",
            actor=actor,
            business=business,
            obj=count,
            metadata={"number": count.number, "reason": count.decision_reason},
        )
    return count


# ---- receiving by scanning ------------------------------------------------------------------


def receive_intake(business, actor, membership, data: dict) -> StockIntake:
    """Put counted goods on the shelf without a purchase order. One document, one posting: every
    line arrives or none does. A unit cost is optional; only a role that may see costs can enter
    one (the others receive without money, as a warehouse keeper does)."""
    location, rows = data["location"], data["lines"]
    _no_duplicates([r["product"] for r in rows])
    explicit = any(r.get("unit_cost") is not None for r in rows)
    if explicit and not has_permission(membership.role, "stock.cost.view"):
        raise ApiError("permission_denied", "Your role cannot enter costs", status_code=403)
    for row in rows:
        if not row["product"].is_active:
            raise ApiError(
                "product_archived",
                "Archived products cannot be received",
                status_code=409,
                params={"product": str(row["product"].pk)},
            )
    with transaction.atomic():
        intake = StockIntake.objects.create(
            business=business,
            number=next_number(business, "intake"),
            location=location,
            note=data["note"].strip(),
            created_by=actor,
        )
        lines = []
        for position, row in enumerate(rows, start=1):
            given = row.get("unit_cost")
            cost = given if given is not None else (row["product"].default_purchase_cost or ZERO)
            lines.append(
                StockIntakeLine(
                    intake=intake,
                    position=position,
                    product=row["product"],
                    quantity=row["quantity"],
                    unit_cost=cost,
                    cost_known=given is not None,
                )
            )
        StockIntakeLine.objects.bulk_create(lines)
        inventory.post(
            business,
            actor,
            [
                inventory.Line(
                    product=line.product,
                    location=location,
                    quantity=line.quantity,
                    unit_cost=line.unit_cost,
                    movement_type=MovementType.INTAKE,
                )
                for line in lines
            ],
            document_type="intake",
            document_id=intake.pk,
        )
        audit.record(
            "stock.intake_posted",
            actor=actor,
            business=business,
            metadata={
                "number": f"IN-{intake.number:04d}",
                "location": location.pk,
                "lines": len(lines),
                "units": str(sum((line.quantity for line in lines), ZERO)),
            },
        )
    return intake


# ---- reconciliation -------------------------------------------------------------------------


def reconcile(business=None) -> list[str]:
    """Transfers: the movements of each transfer must add up. Goods only change places, so the
    net is zero (minus what was written off as missing), and goods still in transit are exactly
    what a dispatched transfer sent."""
    scope = {"business": business} if business is not None else {}
    differences: list[str] = []
    transfers = {t.pk: t for t in Transfer.objects.filter(**scope)}
    net = {
        r["document_id"]: r["total"]
        for r in StockMovement.objects.filter(document_type="transfer", **scope)
        .values("document_id")
        .annotate(total=Sum("quantity"))
    }
    transit = {
        r["document_id"]: r["total"]
        for r in StockMovement.objects.filter(
            document_type="transfer", condition=Condition.IN_TRANSIT, **scope
        )
        .values("document_id")
        .annotate(total=Sum("quantity"))
    }
    for pk, transfer in transfers.items():
        sent = sum((line.quantity for line in transfer.lines.all()), ZERO)
        got = sum((line.received_quantity or ZERO for line in transfer.lines.all()), ZERO)
        label = f"T-{transfer.number:04d}"
        if transfer.status == Transfer.Status.DISPATCHED:
            expected_net, expected_transit = ZERO, sent
        elif transfer.status == Transfer.Status.CANCELLED:
            expected_net, expected_transit = ZERO, ZERO
        else:
            expected_net, expected_transit = -(sent - got), ZERO
        if (net.get(pk) or ZERO) != expected_net:
            differences.append(
                f"{label}: movements net {net.get(pk) or ZERO}, expected {expected_net}"
            )
        if (transit.get(pk) or ZERO) != expected_transit:
            differences.append(
                f"{label}: in transit {transit.get(pk) or ZERO}, expected {expected_transit}"
            )
    return differences + _reconcile_intakes(scope)


def _reconcile_intakes(scope: dict) -> list[str]:
    """Receiving by scanning: each line must have put exactly its quantity on the shelf."""
    posted = {
        (r["document_id"], r["product_id"]): r["total"]
        for r in StockMovement.objects.filter(document_type="intake", **scope)
        .values("document_id", "product_id")
        .annotate(total=Sum("quantity"))
    }
    differences = []
    expected_keys = set()
    for line in StockIntakeLine.objects.filter(
        **{f"intake__{k}": v for k, v in scope.items()}
    ).select_related("intake"):
        key = (line.intake_id, line.product_id)
        expected_keys.add(key)
        if (posted.get(key) or ZERO) != line.quantity:
            differences.append(
                f"IN-{line.intake.number:04d}: product {line.product_id} received "
                f"{posted.get(key) or ZERO}, the document says {line.quantity}"
            )
    for key in sorted(set(posted) - expected_keys, key=str):
        differences.append(f"intake movements without a document line: {key[0]} / {key[1]}")
    return differences
