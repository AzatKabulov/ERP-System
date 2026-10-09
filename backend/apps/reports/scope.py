"""What every report shares: the period, who is asking and what they may see, and how numbers
are written.

Period
    `date_from` and `date_to` (both included, `YYYY-MM-DD`) are calendar days in the BUSINESS
    time zone. The default `date_to` is today there; the default `date_from` is the first day of
    the month of `date_to` (of the current month when `date_to` is also left out), so the
    defaults never produce a reversed range. A range longer than 366 days is refused
    (`range_too_long`).

Rounding
    Money is a decimal string with 2 places, rounded half up. Costs are exact to 5 places in
    the database and are rounded once, at the finest level a report shows; a total is the sum
    of the rounded parts, so a column always adds up.
"""

import uuid
from dataclasses import dataclass
from datetime import date, datetime
from decimal import ROUND_HALF_UP, Decimal
from zoneinfo import ZoneInfo

from apps.businesses.access import require_location, restrict_to_locations
from apps.businesses.models import Location
from apps.businesses.permissions import has_permission
from apps.common.errors import ApiError
from apps.common.params import date_param, invalid, local_day_bounds, uuid_param

ZERO = Decimal("0")
CENT = Decimal("0.01")
MILLI = Decimal("0.001")
MAX_DAYS = 366


def dec(value) -> Decimal:
    """A database sum as a Decimal (no rows -> 0)."""
    return ZERO if value is None else Decimal(value)


def round_money(value) -> Decimal:
    rounded = dec(value).quantize(CENT, rounding=ROUND_HALF_UP)
    return rounded if rounded else ZERO.quantize(CENT)  # never "-0.00"


def money(value) -> str:
    return str(round_money(value))


def qty(value) -> str:
    rounded = dec(value).quantize(MILLI, rounding=ROUND_HALF_UP)
    return str(rounded if rounded else ZERO.quantize(MILLI))


@dataclass(frozen=True)
class Period:
    """Calendar days `first`..`last` (both included) in the business time zone. `start`/`end`
    are the same span as a half-open range of instants: `start <= t < end`."""

    first: date
    last: date
    start: datetime
    end: datetime

    @classmethod
    def of(cls, business, first: date, last: date) -> "Period":
        start, end = local_day_bounds(business, first, last)
        return cls(first, last, start, end)

    def as_json(self) -> dict:
        return {"from": self.first.isoformat(), "to": self.last.isoformat()}

    def instants(self, field: str) -> dict:
        """Filter arguments for a timestamp field."""
        return {f"{field}__gte": self.start, f"{field}__lt": self.end}

    def days(self, field: str) -> dict:
        """Filter arguments for a date field."""
        return {f"{field}__gte": self.first, f"{field}__lte": self.last}


def parse_period(request, business) -> Period:
    params = request.query_params
    first, last = date_param(params, "date_from"), date_param(params, "date_to")
    if last is None:
        last = business.local_today()
    if first is None:
        first = last.replace(day=1)
    if first > last:
        raise invalid("date_from", "date_from is after date_to", code="after_date_to")
    if (last - first).days + 1 > MAX_DAYS:
        raise ApiError(
            "range_too_long",
            "The period is longer than a year",
            params={"max_days": MAX_DAYS},
        )
    return Period.of(business, first, last)


class _Allowed:
    """A member's locations, looked up once, in the shape `restrict_to_locations` expects."""

    def __init__(self, ids):
        self._ids = ids

    def location_ids(self):
        return self._ids


class Scope:
    """The business, the member, and the locations a figure may come from: the member's own
    locations (owner and manager: all), narrowed to `location` when one was asked for."""

    def __init__(self, business, membership, location: uuid.UUID | None = None):
        self.business = business
        self.membership = membership
        self.location = location
        self.zone = ZoneInfo(business.timezone)
        self._allowed = _Allowed(membership.location_ids())

    @classmethod
    def from_request(cls, request, *, allow_location: bool = True) -> "Scope":
        """Reads `location`: 400 for a malformed id, 403 `location_not_permitted` for a location
        that is not the member's or not in this business (the two look the same, so another
        business's locations cannot be probed)."""
        location = uuid_param(request.query_params, "location") if allow_location else None
        if location is not None:
            known = Location.objects.filter(business=request.business, pk=location).exists()
            if not known:
                raise ApiError(
                    "location_not_permitted",
                    "This location is not available to you",
                    status_code=403,
                )
            require_location(request.membership, location)
        return cls(request.business, request.membership, location)

    def limit(self, queryset, field: str = "location_id"):
        queryset = restrict_to_locations(queryset, self._allowed, field)
        if self.location is not None:
            queryset = queryset.filter(**{field: self.location})
        return queryset

    @property
    def location_json(self) -> str | None:
        return None if self.location is None else str(self.location)


@dataclass(frozen=True)
class Rights:
    """The cost-related things a member may see. A key the member may not see is left out of
    the response altogether."""

    sales_cost: bool  # cost of goods, gross profit
    expenses: bool  # expenses, and with sales_cost the result
    stock_cost: bool  # inventory value
    purchasing_cost: bool  # amounts on orders, deliveries and supplier returns

    @classmethod
    def of(cls, role: str) -> "Rights":
        return cls(
            sales_cost=has_permission(role, "sales.cost.view"),
            expenses=has_permission(role, "expense.view"),
            stock_cost=has_permission(role, "stock.cost.view"),
            purchasing_cost=has_permission(role, "purchasing.cost.view"),
        )


@dataclass(frozen=True)
class ReportContext:
    scope: Scope
    period: Period
    rights: Rights

    @classmethod
    def from_request(cls, request) -> "ReportContext":
        period = parse_period(request, request.business)
        return cls(Scope.from_request(request), period, Rights.of(request.membership.role))

    def head(self) -> dict:
        """The two keys every report starts with."""
        return {"period": self.period.as_json(), "location": self.scope.location_json}
