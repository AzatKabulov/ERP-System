"""The register of goods sold with a warranty: every sale line whose product carried a warranty
when it was sold, with the day it started, the last day it holds and where it stands today.

Nothing is stored for it. A line's warranty is its own snapshot (months and terms copied at the
sale, see `entitlement.py`), so the register is computed from sales, returns and claims and can
never disagree with them. Status of a line today:

* `returned` - every piece came back (a refund or a refunded claim): there is nothing left to cover;
* `expired`  - the last day has passed (only an owner or manager may still accept a claim);
* `soon`     - holds, but ends within 30 days;
* `active`   - holds.
A claim that is still open is shown next to the status (`open_claims`), it does not change it.
"""

from collections import defaultdict
from decimal import Decimal

from django.db.models import Q, Sum

from apps.businesses.access import restrict_to_locations
from apps.sales.models import SaleLine, SaleReturnLine
from apps.sales.returns import sale_day

from .entitlement import add_months
from .models import WarrantyClaim

ZERO = Decimal("0")
SOON_DAYS = 30
STATUSES = ("active", "soon", "expired", "returned")
CHUNK = 200


def _sale_number(text: str) -> int | None:
    digits = text.strip().upper().removeprefix("S").lstrip("-").lstrip("0")
    return int(digits) if digits.isdigit() else None


def _lines(request, params):
    lines = restrict_to_locations(
        SaleLine.objects.filter(sale__business=request.business, warranty_months__gt=0),
        request.membership,
        "sale__location_id",
    ).select_related("sale", "product")
    if params.get("location"):
        lines = lines.filter(sale__location_id=params["location"])
    query = params.get("q", "").strip()
    if query:
        match = (
            Q(sale__customer_name__icontains=query)
            | Q(sale__customer_phone__icontains=query)
            | Q(name__icontains=query)
            | Q(sku__icontains=query)
            | Q(product__barcodes__code__iexact=query)
        )
        number = _sale_number(query)
        if number is not None:
            match |= Q(sale__number=number)
        lines = lines.filter(match).distinct()
    return lines.order_by("-sale__created_at", "position", "pk")


def _state(line, returned, today, until) -> str:
    if returned >= line.quantity:
        return "returned"
    if today > until:
        return "expired"
    if (until - today).days <= SOON_DAYS:
        return "soon"
    return "active"


def _item(business, line, returned, open_claims, today) -> dict:
    sale = line.sale
    start = sale_day(business, sale)
    until = add_months(start, line.warranty_months)
    return {
        "sale_line": line.pk,
        "sale": sale.pk,
        "sale_number": sale.number,
        "product": line.product_id,
        "sku": line.sku,
        "name": line.name,
        # exact decimal text, like every quantity of the API (the JSON encoder would make floats)
        "quantity": str(line.quantity),
        "returned": str(returned),
        "customer_name": sale.customer_name,
        "customer_phone": sale.customer_phone,
        "warranty_months": line.warranty_months,
        "warranty_terms": line.warranty_terms,
        "starts": start,
        "until": until,
        "days_left": (until - today).days,
        "status": _state(line, returned, today, until),
        "open_claims": open_claims,
    }


def build(request, params, *, offset: int, limit: int) -> tuple[list[dict], bool]:
    """One page of the register and whether more follow. `status` (a state, `active` also
    takes the ones ending soon, or empty for all) is applied after the state is worked out, so
    the lines are read newest first in chunks until the page is full."""
    business = request.business
    wanted = params.get("status") or ""
    accept = {"active": {"active", "soon"}}.get(wanted, {wanted} if wanted else set(STATUSES))
    today = business.local_today()
    found: list[dict] = []
    need = offset + limit + 1
    lines = _lines(request, params)
    start = 0
    while len(found) < need:
        chunk = list(lines[start : start + CHUNK])
        if not chunk:
            break
        start += CHUNK
        ids = [line.pk for line in chunk]
        returned = {
            r["sale_line_id"]: r["total"]
            for r in SaleReturnLine.objects.filter(sale_line_id__in=ids)
            .values("sale_line_id")
            .annotate(total=Sum("quantity"))
        }
        open_claims: dict = defaultdict(int)
        for line_id in WarrantyClaim.objects.filter(
            sale_line_id__in=ids, status=WarrantyClaim.Status.OPEN
        ).values_list("sale_line_id", flat=True):
            open_claims[line_id] += 1
        for line in chunk:
            item = _item(business, line, returned.get(line.pk) or ZERO, open_claims[line.pk], today)
            if item["status"] in accept:
                found.append(item)
    return found[offset : offset + limit], len(found) > offset + limit


def summary(request, params) -> dict:
    """How many lines are in each state (what the register's tabs show). Counted with the same
    search and place filters but not the status one; capped by scanning at most 5,000 lines."""
    business = request.business
    today = business.local_today()
    counts = dict.fromkeys(STATUSES, 0)
    lines = list(_lines(request, params)[:5000])
    ids = [line.pk for line in lines]
    returned = {
        r["sale_line_id"]: r["total"]
        for r in SaleReturnLine.objects.filter(sale_line_id__in=ids)
        .values("sale_line_id")
        .annotate(total=Sum("quantity"))
    }
    for line in lines:
        until = add_months(sale_day(business, line.sale), line.warranty_months)
        counts[_state(line, returned.get(line.pk) or ZERO, today, until)] += 1
    counts["active"] += counts["soon"]  # the "active" tab includes those ending soon
    return counts
