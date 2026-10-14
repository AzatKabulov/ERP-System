"""Goods received without a cost, and putting the real cost in later.

A shop may scan a box in without knowing what it paid. The batch is then flagged `cost_known =
False` (its cost is only a placeholder), the flag follows the goods wherever they go, and a sale of
such goods is flagged too. Profit leaves those sales out (see `apps.reports.sales`) instead of
pretending the goods were free.

`set_product_cost` is how the owner or a manager fixes it afterwards: one cost for a product.
Every batch of it that was waiting for a cost gets that cost (so the stock value and the sales
that follow are right), and the sales and returns that already happened get a `CostCorrection`
(so the profit of the days they were made becomes right too). Nothing that was written is edited.
"""

from decimal import ROUND_HALF_UP, Decimal

from django.core.exceptions import ObjectDoesNotExist
from django.db import transaction
from django.db.models import Sum

from apps.audit import services as audit
from apps.catalog.models import Product
from apps.inventory import services as inventory
from apps.inventory.models import CostLayer, MovementType, StockBalance, StockMovement

from .models import CostCorrection, SaleLine, SaleReturnLine

ZERO = Decimal("0")
FIVE = Decimal("0.00001")


def effective_line_cost(line) -> tuple[Decimal, bool]:
    """(cost, known) of a sale line or a return line, including a later correction. Select the
    `correction` relation with the lines when listing many (one query for all of them)."""
    try:
        correction = line.correction
    except ObjectDoesNotExist:
        correction = None
    if correction is not None:
        return line.cost_total + correction.delta, True
    return line.cost_total, line.cost_known


def _unpriced(business):
    return Product.objects.filter(business=business, is_active=True, price_amount=0)


def _layers_waiting(business):
    return CostLayer.objects.filter(
        business=business,
        cost_known=False,
        quantity_remaining__gt=0,
        balance__product__is_active=True,
    )


def _sales_waiting(business):
    return SaleLine.objects.filter(
        sale__business=business, cost_known=False, correction__isnull=True, product__is_active=True
    )


def products_to_complete(business) -> list[dict]:
    """Active products that still need a selling price or a cost, with what is missing and how
    much stock and how many past sales are waiting for the cost."""
    unknown_stock = {
        r["balance__product"]: r["pieces"]
        for r in _layers_waiting(business)
        .order_by()
        .values("balance__product")
        .annotate(pieces=Sum("quantity_remaining"))
    }
    unknown_sold = {
        r["product"]: r["pieces"]
        for r in _sales_waiting(business)
        .order_by()
        .values("product")
        .annotate(pieces=Sum("quantity"))
    }
    wanted = set(unknown_stock) | set(unknown_sold)
    products = Product.objects.filter(business=business, is_active=True).select_related("unit")
    rows = []
    for product in products.order_by("name", "sku"):
        missing_price = product.price_amount == 0
        missing_cost = product.pk in wanted
        if not (missing_price or missing_cost):
            continue
        rows.append(
            {
                "product": product,
                "missing_price": missing_price,
                "missing_cost": missing_cost,
                "stock_without_cost": unknown_stock.get(product.pk, ZERO),
                "sold_without_cost": unknown_sold.get(product.pk, ZERO),
            }
        )
    return rows


def count_to_complete(business) -> int:
    """How many products `products_to_complete` lists, in one query (for the dashboard)."""
    return (
        _unpriced(business)
        .order_by()
        .values_list("pk", flat=True)
        .union(
            _layers_waiting(business).order_by().values_list("balance__product_id", flat=True),
            _sales_waiting(business).order_by().values_list("product_id", flat=True),
        )
        .count()
    )


def _corrected(movements, unit_cost: Decimal) -> Decimal:
    """What these slices cost once the unknown ones cost `unit_cost`."""
    return sum(
        (abs(m.quantity) * (m.unit_cost if m.layer.cost_known else unit_cost) for m in movements),
        ZERO,
    )


@transaction.atomic
def set_product_cost(business, actor, product: Product, unit_cost: Decimal) -> dict:
    """Give every batch of `product` that was waiting for a cost this cost, correct the sales and
    returns made from such batches, and make it the product's default cost when it has none (so
    the next box scanned in without a typed cost is a known cost)."""
    unit_cost = unit_cost.quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)
    # Same lock order as every stock posting: the product's balances by place and condition,
    # then its layers oldest first.
    list(
        StockBalance.objects.select_for_update()
        .filter(business=business, product=product)
        .order_by("location_id", "condition")
    )
    layers = list(
        CostLayer.objects.select_for_update()
        .filter(business=business, balance__product=product, cost_known=False)
        .order_by("balance_id", "layer_no")
    )

    sale_lines = list(
        SaleLine.objects.filter(
            sale__business=business, product=product, cost_known=False, correction__isnull=True
        ).order_by("sale__created_at", "id")
    )
    sold = {}
    for m in StockMovement.objects.filter(
        business=business,
        document_type="sale",
        document_id__in={line.sale_id for line in sale_lines},
        product=product,
        quantity__lt=0,
    ).select_related("layer"):
        sold.setdefault(m.document_id, []).append(m)
    corrections = []
    for line in sale_lines:
        new_total = _corrected(sold.get(line.sale_id, []), unit_cost)
        corrections.append(
            CostCorrection(
                business=business,
                sale_line=line,
                unit_cost=unit_cost,
                delta=(new_total - line.cost_total).quantize(FIVE),
                created_by=actor,
            )
        )

    return_lines = list(
        SaleReturnLine.objects.filter(
            sale_return__business=business,
            product=product,
            cost_known=False,
            correction__isnull=True,
        ).select_related("sale_return")
    )
    back = {}
    for m in StockMovement.objects.filter(
        business=business,
        document_type="return",
        document_id__in={line.sale_return_id for line in return_lines},
        product=product,
        movement_type=MovementType.RETURN_IN,
    ).select_related("layer"):
        back.setdefault(m.document_id, []).append(m)
    for line in return_lines:
        new_total = _corrected(back.get(line.sale_return_id, []), unit_cost)
        corrections.append(
            CostCorrection(
                business=business,
                return_line=line,
                unit_cost=unit_cost,
                delta=(new_total - line.cost_total).quantize(FIVE),
                created_by=actor,
            )
        )
    CostCorrection.objects.bulk_create(corrections)

    inventory.reprice_layers([layer.pk for layer in layers], unit_cost)
    if product.default_purchase_cost is None:
        product.default_purchase_cost = unit_cost
        product.save(update_fields=["default_purchase_cost", "updated_at"])
    result = {
        "layers": len(layers),
        "sale_lines": len(sale_lines),
        "return_lines": len(return_lines),
    }
    audit.record(
        "product.cost_set",
        actor=actor,
        business=business,
        obj=product,
        metadata={"unit_cost": str(unit_cost), **result},
    )
    return result
