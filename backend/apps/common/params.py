"""Query-string helpers shared by the list, report and history endpoints: dates and ids that are
checked the same way everywhere (400 `validation_error` with the field named), and calendar days
in a business's own time zone."""

import re
import uuid
from datetime import date, datetime, time, timedelta
from zoneinfo import ZoneInfo

from apps.common.errors import ApiError

_ISO_DAY = re.compile(r"\d{4}-\d{2}-\d{2}")


def invalid(name: str, message: str, code: str = "invalid") -> ApiError:
    return ApiError(
        "validation_error", message, fields={name: [{"code": code, "message": message}]}
    )


def date_param(params, name: str) -> date | None:
    """`YYYY-MM-DD`; blank or absent is None."""
    raw = (params.get(name) or "").strip()
    if not raw:
        return None
    try:
        if not _ISO_DAY.fullmatch(raw):
            raise ValueError(raw)
        return date.fromisoformat(raw)
    except ValueError as exc:
        raise invalid(name, "Dates are YYYY-MM-DD") from exc


def uuid_param(params, name: str) -> uuid.UUID | None:
    raw = (params.get(name) or "").strip()
    if not raw:
        return None
    try:
        return uuid.UUID(raw)
    except ValueError as exc:
        raise invalid(name, "Not a valid id") from exc


def local_day_bounds(business, first: date | None, last: date | None):
    """`(start, end)` as a half-open range `start <= t < end` covering the calendar days `first`
    to `last` (both included) in the business's time zone. Either side may be None (open)."""
    zone = ZoneInfo(business.timezone)

    def midnight(day: date) -> datetime:
        return datetime.combine(day, time.min, tzinfo=zone)

    start = midnight(first) if first else None
    end = midnight(last + timedelta(days=1)) if last else None
    return start, end
