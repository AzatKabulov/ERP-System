"""The returns report: goods customers brought back, and goods sent back to suppliers.

* returns_count / refund_total = customer returns MADE in the period (by the return's own date,
                                 whenever the sale was) and the money refunded for them.
* by_condition = the returned quantity and refund per condition recorded when the return was
                 taken (sellable, damaged, awaiting inspection); a later inspection decision does
                 not move it. Quantities are summed in each product's own unit.
* by_reason    = the reasons given, as typed, with how many returns and how much refunded; the
                 ten with the biggest refund (all of them in the export).
* supplier_returns = goods sent back to suppliers in the period; the credit needs
                 `purchasing.cost.view`.
"""

from django.db.models import Count, Sum

from apps.sales.models import ReturnCondition

from .purchases import supplier_returns
from .sales import return_lines, returns
from .scope import ReportContext, Scope, money, qty

TOP_REASONS = 10


def _by_condition(scope: Scope, period) -> list[dict]:
    rows = {
        r["condition"]: r
        for r in return_lines(scope, period)
        .order_by()
        .values("condition")
        .annotate(quantity=Sum("quantity"), refund=Sum("refund_amount"))
    }
    return [
        {
            "condition": c,
            "quantity": qty(rows[c]["quantity"]),
            "refund": money(rows[c]["refund"]),
        }
        for c in ReturnCondition.values
        if c in rows
    ]


def _by_reason(scope: Scope, period, limit: int | None) -> list[dict]:
    rows = (
        returns(scope, period)
        .order_by()
        .values("reason")
        .annotate(count=Count("id"), refund=Sum("refund_total"))
        .order_by("-refund", "reason")
    )
    if limit is not None:
        rows = rows[:limit]
    return [
        {"reason": r["reason"], "count": r["count"], "refund": money(r["refund"])} for r in rows
    ]


def returns_report(ctx: ReportContext, *, full: bool = False) -> dict:
    """`full` lifts the ten-reason cap (the CSV export lists every reason)."""
    scope, period = ctx.scope, ctx.period
    made = returns(scope, period).order_by().aggregate(count=Count("id"), total=Sum("refund_total"))
    sent = (
        supplier_returns(scope, period)
        .order_by()
        .aggregate(count=Count("id"), credit=Sum("credit_total"))
    )
    supplier = {"count": sent["count"]}
    if ctx.rights.purchasing_cost:
        supplier["credit"] = money(sent["credit"])
    return {
        **ctx.head(),
        "returns_count": made["count"],
        "refund_total": money(made["total"]),
        "by_condition": _by_condition(scope, period),
        "by_reason": _by_reason(scope, period, None if full else TOP_REASONS),
        "supplier_returns": supplier,
    }
