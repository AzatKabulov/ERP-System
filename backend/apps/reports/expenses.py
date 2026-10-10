"""The expenses report: what the shop spent in the period (`spent_on` between the two days, both
included). Voided expenses are not counted. Needs `expense.view`, not `report.view`."""

from django.db.models import Count, Sum

from apps.expenses import services
from apps.expenses.models import Expense

from .scope import ReportContext, Scope, dec, money


def expenses(scope: Scope, period):
    """The period's live (not voided) expenses at the locations in scope."""
    return scope.limit(
        Expense.objects.filter(
            business=scope.business, voided_at__isnull=True, **period.days("spent_on")
        )
    )


def expenses_total(scope: Scope, period):
    return dec(expenses(scope, period).order_by().aggregate(total=Sum("amount"))["total"])


def _by_location(scope: Scope, period) -> list[dict]:
    rows = sorted(
        expenses(scope, period)
        .order_by()
        .values("location_id", "location__name")
        .annotate(total=Sum("amount"), count=Count("id")),
        key=lambda r: (-r["total"], r["location__name"], str(r["location_id"])),
    )
    return [
        {
            "location": {"id": str(r["location_id"]), "name": r["location__name"]},
            "total": money(r["total"]),
            "count": r["count"],
        }
        for r in rows
    ]


def expenses_report(ctx: ReportContext) -> dict:
    summary = services.summarize(expenses(ctx.scope, ctx.period))
    return {
        **ctx.head(),
        "total": summary["total"],
        "count": summary["count"],
        "by_category": summary["by_category"],
        "by_location": _by_location(ctx.scope, ctx.period),
    }
