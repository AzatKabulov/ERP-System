import zoneinfo

from django.conf import settings
from django.core.exceptions import ValidationError
from django.core.validators import MinValueValidator
from django.db import models
from django.db.models.functions import Lower
from django.utils import timezone

from apps.common.models import AppendOnlyModel, TimestampedModel, UUIDModel

LANGUAGES = [("ru", "Русский"), ("tk", "Türkmençe")]


def validate_timezone(value: str) -> None:
    try:
        zoneinfo.ZoneInfo(value)
    except (zoneinfo.ZoneInfoNotFoundError, ValueError) as exc:
        raise ValidationError("Unknown time zone.") from exc


class Role(models.TextChoices):
    OWNER = "owner", "Owner"
    MANAGER = "manager", "Manager"
    SALES = "sales", "Sales"
    WAREHOUSE = "warehouse", "Warehouse"


class Business(UUIDModel, TimestampedModel):
    """A tenant. Every business-owned record points here."""

    CURRENCIES = [("TMT", "TMT")]  # decided 2026-10-06; USD is only an optional *price* currency

    name = models.CharField(max_length=200)
    currency = models.CharField(max_length=3, choices=CURRENCIES, default="TMT")
    default_language = models.CharField(max_length=2, choices=LANGUAGES, default="ru")
    document_language = models.CharField(max_length=2, choices=LANGUAGES, default="ru")
    timezone = models.CharField(
        max_length=64, default="Asia/Ashgabat", validators=[validate_timezone]
    )
    is_active = models.BooleanField(default=True)

    class Meta:
        verbose_name_plural = "businesses"

    def __str__(self) -> str:
        return self.name


class Location(UUIDModel, TimestampedModel):
    class Kind(models.TextChoices):
        STORE = "store", "Store"
        WAREHOUSE = "warehouse", "Warehouse"

    business = models.ForeignKey(Business, on_delete=models.PROTECT, related_name="locations")
    name = models.CharField(max_length=120)
    kind = models.CharField(max_length=16, choices=Kind.choices, default=Kind.STORE)
    is_active = models.BooleanField(default=True)

    class Meta:
        constraints = [
            models.UniqueConstraint(
                "business", Lower("name"), name="businesses_location_name_ci_unique"
            )
        ]
        ordering = ["name"]

    def __str__(self) -> str:
        return self.name


class Membership(UUIDModel, TimestampedModel):
    """Links a user to a business with one role. Owners and managers see every location;
    sales and warehouse staff see only the locations assigned to them."""

    user = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.PROTECT, related_name="memberships"
    )
    business = models.ForeignKey(Business, on_delete=models.PROTECT, related_name="memberships")
    role = models.CharField(max_length=16, choices=Role.choices)
    all_locations = models.BooleanField(default=False)
    locations = models.ManyToManyField(Location, blank=True, related_name="memberships")
    is_active = models.BooleanField(default=True)

    class Meta:
        constraints = [
            models.UniqueConstraint(
                fields=["user", "business"], name="businesses_membership_unique"
            )
        ]

    def __str__(self) -> str:
        return f"{self.user} @ {self.business} ({self.role})"

    def location_ids(self) -> set | None:
        """None means every location of the business; otherwise the permitted IDs."""
        if self.all_locations or self.role in (Role.OWNER, Role.MANAGER):
            return None
        return set(self.locations.filter(is_active=True).values_list("id", flat=True))


class ExchangeRate(UUIDModel, AppendOnlyModel):
    """The USD -> TMT rate entered by an owner or manager. Rates are never edited: a new
    entry supersedes the old one, and the rate used for a sale is copied onto the sale,
    so history can never change. The business currency itself stays TMT."""

    class Currency(models.TextChoices):
        USD = "USD", "USD"

    business = models.ForeignKey(Business, on_delete=models.PROTECT, related_name="exchange_rates")
    currency = models.CharField(max_length=3, choices=Currency.choices, default=Currency.USD)
    # TMT per 1 unit of `currency`
    rate = models.DecimalField(max_digits=18, decimal_places=6, validators=[MinValueValidator(0)])
    set_by = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.PROTECT, related_name="+")
    created_at = models.DateTimeField(default=timezone.now)

    class Meta:
        ordering = ["-created_at"]
        indexes = [models.Index(fields=["business", "currency", "-created_at"])]
        constraints = [
            models.CheckConstraint(condition=models.Q(rate__gt=0), name="businesses_rate_positive")
        ]
