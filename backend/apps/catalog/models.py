from django.core.validators import MaxValueValidator, MinValueValidator
from django.db import models
from django.db.models.functions import Lower

from apps.common.models import TimestampedModel, UUIDModel


class Unit(UUIDModel, TimestampedModel):
    """How a product is counted. `decimal_places` is the quantity precision: pieces are 0,
    litres or kilograms may be 2 or 3. Stock quantities must respect it."""

    business = models.ForeignKey(
        "businesses.Business", on_delete=models.PROTECT, related_name="units"
    )
    name = models.CharField(max_length=60)
    symbol = models.CharField(max_length=16)
    decimal_places = models.PositiveSmallIntegerField(default=0, validators=[MaxValueValidator(3)])
    is_active = models.BooleanField(default=True)

    class Meta:
        ordering = ["name"]
        constraints = [
            models.UniqueConstraint("business", Lower("name"), name="catalog_unit_name_ci_unique"),
            models.CheckConstraint(
                condition=models.Q(decimal_places__lte=3), name="catalog_unit_decimals_max3"
            ),
        ]

    def __str__(self) -> str:
        return self.name


class Category(UUIDModel, TimestampedModel):
    business = models.ForeignKey(
        "businesses.Business", on_delete=models.PROTECT, related_name="categories"
    )
    name = models.CharField(max_length=120)
    is_active = models.BooleanField(default=True)

    class Meta:
        ordering = ["name"]
        verbose_name_plural = "categories"
        constraints = [
            models.UniqueConstraint(
                "business", Lower("name"), name="catalog_category_name_ci_unique"
            )
        ]

    def __str__(self) -> str:
        return self.name


class Brand(UUIDModel, TimestampedModel):
    business = models.ForeignKey(
        "businesses.Business", on_delete=models.PROTECT, related_name="brands"
    )
    name = models.CharField(max_length=120)
    is_active = models.BooleanField(default=True)

    class Meta:
        ordering = ["name"]
        constraints = [
            models.UniqueConstraint("business", Lower("name"), name="catalog_brand_name_ci_unique")
        ]

    def __str__(self) -> str:
        return self.name


class Product(UUIDModel, TimestampedModel):
    class PriceCurrency(models.TextChoices):
        TMT = "TMT", "TMT"
        USD = "USD", "USD"

    business = models.ForeignKey(
        "businesses.Business", on_delete=models.PROTECT, related_name="products"
    )
    sku = models.CharField(max_length=64)
    name = models.CharField(max_length=255)
    category = models.ForeignKey(
        Category, null=True, blank=True, on_delete=models.PROTECT, related_name="products"
    )
    brand = models.ForeignKey(
        Brand, null=True, blank=True, on_delete=models.PROTECT, related_name="products"
    )
    unit = models.ForeignKey(Unit, on_delete=models.PROTECT, related_name="products")

    # The selling price as the shop states it (decision D3): TMT or USD. A USD price is
    # converted to TMT at the business's latest exchange rate when it is sold.
    price_amount = models.DecimalField(
        max_digits=14, decimal_places=2, validators=[MinValueValidator(0)]
    )
    price_currency = models.CharField(
        max_length=3, choices=PriceCurrency.choices, default=PriceCurrency.TMT
    )
    # Pre-fills purchase orders. Always TMT. Real cost comes from receipts (FIFO layers).
    default_purchase_cost = models.DecimalField(
        max_digits=14, decimal_places=2, null=True, blank=True, validators=[MinValueValidator(0)]
    )

    # Warranty terms (decision D8a): copied onto each sale so later edits never change them.
    warranty_months = models.PositiveSmallIntegerField(
        default=0, validators=[MaxValueValidator(120)]
    )
    warranty_terms = models.TextField(blank=True)

    is_active = models.BooleanField(default=True)
    # Case-folded name, SKU, brand, category and barcodes; searched with `contains` so
    # Cyrillic and Turkmen letters match regardless of the database collation.
    search_key = models.TextField(blank=True, editable=False, default="")

    class Meta:
        ordering = ["name", "id"]
        constraints = [
            models.UniqueConstraint("business", Lower("sku"), name="catalog_product_sku_ci_unique"),
            models.CheckConstraint(
                condition=models.Q(price_amount__gte=0), name="catalog_product_price_nonneg"
            ),
            models.CheckConstraint(
                condition=models.Q(warranty_months__lte=120), name="catalog_product_warranty_max"
            ),
        ]
        indexes = [models.Index(fields=["business", "is_active", "name"])]

    def __str__(self) -> str:
        return f"{self.sku} {self.name}"


class Barcode(UUIDModel):
    business = models.ForeignKey("businesses.Business", on_delete=models.PROTECT, related_name="+")
    product = models.ForeignKey(Product, on_delete=models.CASCADE, related_name="barcodes")
    code = models.CharField(max_length=64)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["created_at", "code"]
        constraints = [
            models.UniqueConstraint(fields=["business", "code"], name="catalog_barcode_unique")
        ]

    def __str__(self) -> str:
        return self.code


class ReorderSetting(UUIDModel, TimestampedModel):
    """Minimum and target stock for one product at one location (used from Phase 7)."""

    business = models.ForeignKey("businesses.Business", on_delete=models.PROTECT, related_name="+")
    product = models.ForeignKey(Product, on_delete=models.CASCADE, related_name="reorder_settings")
    location = models.ForeignKey("businesses.Location", on_delete=models.PROTECT, related_name="+")
    minimum = models.DecimalField(
        max_digits=14, decimal_places=3, validators=[MinValueValidator(0)]
    )
    target = models.DecimalField(max_digits=14, decimal_places=3, validators=[MinValueValidator(0)])

    class Meta:
        constraints = [
            models.UniqueConstraint(fields=["product", "location"], name="catalog_reorder_unique"),
            models.CheckConstraint(
                condition=models.Q(minimum__gte=0) & models.Q(target__gte=models.F("minimum")),
                name="catalog_reorder_target_ge_min",
            ),
        ]
