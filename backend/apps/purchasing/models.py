from django.core.validators import MinValueValidator
from django.db import models
from django.db.models.functions import Lower

from apps.common.models import AppendOnlyModel, TimestampedModel, UUIDModel


class Supplier(UUIDModel, TimestampedModel):
    business = models.ForeignKey(
        "businesses.Business", on_delete=models.PROTECT, related_name="suppliers"
    )
    name = models.CharField(max_length=160)
    contact_name = models.CharField(max_length=160, blank=True)
    phone = models.CharField(max_length=40, blank=True)
    email = models.CharField(max_length=254, blank=True)
    address = models.CharField(max_length=300, blank=True)
    notes = models.TextField(blank=True)
    is_active = models.BooleanField(default=True)

    class Meta:
        ordering = ["name", "id"]
        constraints = [
            models.UniqueConstraint(
                "business", Lower("name"), name="purchasing_supplier_name_ci_unique"
            )
        ]

    def __str__(self) -> str:
        return self.name


class DocumentCounter(models.Model):
    """Per-business running number for a kind of document. The row is locked while a
    number is taken, so two requests can never receive the same number."""

    business = models.ForeignKey("businesses.Business", on_delete=models.CASCADE, related_name="+")
    kind = models.CharField(max_length=32)
    last_value = models.PositiveIntegerField(default=0)

    class Meta:
        constraints = [
            models.UniqueConstraint(fields=["business", "kind"], name="purchasing_counter_unique")
        ]


class PurchaseOrder(UUIDModel, TimestampedModel):
    class Status(models.TextChoices):
        DRAFT = "draft", "Draft"
        ORDERED = "ordered", "Ordered"
        PARTIALLY_RECEIVED = "partially_received", "Partially received"
        RECEIVED = "received", "Received"
        CANCELLED = "cancelled", "Cancelled"

    business = models.ForeignKey(
        "businesses.Business", on_delete=models.PROTECT, related_name="purchase_orders"
    )
    number = models.PositiveIntegerField()
    supplier = models.ForeignKey(Supplier, on_delete=models.PROTECT, related_name="orders")
    location = models.ForeignKey(
        "businesses.Location", on_delete=models.PROTECT, related_name="+"
    )  # where the goods will be received
    status = models.CharField(max_length=24, choices=Status.choices, default=Status.DRAFT)
    expected_date = models.DateField(null=True, blank=True)
    notes = models.TextField(blank=True)
    created_by = models.ForeignKey("accounts.User", on_delete=models.PROTECT, related_name="+")
    ordered_at = models.DateTimeField(null=True, blank=True)
    cancelled_at = models.DateTimeField(null=True, blank=True)
    cancel_reason = models.TextField(blank=True)

    class Meta:
        ordering = ["-number"]
        constraints = [
            models.UniqueConstraint(fields=["business", "number"], name="purchasing_po_number"),
        ]
        indexes = [models.Index(fields=["business", "status"])]

    def __str__(self) -> str:
        return f"PO-{self.number:04d}"


class PurchaseOrderLine(UUIDModel):
    order = models.ForeignKey(PurchaseOrder, on_delete=models.CASCADE, related_name="lines")
    product = models.ForeignKey("catalog.Product", on_delete=models.PROTECT, related_name="+")
    position = models.PositiveSmallIntegerField(default=0)
    quantity = models.DecimalField(max_digits=14, decimal_places=3)
    unit_cost = models.DecimalField(
        max_digits=14, decimal_places=2, validators=[MinValueValidator(0)]
    )  # TMT
    received_quantity = models.DecimalField(max_digits=14, decimal_places=3, default=0)

    class Meta:
        ordering = ["position", "id"]
        constraints = [
            models.UniqueConstraint(fields=["order", "product"], name="purchasing_line_product"),
            models.CheckConstraint(
                condition=models.Q(quantity__gt=0), name="purchasing_line_quantity_positive"
            ),
            models.CheckConstraint(
                condition=models.Q(received_quantity__gte=0)
                & models.Q(received_quantity__lte=models.F("quantity")),
                name="purchasing_line_received_valid",
            ),
            models.CheckConstraint(
                condition=models.Q(unit_cost__gte=0), name="purchasing_line_cost_nonneg"
            ),
        ]

    @property
    def outstanding(self):
        return self.quantity - self.received_quantity


