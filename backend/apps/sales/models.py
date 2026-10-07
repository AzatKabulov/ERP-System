"""Sales. A completed sale is a historical fact: the sale and its lines are append-only (ORM
guard plus PostgreSQL trigger). Everything a receipt or a later return needs is copied onto the
rows (names, the price charged, the catalog price at that moment, cost, warranty terms), so
editing the catalog afterwards never changes what was sold. The seller sets the price of every
line freely; there are no discounts and no payment amounts, only how the customer paid."""

from django.db import models

from apps.common.models import AppendOnlyModel, TimestampedModel, UUIDModel


class Customer(UUIDModel, TimestampedModel):
    """Optional: a walk-in sale needs none."""

    business = models.ForeignKey(
        "businesses.Business", on_delete=models.PROTECT, related_name="customers"
    )
    name = models.CharField(max_length=200)
    phone = models.CharField(max_length=60, blank=True)
    notes = models.TextField(blank=True)
    is_active = models.BooleanField(default=True)
    # Case-folded name and phone, searched with `contains` (see catalog.Product.search_key).
    search_key = models.TextField(blank=True, editable=False, default="")

    class Meta:
        ordering = ["name", "id"]
        indexes = [models.Index(fields=["business", "is_active", "name"])]

    def __str__(self) -> str:
        return self.name


class PaymentMethod(models.TextChoices):
    CASH = "cash", "Cash"
    CARD = "card", "Card"  # a terminal used outside the system; only the fact is recorded


