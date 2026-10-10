"""Sales figures and the sales report.

Definitions (they are kept apart on purpose: revenue, gross profit, expenses and the result are
four different measures):

* revenue      = sum of `Sale.total` of the sales made in the period.
* refunds      = sum of `SaleReturn.refund_total` of the returns made in the period, by the
                 return's OWN date, whenever the sale was made.
* net_sales    = revenue - refunds.
* cost_of_goods = sum of `SaleLine.cost_total` of the period's sales MINUS sum of
                 `SaleReturnLine.cost_total` of the period's returns (returned goods carry their
                 cost back, in any condition). Exact FIFO cost, rounded half up once.
* gross_profit = net_sales - cost_of_goods.

Cost of goods and gross profit need `sales.cost.view`; without it the keys are left out.
Days are calendar days in the business time zone. `top_products` ranks the period's sale lines
by `line_total` and does not net out returns.
"""

from django.db.models import Count, Sum
from django.db.models.functions import TruncDate

from apps.sales.models import PaymentMethod, Sale, SaleLine, SaleReturn, SaleReturnLine

from .scope import ReportContext, Scope, dec, money, qty, round_money

TOP_PRODUCTS = 10


def sales(scope: Scope, period):
    return scope.limit(
        Sale.objects.filter(business=scope.business, **period.instants("created_at"))
    )


def returns(scope: Scope, period):
    return scope.limit(
        SaleReturn.objects.filter(business=scope.business, **period.instants("created_at"))
    )


def sale_lines(scope: Scope, period):
    return scope.limit(
        SaleLine.objects.filter(
            sale__business=scope.business, **period.instants("sale__created_at")
        ),
        "sale__location_id",
    )


def return_lines(scope: Scope, period):
    return scope.limit(
        SaleReturnLine.objects.filter(
            sale_return__business=scope.business, **period.instants("sale_return__created_at")
        ),
        "sale_return__location_id",
    )


def figures(scope: Scope, period, rights) -> dict:
    """revenue, refunds, net_sales and the two counts; with `rights.sales_cost` also
    cost_of_goods and gross_profit. Four queries at most, whatever the number of sales."""
    made = sales(scope, period).order_by().aggregate(count=Count("id"), total=Sum("total"))
    given = (
        returns(scope, period).order_by().aggregate(count=Count("id"), total=Sum("refund_total"))
    )
    revenue, refunds = round_money(made["total"]), round_money(given["total"])
    out = {
        "revenue": str(revenue),
        "refunds": str(refunds),
        "net_sales": str(revenue - refunds),
        "sales_count": made["count"],
        "returns_count": given["count"],
    }
    if rights.sales_cost:
        sold = sale_lines(scope, period).order_by().aggregate(cost=Sum("cost_total"))["cost"]
        back = return_lines(scope, period).order_by().aggregate(cost=Sum("cost_total"))["cost"]
        cost = round_money(dec(sold) - dec(back))
        out["cost_of_goods"] = str(cost)
        out["gross_profit"] = str(revenue - refunds - cost)
    return out


def _by_payment(scope: Scope, period) -> list[dict]:
    rows = {
        r["payment_method"]: r
        for r in sales(scope, period)
        .order_by()
        .values("payment_method")
        .annotate(count=Count("id"), total=Sum("total"))
    }
    return [
        {"method": method, "count": rows[method]["count"], "total": money(rows[method]["total"])}
        for method in PaymentMethod.values
        if method in rows
    ]


def _by_day(scope: Scope, period) -> list[dict]:
    days: dict = {}
    sold = (
        sales(scope, period)
        .order_by()
        .annotate(day=TruncDate("created_at", tzinfo=scope.zone))
        .values("day")
        .annotate(count=Count("id"), total=Sum("total"))
    )
    for row in sold:
        days[row["day"]] = {"count": row["count"], "revenue": row["total"], "refunds": None}
    given = (
        returns(scope, period)
        .order_by()
        .annotate(day=TruncDate("created_at", tzinfo=scope.zone))
        .values("day")
        .annotate(total=Sum("refund_total"))
    )
    for row in given:
        day = days.setdefault(row["day"], {"count": 0, "revenue": None, "refunds": None})
        day["refunds"] = row["total"]
    return [
        {
            "date": day.isoformat(),
            "count": days[day]["count"],
            "revenue": money(days[day]["revenue"]),
            "refunds": money(days[day]["refunds"]),
        }
        for day in sorted(days)
    ]


def _top_products(scope: Scope, period) -> list[dict]:
    rows = (
        sale_lines(scope, period)
        .order_by()
        .values(
            "product_id",
            "product__sku",
            "product__name",
            "product__unit__symbol",
            "product__unit__decimal_places",
        )
        .annotate(quantity=Sum("quantity"), revenue=Sum("line_total"))
        .order_by("-revenue", "product__name", "product_id")[:TOP_PRODUCTS]
    )
    return [
        {
            "product": str(r["product_id"]),
            "sku": r["product__sku"],
            "name": r["product__name"],
            "unit_symbol": r["product__unit__symbol"],
            "unit_decimals": r["product__unit__decimal_places"],
            "quantity": qty(r["quantity"]),
            "revenue": money(r["revenue"]),
        }
        for r in rows
    ]


def sales_report(ctx: ReportContext) -> dict:
    scope, period = ctx.scope, ctx.period
    f = figures(scope, period, ctx.rights)
    out = {
        **ctx.head(),
        "sales_count": f["sales_count"],
        "revenue": f["revenue"],
        "refunds": f["refunds"],
        "returns_count": f["returns_count"],
        "net_sales": f["net_sales"],
    }
    if ctx.rights.sales_cost:
        out["cost_of_goods"] = f["cost_of_goods"]
        out["gross_profit"] = f["gross_profit"]
    out["by_payment"] = _by_payment(scope, period)
    out["by_day"] = _by_day(scope, period)
    out["top_products"] = _top_products(scope, period)
    return out
