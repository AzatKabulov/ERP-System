"""Read-only expiry information for remaining sellable batches in permitted locations."""

from datetime import timedelta

from django.db.models import Min, Q, Sum

from apps.businesses.access import restrict_to_locations
from apps.common.errors import ApiError
from apps.inventory.models import Condition, CostLayer


def layers(request, location_id=None):
    result = restrict_to_locations(
        CostLayer.objects.filter(
            business=request.business,
            balance__business=request.business,
            balance__condition=Condition.SELLABLE,
            quantity_remaining__gt=0,
            expiry_date__isnull=False,
        ),
        request.membership,
        field="balance__location_id",
    )
    if location_id is not None:
        result = result.filter(balance__location_id=location_id)
    mode = request.query_params.get("expiry", "")
    today = request.business.local_today()
    if mode == "expired":
        result = result.filter(expiry_date__lt=today)
    elif mode == "soon":
        result = result.filter(expiry_date__range=(today, today + timedelta(days=30)))
    elif mode:
        raise ApiError("validation_error", "Unknown expiry filter")
    return result


def summary(request, product_ids, location_id=None):
    batches = layers(request, location_id).filter(balance__product_id__in=product_ids)
    dates = dict(
        batches.order_by()
        .values("balance__product_id")
        .annotate(day=Min("expiry_date"))
        .values_list("balance__product_id", "day")
    )
    if not dates:
        return {}
    match = Q(pk__in=[])
    for product_id, day in dates.items():
        match |= Q(balance__product_id=product_id, expiry_date=day)
    amounts = dict(
        batches.filter(match)
        .order_by()
        .values("balance__product_id")
        .annotate(total=Sum("quantity_remaining"))
        .values_list("balance__product_id", "total")
    )
    today = request.business.local_today()
    return {
        product_id: {
            "date": day.isoformat(),
            "quantity": str(amounts[product_id]),
            "status": "expired"
            if day < today
            else "soon"
            if day <= today + timedelta(days=30)
            else "valid",
        }
        for product_id, day in dates.items()
    }