class Sale(UUIDModel, AppendOnlyModel):
    business = models.ForeignKey("businesses.Business", on_delete=models.PROTECT, related_name="+")
    number = models.PositiveIntegerField()  # S-000001, per business
    location = models.ForeignKey("businesses.Location", on_delete=models.PROTECT, related_name="+")
    cashier = models.ForeignKey("accounts.User", on_delete=models.PROTECT, related_name="+")
    customer = models.ForeignKey(
        Customer, null=True, blank=True, on_delete=models.PROTECT, related_name="sales"
    )
    customer_name = models.CharField(max_length=200, blank=True)  # snapshot
    customer_phone = models.CharField(max_length=60, blank=True)  # snapshot
    total = models.DecimalField(max_digits=14, decimal_places=2)  # TMT, the sum of the lines
    payment_method = models.CharField(
        max_length=16, choices=PaymentMethod.choices, default=PaymentMethod.CASH
    )
    note = models.CharField(max_length=500, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-number"]
        constraints = [
            models.UniqueConstraint(fields=["business", "number"], name="sales_sale_number"),
            models.CheckConstraint(
                condition=models.Q(total__gte=0), name="sales_sale_total_nonneg"
            ),
        ]
        indexes = [
            models.Index(fields=["business", "-created_at"]),
            models.Index(fields=["business", "location", "-created_at"]),
        ]

    def __str__(self) -> str:
        return f"S-{self.number:06d}"


class SaleLine(UUIDModel, AppendOnlyModel):
    sale = models.ForeignKey(Sale, on_delete=models.PROTECT, related_name="lines")
    position = models.PositiveSmallIntegerField(default=0)
    product = models.ForeignKey("catalog.Product", on_delete=models.PROTECT, related_name="+")
    sku = models.CharField(max_length=64)  # snapshot
    name = models.CharField(max_length=255)  # snapshot
    unit_symbol = models.CharField(max_length=16)  # snapshot
    unit_decimals = models.PositiveSmallIntegerField()  # snapshot
    quantity = models.DecimalField(max_digits=14, decimal_places=3)
    # The catalog price at that moment, for reference (as the shop states it).
    price_amount = models.DecimalField(max_digits=14, decimal_places=2)
    price_currency = models.CharField(max_length=3)
    # What the seller actually charged per unit (TMT), and the line: quantity x unit_price,
    # rounded half up to two decimals. The seller may charge any price, including zero.
    unit_price = models.DecimalField(max_digits=14, decimal_places=2)
    line_total = models.DecimalField(max_digits=14, decimal_places=2)
    # What the goods cost (FIFO, from the stock movements). Exact, so five decimals.
    cost_total = models.DecimalField(max_digits=18, decimal_places=5)
    # Copied from the product so a later catalog edit never changes the entitlement.
    warranty_months = models.PositiveSmallIntegerField(default=0)
    warranty_terms = models.TextField(blank=True)
    # Days after the sale the customer may return it (empty = no limit, 0 = not returnable).
    return_days = models.PositiveSmallIntegerField(null=True, blank=True)

    class Meta:
        ordering = ["position", "id"]
        constraints = [
            models.UniqueConstraint(fields=["sale", "product"], name="sales_line_product"),
            models.CheckConstraint(
                condition=models.Q(quantity__gt=0), name="sales_line_quantity_positive"
            ),
            models.CheckConstraint(
                condition=models.Q(unit_price__gte=0), name="sales_line_price_nonneg"
            ),
        ]


class ReturnCondition(models.TextChoices):
    """Where returned goods go: back on the shelf, into the damaged pile, or aside until
    somebody has looked at them."""

    SELLABLE = "sellable", "Sellable"
    DAMAGED = "damaged", "Damaged"
    INSPECTION = "inspection", "Awaiting inspection"


class SaleReturn(UUIDModel, AppendOnlyModel):
    """Goods a customer brought back, linked to the original sale. Written once; the refund is
    what the customer was charged for those goods (price charged x quantity), so prices that
    were not fixed are refunded as they were paid."""

    business = models.ForeignKey("businesses.Business", on_delete=models.PROTECT, related_name="+")
    number = models.PositiveIntegerField()  # R-0001, per business
    sale = models.ForeignKey(Sale, on_delete=models.PROTECT, related_name="returns")
    location = models.ForeignKey("businesses.Location", on_delete=models.PROTECT, related_name="+")
    created_by = models.ForeignKey("accounts.User", on_delete=models.PROTECT, related_name="+")
    reason = models.CharField(max_length=300)
    note = models.CharField(max_length=500, blank=True)
    refund_total = models.DecimalField(max_digits=14, decimal_places=2)  # TMT
    # How the money went back is the label of the original sale (cash or card).
    payment_method = models.CharField(max_length=16, choices=PaymentMethod.choices)
    # Set when the return was the outcome of a warranty claim.
    warranty_claim_id = models.UUIDField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-number"]
        constraints = [
            models.UniqueConstraint(fields=["business", "number"], name="sales_return_number"),
            models.CheckConstraint(
                condition=models.Q(refund_total__gte=0), name="sales_return_refund_nonneg"
            ),
        ]
        indexes = [models.Index(fields=["business", "-created_at"])]

    def __str__(self) -> str:
        return f"R-{self.number:04d}"


class SaleReturnLine(UUIDModel, AppendOnlyModel):
    sale_return = models.ForeignKey(SaleReturn, on_delete=models.PROTECT, related_name="lines")
    sale_line = models.ForeignKey(SaleLine, on_delete=models.PROTECT, related_name="return_lines")
    position = models.PositiveSmallIntegerField(default=0)
    product = models.ForeignKey("catalog.Product", on_delete=models.PROTECT, related_name="+")
    sku = models.CharField(max_length=64)  # snapshot
    name = models.CharField(max_length=255)  # snapshot
    unit_symbol = models.CharField(max_length=16)  # snapshot
    unit_decimals = models.PositiveSmallIntegerField()  # snapshot
    quantity = models.DecimalField(max_digits=14, decimal_places=3)
    condition = models.CharField(max_length=16, choices=ReturnCondition.choices)
    refund_amount = models.DecimalField(max_digits=14, decimal_places=2)  # TMT
    # What the goods cost when they were sold (FIFO), carried back with them. Five decimals.
    cost_total = models.DecimalField(max_digits=18, decimal_places=5)

    class Meta:
        ordering = ["position", "id"]
        constraints = [
            models.CheckConstraint(
                condition=models.Q(quantity__gt=0), name="sales_return_line_quantity_positive"
            ),
            models.CheckConstraint(
                condition=models.Q(refund_amount__gte=0), name="sales_return_line_refund_nonneg"
            ),
        ]


class ReturnInspection(UUIDModel, AppendOnlyModel):
    """The decision on goods that came back "awaiting inspection": sellable or damaged."""

    return_line = models.ForeignKey(
        SaleReturnLine, on_delete=models.PROTECT, related_name="inspections"
    )
    outcome = models.CharField(
        max_length=16,
        choices=[(ReturnCondition.SELLABLE, "Sellable"), (ReturnCondition.DAMAGED, "Damaged")],
    )
    quantity = models.DecimalField(max_digits=14, decimal_places=3)
    decided_by = models.ForeignKey("accounts.User", on_delete=models.PROTECT, related_name="+")
    decided_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["decided_at", "id"]
        constraints = [
            models.CheckConstraint(
                condition=models.Q(quantity__gt=0), name="sales_inspection_quantity_positive"
            ),
        ]
