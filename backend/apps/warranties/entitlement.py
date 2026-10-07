"""How long a sold line is under warranty. The months were copied from the product onto the sale
line when it was sold, so a later catalog edit never changes the entitlement. Counted from the
day of the sale in the business's time zone; the last day is included."""

import calendar
from datetime import date

from apps.sales.returns import sale_day


def add_months(day: date, months: int) -> date:
    """`day` moved forward by whole months. When the target month is shorter the date is clamped
    to its last day (31 January plus one month is 28 or 29 February)."""
    index = day.month - 1 + months
    year, month = day.year + index // 12, index % 12 + 1
    return date(year, month, min(day.day, calendar.monthrange(year, month)[1]))


def warranty_until(business, sale, line) -> date | None:
    """The last day the warranty of this sale line holds, or None when the product had none."""
    if not line.warranty_months:
        return None
    return add_months(sale_day(business, sale), line.warranty_months)
