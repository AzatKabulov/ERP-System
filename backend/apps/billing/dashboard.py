"""The numbers on the console's front page, and the usage signals beside each client. Counts
only: never what a store sold or to whom (the terms must say so; D5)."""

from collections import Counter, defaultdict
from datetime import datetime, timedelta
from decimal import Decimal

from django.db.models import Count, Max, Sum
from django.utils import timezone

from apps.businesses.models import Membership
from apps.sales.models import Sale

from .models import Client, SubscriptionEvent
from .status import ACTIVE, EXPIRING, FREE, GRACE, READ_ONLY, SUSPENDED, status_for

# What the owner should do next, in the order they should look at it.
ATTENTION = (EXPIRING, GRACE, READ_ONLY)


def usage(business_ids, now: datetime | None = None) -> dict:
    """{business_id: {"last_sign_in", "staff", "sales_30d"}} for the given stores."""
    now = now or timezone.now()
    since = now - timedelta(days=30)
    out = {b: {"last_sign_in": None, "staff": 0, "sales_30d": 0} for b in business_ids}
    members = (
        Membership.objects.filter(business_id__in=business_ids, is_active=True)
        .values("business_id")
        .annotate(last=Max("user__last_login"), n=Count("id"))
    )
    for row in members:
        out[row["business_id"]].update(last_sign_in=row["last"], staff=row["n"])
    sales = (
        Sale.objects.filter(business_id__in=business_ids, created_at__gte=since)
        .values("business_id")
        .annotate(n=Count("id"))
    )
    for row in sales:
        out[row["business_id"]]["sales_30d"] = row["n"]
    return out


def snapshot(now: datetime | None = None) -> dict:
    """Everything the console's front page shows."""
    now = now or timezone.now()
    clients = list(Client.objects.select_related("business", "plan"))
    rows = [(client, status_for(client, client.business, now)) for client in clients]
    counts = Counter(status.state for _, status in rows)
    trials = sum(1 for _, status in rows if status.is_trial and status.state in (ACTIVE, EXPIRING))

    def listed(states):
        picked = [(c, s) for c, s in rows if s.state in states]
        return sorted(picked, key=lambda pair: pair[1].ends_at or now)

    month_start = now.replace(day=1, hour=0, minute=0, second=0, microsecond=0)
    income: dict[str, Decimal] = defaultdict(Decimal)
    paid = SubscriptionEvent.objects.filter(created_at__gte=month_start, amount__isnull=False)
    for row in paid.values("currency").annotate(total=Sum("amount")):
        income[row["currency"] or "—"] += row["total"]
    lapsed_this_month = sum(
        1
        for _, status in rows
        if status.state in (GRACE, READ_ONLY) and status.ends_at and status.ends_at >= month_start
    )
    return {
        "total": len(rows),
        "counts": {
            "active": counts[ACTIVE] + counts[EXPIRING],
            "trial": trials,
            "expiring": counts[EXPIRING],
            "grace": counts[GRACE],
            "read_only": counts[READ_ONLY],
            "suspended": counts[SUSPENDED],
            "free": counts[FREE],
        },
        "attention": listed(ATTENTION),
        "income_this_month": dict(income),
        "new_30_days": sum(
            1 for client, _ in rows if client.created_at >= now - timedelta(days=30)
        ),
        "lapsed_this_month": lapsed_this_month,
    }
