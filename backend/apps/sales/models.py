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
