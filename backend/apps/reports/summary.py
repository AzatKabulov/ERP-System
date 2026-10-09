"""The period summary and the dashboard.

Summary (`report.view`): the headline figures of a period. Revenue, gross profit, expenses and
the result stay separate measures:

* result = gross_profit - expenses, shown only to someone who may see both. It is an OPERATING
  result, not an accounting profit: it knows nothing about tax, depreciation, owner's pay,
  stock bought but not yet sold, or anything that is not recorded as an expense.
* inventory_value, low_stock_count and open_orders_count are snapshots of now (restricted to the
  locations in scope), not figures of the period.

Dashboard (`dashboard.view`): a flat object with ONLY the sections the caller may see, for the
caller's own locations. "Today" and "this month" are calendar days in the business time zone;
this month runs from its first day to today. Sales figures are sale totals (revenue); the gross
profit is net of returns as defined in `sales.py`.
"""

from django.db.models import Count, Q, Sum
from django.utils import timezone
from rest_framework import serializers

from apps.audit.models import AuditEvent
from apps.audit.serializers import AuditEventSerializer
from apps.businesses.permissions import has_permission
from apps.purchasing import reorder
from apps.warranties.models import WarrantyClaim

from . import expenses as expense_figures
from . import sales as sales_figures
from . import stock
from .purchases import open_orders_count
from .scope import Period, ReportContext, Rights, Scope, money, round_money

RECENT_ACTIVITY = 10


def summary_report(ctx: ReportContext) -> dict:
    scope, period, rights = ctx.scope, ctx.period, ctx.rights
    f = sales_figures.figures(scope, period, rights)
    out = {**ctx.head(), **f}
    if rights.expenses:
        spent = round_money(expense_figures.expenses_total(scope, period))
        out["expenses"] = str(spent)
        if rights.sales_cost:
            out["result"] = money(round_money(f["gross_profit"]) - spent)
    if rights.stock_cost:
        out["inventory_value"] = stock.inventory_value(scope)["total"]
    out["low_stock_count"] = stock.low_stock_count(scope)
    out["open_orders_count"] = open_orders_count(scope)
    return out


def dashboard(request) -> dict:
    """Only the sections the caller's role allows. One `timezone.now()` fixes both the day
    bounds and `generated_at`."""
    business, membership = request.business, request.membership
    scope = Scope.from_request(request, allow_location=False)
    role = membership.role
    now = timezone.now()
    today = now.astimezone(scope.zone).date()
    month = Period.of(business, today.replace(day=1), today)
    day = Period.of(business, today, today)

    out = {"generated_at": serializers.DateTimeField().to_representation(now)}
    rights = Rights.of(role)

    if has_permission(role, "sales.view"):
        made = (
            sales_figures.sales(scope, month)
            .order_by()
            .aggregate(
                month_count=Count("id"),
                month_total=Sum("total"),
                today_count=Count("id", filter=Q(created_at__gte=day.start)),
                today_total=Sum("total", filter=Q(created_at__gte=day.start)),
            )
        )
        out["sales_today"] = {"count": made["today_count"], "total": money(made["today_total"])}
        out["sales_month"] = {"count": made["month_count"], "total": money(made["month_total"])}
    if rights.sales_cost:
        out["gross_profit_month"] = sales_figures.figures(scope, month, rights)["gross_profit"]
    if rights.expenses:
        out["expenses_month"] = money(expense_figures.expenses_total(scope, month))
    if rights.stock_cost:
        out["inventory_value"] = stock.inventory_value(scope)["total"]
    if has_permission(role, "stock.view"):
        out["low_stock_count"] = stock.low_stock_count(scope)
    if has_permission(role, "reorder.view"):
        out["reorder_count"] = len(reorder.suggestions(business, membership))
    if has_permission(role, "purchasing.view"):
        out["open_orders_count"] = open_orders_count(scope)
    if has_permission(role, "warranty.view"):
        out["open_claims_count"] = scope.limit(
            WarrantyClaim.objects.filter(business=business, status=WarrantyClaim.Status.OPEN),
            "sale__location_id",
        ).count()
    if has_permission(role, "audit.view"):
        events = (
            AuditEvent.objects.filter(business=business)
            .select_related("actor")
            .order_by("-created_at", "-id")[:RECENT_ACTIVITY]
        )
        out["recent_activity"] = AuditEventSerializer(events, many=True).data
    return out
