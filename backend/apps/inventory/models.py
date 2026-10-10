"""The stock ledger.

Three tables, one writer (`apps.inventory.services`):

* `StockMovement` - append-only history. Every change of stock is a movement.
* `StockBalance`  - the current quantity per product, location and condition, kept in step
                    with the movements inside the same transaction.
* `CostLayer`     - one per receipt or opening-stock line (decision D6, FIFO). Selling or
                    writing off consumes the oldest layer first, so each movement records
                    its exact cost.

Invariant, checked by `services.reconcile()`: for every product/location/condition,
balance = sum of movements = sum of layer quantities remaining.
"""

from django.core.validators import MinValueValidator
from django.db import models

from apps.common.models import AppendOnlyModel, UUIDModel


class Condition(models.TextChoices):
    SELLABLE = "sellable", "Sellable"
    DAMAGED = "damaged", "Damaged"
    INSPECTION = "inspection", "Awaiting inspection"
    IN_TRANSIT = "in_transit", "In transit"  # used by transfers (Phase 6)


class MovementType(models.TextChoices):
    OPENING = "opening", "Opening stock"
    RECEIPT = "receipt", "Purchase receipt"
    ADJUSTMENT_IN = "adjustment_in", "Adjustment (increase)"
    ADJUSTMENT_OUT = "adjustment_out", "Adjustment (decrease)"
    SALE = "sale", "Sale"
    # A transfer's legs: goods leave a place (sellable at the source, or in transit when a
    # transfer is received or cancelled), arrive somewhere, or are lost on the way.
    TRANSFER_OUT = "transfer_out", "Transfer (out)"
    TRANSFER_IN = "transfer_in", "Transfer (in)"
    TRANSFER_LOSS = "transfer_loss", "Transfer (missing on arrival)"
    # Returns: goods a customer brought back (at the cost they were sold at), the decision on
    # goods that were awaiting inspection, goods sent back to a supplier, and warranty swaps.
    RETURN_IN = "return_in", "Customer return"
    INSPECTION_OUT = "inspection_out", "Inspection decided (out)"
    INSPECTION_IN = "inspection_in", "Inspection decided (in)"
    SUPPLIER_RETURN = "supplier_return", "Return to supplier"
    WARRANTY_OUT = "warranty_out", "Warranty replacement (out)"
    WARRANTY_IN = "warranty_in", "Warranty defective unit (in)"


class StockBalance(UUIDModel):
    business = models.ForeignKey("businesses.Business", on_delete=models.PROTECT, related_name="+")
    product = models.ForeignKey("catalog.Product", on_delete=models.PROTECT, related_name="+")
    location = models.ForeignKey("businesses.Location", on_delete=models.PROTECT, related_name="+")
    condition = models.CharField(
        max_length=16, choices=Condition.choices, default=Condition.SELLABLE
    )
    quantity = models.DecimalField(max_digits=14, decimal_places=3, default=0)
    # Numbers the next cost layer of this bucket; guarded by the row lock on this balance.
    layer_seq = models.PositiveIntegerField(default=0)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        constraints = [
            models.UniqueConstraint(
                fields=["product", "location", "condition"], name="inventory_balance_unique"
            ),
            # The database itself refuses negative stock, whatever the code does.
            models.CheckConstraint(
                condition=models.Q(quantity__gte=0), name="inventory_balance_nonnegative"
            ),
        ]
        indexes = [models.Index(fields=["business", "location", "condition"])]

    def __str__(self) -> str:
        return f"{self.product_id} @ {self.location_id} [{self.condition}] = {self.quantity}"


class CostLayer(UUIDModel):
    business = models.ForeignKey("businesses.Business", on_delete=models.PROTECT, related_name="+")
    balance = models.ForeignKey(StockBalance, on_delete=models.PROTECT, related_name="layers")
    layer_no = models.PositiveIntegerField()  # FIFO order inside the balance
    unit_cost = models.DecimalField(
        max_digits=14, decimal_places=2, validators=[MinValueValidator(0)]
    )  # TMT
    quantity_initial = models.DecimalField(max_digits=14, decimal_places=3)
    quantity_remaining = models.DecimalField(max_digits=14, decimal_places=3)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["balance_id", "layer_no"]
        constraints = [
            models.UniqueConstraint(fields=["balance", "layer_no"], name="inventory_layer_no"),
            models.CheckConstraint(
                condition=models.Q(quantity_remaining__gte=0)
                & models.Q(quantity_remaining__lte=models.F("quantity_initial")),
                name="inventory_layer_remaining_valid",
            ),
            models.CheckConstraint(
                condition=models.Q(quantity_initial__gt=0), name="inventory_layer_initial_positive"
            ),
            models.CheckConstraint(
                condition=models.Q(unit_cost__gte=0), name="inventory_layer_cost_nonneg"
            ),
        ]
        indexes = [
            models.Index(fields=["balance", "layer_no"]),
            # The inventory value only reads layers with something left; consumed layers pile
            # up over the years, so the report reads a small index instead of the whole table.
            models.Index(
                fields=["business", "balance"],
                condition=models.Q(quantity_remaining__gt=0),
                name="inventory_layer_live",
            ),
        ]


class StockMovement(UUIDModel, AppendOnlyModel):
    business = models.ForeignKey("businesses.Business", on_delete=models.PROTECT, related_name="+")
    product = models.ForeignKey("catalog.Product", on_delete=models.PROTECT, related_name="+")
    location = models.ForeignKey("businesses.Location", on_delete=models.PROTECT, related_name="+")
    condition = models.CharField(max_length=16, choices=Condition.choices)
    movement_type = models.CharField(max_length=24, choices=MovementType.choices)
    quantity = models.DecimalField(max_digits=14, decimal_places=3)  # signed
    unit_cost = models.DecimalField(max_digits=14, decimal_places=2)  # TMT, from the layer
    layer = models.ForeignKey(CostLayer, on_delete=models.PROTECT, related_name="movements")
    # The document that caused it, e.g. ("delivery", <id>) or ("adjustment", <id>).
    document_type = models.CharField(max_length=32)
    document_id = models.UUIDField()
    reason = models.TextField(blank=True)
    actor = models.ForeignKey("accounts.User", on_delete=models.PROTECT, related_name="+")
    request_id = models.CharField(max_length=64, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-created_at", "-id"]
        constraints = [
            models.CheckConstraint(
                condition=~models.Q(quantity=0), name="inventory_movement_nonzero"
            ),
        ]
        indexes = [
            models.Index(fields=["business", "product", "-created_at"]),
            models.Index(fields=["business", "location", "-created_at"]),
            models.Index(fields=["business", "-created_at"]),  # the stock report's period
            models.Index(fields=["document_type", "document_id"]),
        ]
