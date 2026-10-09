"""The purchasing report.

* orders_count / by_status  = every purchase order CREATED in the period, whatever its status
                              (draft and cancelled ones are part of the split).
* ordered_total             = quantity x unit cost over the lines of the period's orders that
                              were actually placed with the supplier (status ordered, partially
                              received or received; not draft, not cancelled).
* deliveries_count          = deliveries RECEIVED in the period (by `received_at`), at the
  received_value              locations in scope; received_value is their cost (the unit cost on
                              the delivery line x quantity).
* by_supplier               = per supplier, the placed orders created in the period (`orders`)
                              and the cost of the period's deliveries against placed orders
                              (`received_value`). A supplier with a delivery but no new order
                              appears with 0 orders. Only placed orders count here, so
                              `received_value` of the suppliers can fall short of the report's
                              `received_value` only by goods received on an order that was
                              cancelled afterwards (they did arrive, so the total keeps them).
* supplier_returns_*        = goods sent back to suppliers in the period, and the credit the
                              deliveries charged for them.

Amounts (`ordered_total`, `received_value`, `supplier_returns_credit`) need
`purchasing.cost.view`; without it the keys are left out. Orders are located where the goods are
to be received.
"""

from django.db.models import Count, DecimalField, ExpressionWrapper, F, Sum

from apps.purchasing.models import (
    Delivery,
    DeliveryLine,
    PurchaseOrder,
    PurchaseOrderLine,
    SupplierReturn,
)

from .scope import ReportContext, Scope, dec, money, round_money

Status = PurchaseOrder.Status
PLACED = (Status.ORDERED, Status.PARTIALLY_RECEIVED, Status.RECEIVED)
OPEN = (Status.ORDERED, Status.PARTIALLY_RECEIVED)

_VALUE = ExpressionWrapper(
    F("quantity") * F("unit_cost"), output_field=DecimalField(max_digits=28, decimal_places=5)
)


def orders(scope: Scope, period):
    return scope.limit(
        PurchaseOrder.objects.filter(business=scope.business, **period.instants("created_at"))
    )


def deliveries(scope: Scope, period):
    return scope.limit(
        Delivery.objects.filter(business=scope.business, **period.instants("received_at")),
        "order__location_id",
    )


def supplier_returns(scope: Scope, period):
    return scope.limit(
        SupplierReturn.objects.filter(business=scope.business, **period.instants("created_at"))
    )


def open_orders_count(scope: Scope) -> int:
    """Orders waiting for goods (ordered or partially received) at the locations in scope."""
    return scope.limit(
        PurchaseOrder.objects.filter(business=scope.business, status__in=OPEN)
    ).count()


def _by_status(scope: Scope, period) -> list[dict]:
    rows = {
        r["status"]: r["count"]
        for r in orders(scope, period).order_by().values("status").annotate(count=Count("id"))
    }
    return [{"status": s, "count": rows[s]} for s in Status.values if s in rows]


def _by_supplier(scope: Scope, period, rights):
    """`(rows, value of ALL the period's deliveries)`. Always the same two queries, so the
    suppliers listed do not depend on the cost right. A supplier is listed when it has a placed
    order in the period or a delivery against one."""
    suppliers: dict = {}

    def row(supplier_id, name):
        return suppliers.setdefault(supplier_id, {"name": name, "orders": 0, "value": dec(0)})

    placed = (
        orders(scope, period)
        .filter(status__in=PLACED)
        .order_by()
        .values("supplier_id", "supplier__name")
        .annotate(count=Count("id"))
    )
    for r in placed:
        row(r["supplier_id"], r["supplier__name"])["orders"] = r["count"]
    arrived = (
        scope.limit(
            DeliveryLine.objects.filter(
                delivery__business=scope.business, **period.instants("delivery__received_at")
            ),
            "delivery__order__location_id",
        )
        .order_by()
        .values(
            "delivery__order__supplier_id",
            "delivery__order__supplier__name",
            "delivery__order__status",
        )
        .annotate(value=Sum(_VALUE))
    )
    exact: dict = {}  # every delivery, whatever became of its order
    for r in arrived:
        supplier = r["delivery__order__supplier_id"]
        exact[supplier] = exact.get(supplier, dec(0)) + dec(r["value"])
        if r["delivery__order__status"] in PLACED:
            row(supplier, r["delivery__order__supplier__name"])["value"] += dec(r["value"])
    total = sum((round_money(value) for value in exact.values()), dec(0))
    ordered = sorted(
        suppliers.items(),
        key=lambda item: (
            -round_money(item[1]["value"]) if rights.purchasing_cost else 0,
            -item[1]["orders"],
            item[1]["name"],
            str(item[0]),
        ),
    )
    rows = []
    for supplier, entry in ordered:
        out = {"supplier": {"id": str(supplier), "name": entry["name"]}, "orders": entry["orders"]}
        if rights.purchasing_cost:
            out["received_value"] = money(entry["value"])
        rows.append(out)
    return rows, total


def purchasing_report(ctx: ReportContext) -> dict:
    scope, period, rights = ctx.scope, ctx.period, ctx.rights
    by_status = _by_status(scope, period)
    by_supplier, received = _by_supplier(scope, period, rights)
    out = {
        **ctx.head(),
        "orders_count": sum(r["count"] for r in by_status),
        "by_status": by_status,
        "deliveries_count": deliveries(scope, period).count(),
    }
    if rights.purchasing_cost:
        lines = scope.limit(
            PurchaseOrderLine.objects.filter(
                order__business=scope.business,
                order__status__in=PLACED,
                **period.instants("order__created_at"),
            ),
            "order__location_id",
        )
        out["ordered_total"] = money(lines.order_by().aggregate(total=Sum(_VALUE))["total"])
        out["received_value"] = money(received)
    out["by_supplier"] = by_supplier
    returned = (
        supplier_returns(scope, period)
        .order_by()
        .aggregate(count=Count("id"), credit=Sum("credit_total"))
    )
    out["supplier_returns_count"] = returned["count"]
    if rights.purchasing_cost:
        out["supplier_returns_credit"] = money(returned["credit"])
    return out
