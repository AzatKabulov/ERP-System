"""The stock report: what is running low, what the stock is worth, and what moved.

* low stock   = a `ReorderSetting` of an active product whose SELLABLE quantity at that location
                is below its minimum (goods on order are not counted here; the reorder list does
                that). A snapshot of now.
* value       = sum over the `CostLayer` rows with something left of remaining quantity x unit
                cost, per location and condition, in TMT. It is the exact FIFO cost of the goods
                on hand (not an estimate) and includes damaged, awaiting-inspection and
                in-transit goods, each shown under its own condition. A snapshot of now. Needs
                `stock.cost.view`.
* movements   = the period's stock movements grouped by type: how many, how much came in
                (positive quantities) and went out (negative ones, as a positive number).
"""

from decimal import Decimal

from django.db.models import (
    Count,
    DecimalField,
    ExpressionWrapper,
    F,
    OuterRef,
    Q,
    Subquery,
    Sum,
    Value,
)
from django.db.models.functions import Coalesce

from apps.catalog.models import ReorderSetting
from apps.inventory.models import Condition, CostLayer, MovementType, StockBalance, StockMovement

from .scope import ReportContext, Scope, dec, money, qty, round_money

LOW_STOCK_ROWS = 200


def low_stock_settings(scope: Scope):
    on_hand = Coalesce(
        Subquery(
            StockBalance.objects.filter(
                product_id=OuterRef("product_id"),
                location_id=OuterRef("location_id"),
                condition=Condition.SELLABLE,
            ).values("quantity")[:1]
        ),
        Value(Decimal(0), output_field=DecimalField(max_digits=14, decimal_places=3)),
    )
    return scope.limit(
        ReorderSetting.objects.filter(business=scope.business, product__is_active=True)
        .annotate(on_hand=on_hand)
        .filter(on_hand__lt=F("minimum"))
    )


def low_stock_count(scope: Scope) -> int:
    return low_stock_settings(scope).count()


def low_stock(scope: Scope, limit: int | None) -> list[dict]:
    rows = (
        low_stock_settings(scope)
        .select_related("product__unit", "location")
        .order_by("location__name", "product__name", "id")
    )
    if limit is not None:
        rows = rows[:limit]
    return [
        {
            "product": {
                "id": str(r.product_id),
                "sku": r.product.sku,
                "name": r.product.name,
                "unit_symbol": r.product.unit.symbol,
                "unit_decimals": r.product.unit.decimal_places,
            },
            "location": {"id": str(r.location_id), "name": r.location.name},
            "on_hand": qty(r.on_hand),
            "minimum": qty(r.minimum),
            "target": qty(r.target),
        }
        for r in rows
    ]


def inventory_value(scope: Scope) -> dict:
    """`{"total", "by_location": [{"location", "total", "by_condition"}]}` (one query). Each
    location x condition is rounded on its own and the totals are sums of the rounded parts."""
    rows = (
        scope.limit(
            CostLayer.objects.filter(business=scope.business, quantity_remaining__gt=0),
            "balance__location_id",
        )
        .order_by()
        .values("balance__location_id", "balance__location__name", "balance__condition")
        .annotate(
            value=Sum(
                ExpressionWrapper(
                    F("quantity_remaining") * F("unit_cost"),
                    output_field=DecimalField(max_digits=28, decimal_places=5),
                )
            )
        )
    )
    places: dict = {}
    for r in rows:
        place = places.setdefault(
            r["balance__location_id"],
            {"name": r["balance__location__name"], "by_condition": {}},
        )
        place["by_condition"][r["balance__condition"]] = round_money(r["value"])
    by_location = []
    total = Decimal(0)
    for location_id, place in sorted(places.items(), key=lambda p: (p[1]["name"], str(p[0]))):
        parts = {c: place["by_condition"].get(c, Decimal(0)) for c in Condition.values}
        subtotal = sum(parts.values(), Decimal(0))
        total += subtotal
        by_location.append(
            {
                "location": {"id": str(location_id), "name": place["name"]},
                "total": money(subtotal),
                "by_condition": {c: money(v) for c, v in parts.items()},
            }
        )
    return {"total": money(total), "by_location": by_location}


def movements(scope: Scope, period) -> list[dict]:
    rows = {
        r["movement_type"]: r
        for r in scope.limit(
            StockMovement.objects.filter(business=scope.business, **period.instants("created_at"))
        )
        .order_by()
        .values("movement_type")
        .annotate(
            count=Count("id"),
            came_in=Sum("quantity", filter=Q(quantity__gt=0)),
            went_out=Sum("quantity", filter=Q(quantity__lt=0)),
        )
    }
    return [
        {
            "type": kind,
            "count": rows[kind]["count"],
            "quantity_in": qty(rows[kind]["came_in"]),
            "quantity_out": qty(-dec(rows[kind]["went_out"])),
        }
        for kind in MovementType.values
        if kind in rows
    ]


def stock_report(ctx: ReportContext, *, full: bool = False) -> dict:
    """`full` lifts the 200-row cap on the low-stock list (the CSV export is complete)."""
    scope = ctx.scope
    out = {
        **ctx.head(),
        "low_stock": low_stock(scope, None if full else LOW_STOCK_ROWS),
        "low_stock_count": low_stock_count(scope),
    }
    if ctx.rights.stock_cost:
        out["value"] = inventory_value(scope)
    out["movements"] = movements(scope, ctx.period)
    return out
