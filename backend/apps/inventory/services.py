"""The only code that changes stock.

Everything else (opening stock, adjustments, purchase receipts, and later sales, transfers
and returns) calls `post()`. It takes row locks in a fixed order, writes the movements,
keeps the balances and FIFO cost layers in step, and refuses to go below zero.
`reconcile()` proves the three agree.
"""

import uuid
from dataclasses import dataclass, field
from decimal import Decimal

from django.db import transaction
from django.db.models import F, Sum

from apps.audit import services as audit
from apps.catalog.services import check_quantity_precision
from apps.common.errors import ApiError
from apps.common.middleware import current_request_id

from .models import Condition, CostLayer, MovementType, StockBalance, StockMovement

ZERO = Decimal("0")
# Conditions that ordinary documents may post to today. In-transit is reserved for transfers.
POSTABLE_CONDITIONS = (Condition.SELLABLE, Condition.DAMAGED, Condition.INSPECTION)


@dataclass
class Line:
    """One change of stock. A positive `quantity` adds goods and needs `unit_cost` (TMT);
    a negative one removes goods, oldest cost layer first."""

    product: object  # catalog.Product, with its unit
    location: object  # businesses.Location
    quantity: Decimal
    movement_type: str
    unit_cost: Decimal | None = None
    condition: str = Condition.SELLABLE


@dataclass
class Posted:
    movements: list[StockMovement] = field(default_factory=list)

    @property
    def cost(self) -> Decimal:
        """Exact cost of everything this posting removed (positive), for sales margins."""
        return sum((-m.quantity * m.unit_cost for m in self.movements if m.quantity < 0), ZERO)


def _validate(business, line: Line) -> None:
    if line.quantity == 0:
        raise ApiError("validation_error", "A stock line cannot be zero")
    if line.product.business_id != business.pk or line.location.business_id != business.pk:
        # Never reachable through the API (references are business-scoped); a guard for
        # any future caller.
        raise ApiError("validation_error", "Product or location belongs to another business")
    if not line.location.is_active:
        raise ApiError("location_inactive", "This location is not active", status_code=409)
    if line.condition not in Condition.values:
        raise ApiError("validation_error", "Unknown stock condition")
    check_quantity_precision(abs(line.quantity), line.product.unit)
    if line.quantity > 0 and (line.unit_cost is None or line.unit_cost < 0):
        raise ApiError(
            "validation_error",
            "Goods coming in need a unit cost",
            fields={"unit_cost": [{"code": "required", "message": "Required"}]},
        )


def _locked_balances(business, lines: list[Line]) -> dict[tuple, StockBalance]:
    """Create any missing balance rows, then lock them one by one in a fixed order so two
    postings that touch the same rows can never wait on each other in a circle."""
    keys = sorted({(str(x.location.pk), str(x.product.pk), x.condition) for x in lines})
    existing = {
        (str(b.location_id), str(b.product_id), b.condition)
        for b in StockBalance.objects.filter(
            business=business,
            location_id__in={k[0] for k in keys},
            product_id__in={k[1] for k in keys},
        )
    }
    missing = [k for k in keys if k not in existing]
    if missing:
        # A concurrent transaction may create the same row first: ignore_conflicts makes
        # that harmless, and the lock below then serialises us behind it.
        StockBalance.objects.bulk_create(
            [
                StockBalance(
                    business=business, location_id=loc, product_id=prod, condition=condition
                )
                for loc, prod, condition in missing
            ],
            ignore_conflicts=True,
        )
    return {
        key: StockBalance.objects.select_for_update().get(
            business=business, location_id=key[0], product_id=key[1], condition=key[2]
        )
        for key in keys
    }


def post(
    business,
    actor,
    lines: list[Line],
    *,
    document_type: str,
    document_id: uuid.UUID,
    reason: str = "",
) -> Posted:
    """Apply `lines` atomically. Raises `insufficient_stock` (409) if any bucket would go
    below zero; nothing is written in that case."""
    if not lines:
        raise ApiError("validation_error", "Nothing to post")
    with transaction.atomic():
        for line in lines:
            _validate(business, line)
        balances = _locked_balances(business, lines)
        request_id = current_request_id()[:64]
        posted = Posted()

        def movement(line, balance, layer, quantity):
            m = StockMovement.objects.create(
                business=business,
                product=line.product,
                location=line.location,
                condition=line.condition,
                movement_type=line.movement_type,
                quantity=quantity,
                unit_cost=layer.unit_cost,
                layer=layer,
                document_type=document_type,
                document_id=document_id,
                reason=reason,
                actor=actor,
                request_id=request_id,
            )
            posted.movements.append(m)

        for line in lines:
            balance = balances[(str(line.location.pk), str(line.product.pk), line.condition)]
            if line.quantity > 0:
                balance.layer_seq += 1
                layer = CostLayer.objects.create(
                    business=business,
                    balance=balance,
                    layer_no=balance.layer_seq,
                    unit_cost=line.unit_cost,
                    quantity_initial=line.quantity,
                    quantity_remaining=line.quantity,
                )
                balance.quantity += line.quantity
                movement(line, balance, layer, line.quantity)
            else:
                needed = -line.quantity
                if balance.quantity < needed:
                    raise ApiError(
                        "insufficient_stock",
                        "Not enough stock",
                        status_code=409,
                        params={
                            "product": str(line.product.pk),
                            "location": str(line.location.pk),
                            "available": str(balance.quantity),
                            "requested": str(needed),
                        },
                    )
                remaining = needed
                layers = CostLayer.objects.select_for_update().filter(
                    balance=balance, quantity_remaining__gt=0
                )
                for layer in layers.order_by("layer_no"):
                    take = min(layer.quantity_remaining, remaining)
                    layer.quantity_remaining -= take
                    layer.save(update_fields=["quantity_remaining"])
                    movement(line, balance, layer, -take)
                    remaining -= take
                    if remaining == 0:
                        break
                if remaining != 0:  # balance said yes, layers say no: the ledger is damaged
                    raise RuntimeError("stock layers do not cover the balance; run reconcile_stock")
                balance.quantity -= needed
            balance.save(update_fields=["quantity", "layer_seq", "updated_at"])
        return posted


