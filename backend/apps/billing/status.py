"""What a client's subscription means right now. One function decides; everything else (the
API gate, the banner in the app, the console's colours) asks it.

    free        no client record, or free access: never expires
    suspended   cut off by us, whatever was paid: nothing works
    active      paid, more than a week left (trial flag set while on the free trial)
    expiring    paid, a week or less left: works, owner and manager see a warning
    grace       the end date passed less than a week ago: works, a red warning
    read_only   past the grace days: can look and export, cannot sell or change anything
"""

import zoneinfo
from dataclasses import dataclass
from datetime import datetime, timedelta

from django.conf import settings
from django.core.exceptions import ObjectDoesNotExist
from django.utils import timezone

FREE = "free"
SUSPENDED = "suspended"
ACTIVE = "active"
EXPIRING = "expiring"
GRACE = "grace"
READ_ONLY = "read_only"


@dataclass(frozen=True)
class SubscriptionStatus:
    state: str
    is_trial: bool = False
    ends_at: datetime | None = None
    grace_ends_at: datetime | None = None
    days_left: int | None = None  # whole days of the store's own calendar; negative once ended

    @property
    def allows_reads(self) -> bool:
        return self.state != SUSPENDED

    @property
    def allows_writes(self) -> bool:
        return self.state in (FREE, ACTIVE, EXPIRING, GRACE)

    @property
    def blocked(self) -> bool:
        return not self.allows_writes


def client_of(business):
    """The business's Client row, or None (a business we never set up billing for)."""
    try:
        return business.client
    except ObjectDoesNotExist:
        return None


def local_date(business, moment: datetime):
    return moment.astimezone(zoneinfo.ZoneInfo(business.timezone)).date()


def status_of(business, now: datetime | None = None) -> SubscriptionStatus:
    return status_for(client_of(business), business, now)


def status_for(client, business, now: datetime | None = None) -> SubscriptionStatus:
    """The same decision for a client row already in hand (the console lists many at once)."""
    if client is None or client.override == "free":
        return SubscriptionStatus(FREE)
    if client.override == "suspended":
        return SubscriptionStatus(SUSPENDED, client.is_trial, client.paid_until)
    ends = client.paid_until
    if ends is None:  # never paid and no trial given: nothing to allow
        return SubscriptionStatus(READ_ONLY, client.is_trial)
    now = now or timezone.now()
    grace_ends = ends + timedelta(days=settings.SUBSCRIPTION_GRACE_DAYS)
    days_left = (local_date(business, ends) - local_date(business, now)).days
    if now > grace_ends:
        state = READ_ONLY
    elif now > ends:
        state = GRACE
    elif days_left <= settings.SUBSCRIPTION_WARN_DAYS:
        state = EXPIRING
    else:
        state = ACTIVE
    return SubscriptionStatus(state, client.is_trial, ends, grace_ends, days_left)