class Delivery(UUIDModel, AppendOnlyModel):
    """One receipt of goods against an order. Written once; never edited or deleted."""

    business = models.ForeignKey("businesses.Business", on_delete=models.PROTECT, related_name="+")
    order = models.ForeignKey(PurchaseOrder, on_delete=models.PROTECT, related_name="deliveries")
    number = models.PositiveSmallIntegerField()  # 1, 2, 3... within the order
    received_by = models.ForeignKey("accounts.User", on_delete=models.PROTECT, related_name="+")
    received_at = models.DateTimeField(auto_now_add=True)
    note = models.CharField(max_length=500, blank=True)

    class Meta:
        ordering = ["number"]
        constraints = [
            models.UniqueConstraint(fields=["order", "number"], name="purchasing_delivery_number")
        ]


class DeliveryLine(UUIDModel, AppendOnlyModel):
    delivery = models.ForeignKey(Delivery, on_delete=models.PROTECT, related_name="lines")
    order_line = models.ForeignKey(PurchaseOrderLine, on_delete=models.PROTECT, related_name="+")
    quantity = models.DecimalField(max_digits=14, decimal_places=3)
    unit_cost = models.DecimalField(max_digits=14, decimal_places=2)  # snapshot, TMT

    class Meta:
        ordering = ["order_line__position", "id"]
        constraints = [
            models.CheckConstraint(
                condition=models.Q(quantity__gt=0), name="purchasing_delivery_line_positive"
            )
        ]


class SupplierReturn(UUIDModel, AppendOnlyModel):
    """Goods sent back to a supplier, linked to the delivery they came with. The credit is
    what the delivery charged for them; the stock leaves at its FIFO cost."""

    business = models.ForeignKey("businesses.Business", on_delete=models.PROTECT, related_name="+")
    number = models.PositiveIntegerField()  # SR-0001, per business
    supplier = models.ForeignKey(Supplier, on_delete=models.PROTECT, related_name="returns")
    delivery = models.ForeignKey(Delivery, on_delete=models.PROTECT, related_name="returns")
    location = models.ForeignKey("businesses.Location", on_delete=models.PROTECT, related_name="+")
    created_by = models.ForeignKey("accounts.User", on_delete=models.PROTECT, related_name="+")
    reason = models.CharField(max_length=300)
    note = models.CharField(max_length=500, blank=True)
    credit_total = models.DecimalField(max_digits=14, decimal_places=2)  # TMT, informational
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-number"]
        constraints = [
            models.UniqueConstraint(fields=["business", "number"], name="purchasing_sr_number"),
        ]
        indexes = [models.Index(fields=["business", "-created_at"])]

    def __str__(self) -> str:
        return f"SR-{self.number:04d}"


class SupplierReturnLine(UUIDModel, AppendOnlyModel):
    supplier_return = models.ForeignKey(
        SupplierReturn, on_delete=models.PROTECT, related_name="lines"
    )
    delivery_line = models.ForeignKey(
        DeliveryLine, on_delete=models.PROTECT, related_name="return_lines"
    )
    product = models.ForeignKey("catalog.Product", on_delete=models.PROTECT, related_name="+")
    quantity = models.DecimalField(max_digits=14, decimal_places=3)
    condition = models.CharField(max_length=16)  # sellable or damaged: where it was taken from
    unit_cost = models.DecimalField(max_digits=14, decimal_places=2)  # the delivery's, TMT
    # What the goods cost in stock (FIFO, the oldest layers). Exact, so five decimals.
    cost_total = models.DecimalField(max_digits=18, decimal_places=5)

    class Meta:
        constraints = [
            models.CheckConstraint(
                condition=models.Q(quantity__gt=0), name="purchasing_sr_line_positive"
            )
        ]