# ---- documents built on post() --------------------------------------------------------------


def post_opening_stock(business, actor, location, rows: list[dict], note: str = "") -> dict:
    """First quantities for a product at a location, entered with their unit cost.
    A product that already has any movement at this location cannot get an opening line;
    corrections go through adjustments."""
    document_id = uuid.uuid4()
    products = [r["product"] for r in rows]
    if len({p.pk for p in products}) != len(products):
        raise ApiError(
            "validation_error",
            "A product appears twice",
            fields={"lines": [{"code": "duplicate_product", "message": "Duplicate product"}]},
        )
    with transaction.atomic():
        for row in rows:
            if not row["product"].is_active:
                raise ApiError(
                    "product_archived",
                    "Archived products cannot be stocked",
                    status_code=409,
                    params={"product": str(row["product"].pk)},
                )
            if StockMovement.objects.filter(
                business=business, product=row["product"], location=location
            ).exists():
                raise ApiError(
                    "opening_stock_exists",
                    "This product already has stock history here; use an adjustment",
                    status_code=409,
                    params={"product": str(row["product"].pk)},
                )
        posted = post(
            business,
            actor,
            [
                Line(
                    product=r["product"],
                    location=location,
                    quantity=r["quantity"],
                    unit_cost=r["unit_cost"],
                    movement_type=MovementType.OPENING,
                )
                for r in rows
            ],
            document_type="opening",
            document_id=document_id,
            reason=note,
        )
        audit.record(
            "stock.opening_posted",
            actor=actor,
            business=business,
            metadata={"document_id": document_id, "location": location.pk, "lines": len(rows)},
        )
    return {"document_id": document_id, "posted": posted}


def post_adjustment(business, actor, location, rows: list[dict], reason: str) -> dict:
    """A correction or write-off. The reason is mandatory and stored on every movement."""
    reason = reason.strip()
    if not reason:
        raise ApiError(
            "validation_error",
            "A reason is required",
            fields={"reason": [{"code": "required", "message": "Required"}]},
        )
    document_id = uuid.uuid4()
    lines = []
    for r in rows:
        incoming = r["direction"] == "in"
        lines.append(
            Line(
                product=r["product"],
                location=location,
                quantity=r["quantity"] if incoming else -r["quantity"],
                unit_cost=r.get("unit_cost") if incoming else None,
                movement_type=(
                    MovementType.ADJUSTMENT_IN if incoming else MovementType.ADJUSTMENT_OUT
                ),
                condition=r.get("condition") or Condition.SELLABLE,
            )
        )
    with transaction.atomic():
        posted = post(
            business,
            actor,
            lines,
            document_type="adjustment",
            document_id=document_id,
            reason=reason,
        )
        audit.record(
            "stock.adjustment_posted",
            actor=actor,
            business=business,
            metadata={
                "document_id": document_id,
                "location": location.pk,
                "lines": len(rows),
                "reason": reason,
            },
        )
    return {"document_id": document_id, "posted": posted}


# ---- reconciliation -------------------------------------------------------------------------


def reconcile(business=None) -> list[str]:
    """Compare balances, movements and cost layers. Returns human-readable differences;
    an empty list means the ledger is consistent."""
    scope = {"business": business} if business is not None else {}
    differences: list[str] = []

    movement_totals = {
        (r["product_id"], r["location_id"], r["condition"]): r["total"]
        for r in StockMovement.objects.filter(**scope)
        .values("product_id", "location_id", "condition")
        .annotate(total=Sum("quantity"))
    }
    layer_totals = {
        (r["balance__product_id"], r["balance__location_id"], r["balance__condition"]): r["total"]
        for r in CostLayer.objects.filter(**scope)
        .values("balance__product_id", "balance__location_id", "balance__condition")
        .annotate(total=Sum("quantity_remaining"))
    }
    balances = {
        (b.product_id, b.location_id, b.condition): b.quantity
        for b in StockBalance.objects.filter(**scope)
    }
    for key in sorted(set(movement_totals) | set(layer_totals) | set(balances), key=str):
        balance = balances.get(key, ZERO)
        moved = movement_totals.get(key, ZERO) or ZERO
        layered = layer_totals.get(key, ZERO) or ZERO
        if not (balance == moved == layered):
            differences.append(
                f"product={key[0]} location={key[1]} condition={key[2]}: "
                f"balance={balance} movements={moved} layers={layered}"
            )

    per_layer = {
        r["layer_id"]: r["total"]
        for r in StockMovement.objects.filter(**scope)
        .values("layer_id")
        .annotate(total=Sum("quantity"))
    }
    for layer in CostLayer.objects.filter(**scope).only("id", "quantity_remaining"):
        moved = per_layer.get(layer.pk, ZERO) or ZERO
        if moved != layer.quantity_remaining:
            differences.append(
                f"layer={layer.pk}: remaining={layer.quantity_remaining} movements={moved}"
            )
    return differences


def stock_values(balance_ids) -> dict:
    """{balance_id: value in TMT} - what the goods in each balance cost, from the layers."""
    return {
        r["balance_id"]: r["value"]
        for r in CostLayer.objects.filter(balance_id__in=balance_ids)
        .values("balance_id")
        .annotate(value=Sum(F("quantity_remaining") * F("unit_cost")))
    }
