"""Sales. A completed sale is a historical fact: the sale, its lines and its payments are
append-only (ORM guard plus PostgreSQL trigger). Everything a document or a later return needs
is copied onto the rows (names, prices, rate, discount, cost, warranty terms), so editing the
catalog afterwards never changes what was sold."""

from django.core.validators import MinValueValidator
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
    TRANSFER = "transfer", "Bank transfer"


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
    total = models.DecimalField(max_digits=14, decimal_places=2)  # TMT
    change_given = models.DecimalField(max_digits=14, decimal_places=2, default=0)
    # The USD -> TMT rate used for USD-priced lines (null when no line was priced in USD).
    usd_rate = models.DecimalField(max_digits=18, decimal_places=6, null=True, blank=True)
    note = models.CharField(max_length=500, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-number"]
        constraints = [
            models.UniqueConstraint(fields=["business", "number"], name="sales_sale_number"),
            models.CheckConstraint(
                condition=models.Q(total__gte=0), name="sales_sale_total_nonneg"
            ),
            models.CheckConstraint(
                condition=models.Q(change_given__gte=0), name="sales_sale_change_nonneg"
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
    # The price as the shop states it, and what it came to in TMT at the rate in force.
    price_amount = models.DecimalField(max_digits=14, decimal_places=2)
    price_currency = models.CharField(max_length=3)
    unit_price = models.DecimalField(max_digits=14, decimal_places=2)  # TMT
    gross = models.DecimalField(max_digits=14, decimal_places=2)  # quantity x unit_price, rounded
    discount = models.DecimalField(max_digits=14, decimal_places=2, default=0)
    line_total = models.DecimalField(max_digits=14, decimal_places=2)  # gross - discount
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
                condition=models.Q(discount__gte=0) & models.Q(discount__lte=models.F("gross")),
                name="sales_line_discount_valid",
            ),
        ]


class SalePayment(UUIDModel, AppendOnlyModel):
    sale = models.ForeignKey(Sale, on_delete=models.PROTECT, related_name="payments")
    position = models.PositiveSmallIntegerField(default=0)
    method = models.CharField(max_length=16, choices=PaymentMethod.choices)
    amount = models.DecimalField(
        max_digits=14, decimal_places=2, validators=[MinValueValidator(0)]
    )  # TMT

    class Meta:
        ordering = ["position", "id"]
        constraints = [
            models.CheckConstraint(condition=models.Q(amount__gt=0), name="sales_payment_positive")
        ]
