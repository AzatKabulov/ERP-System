"""What to buy again. For every product and location that has a minimum and a target level, the
suggestion is the target minus what is on the shelf (sellable) and what is already ordered but
not yet received. Nothing is ordered automatically: staff review the list and create a draft
purchase order from it."""

from decimal import Decimal

from django.db.models import F, Sum

from apps.catalog.models import ReorderSetting
from apps.inventory.models import Condition, StockBalance

from .models import PurchaseOrder, PurchaseOrderLine

ZERO = Decimal("0")
OPEN = (PurchaseOrder.Status.ORDERED, PurchaseOrder.Status.PARTIALLY_RECEIVED)


def suggestions(business, membership, location_id=None) -> list[dict]:
    settings = ReorderSetting.objects.filter(business=business, product__is_active=True)
    allowed = membership.location_ids()
    if allowed is not None:
        settings = settings.filter(location_id__in=allowed)
    if location_id:
        settings = settings.filter(location_id=location_id)
    settings = list(
        settings.select_related("product__unit", "location").order_by(
            "location__name", "product__name"
        )
    )
    if not settings:
        return []
    products = {s.product_id for s in settings}
    locations = {s.location_id for s in settings}
    on_hand = {
        (r["product_id"], r["location_id"]): r["quantity"]
        for r in StockBalance.objects.filter(
            business=business,
            condition=Condition.SELLABLE,
            product_id__in=products,
            location_id__in=locations,
        ).values("product_id", "location_id", "quantity")
    }
    on_order = {
        (r["product_id"], r["order__location_id"]): r["outstanding"]
        for r in PurchaseOrderLine.objects.filter(
            order__business=business,
            order__status__in=OPEN,
            product_id__in=products,
            order__location_id__in=locations,
        )
        .values("product_id", "order__location_id")
        .annotate(outstanding=Sum(F("quantity") - F("received_quantity")))
    }
    rows = []
    for setting in settings:
        key = (setting.product_id, setting.location_id)
        have = on_hand.get(key, ZERO)
        ordered = on_order.get(key, ZERO) or ZERO
        if have + ordered >= setting.minimum:
            continue
        rows.append(
            {
                "product": setting.product,
                "location": setting.location,
                "on_hand": have,
                "on_order": ordered,
                "minimum": setting.minimum,
                "target": setting.target,
                "suggested": setting.target - (have + ordered),
            }
        )
    return rows
