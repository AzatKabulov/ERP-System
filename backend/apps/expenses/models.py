"""What the shop spends money on (rent, wages, utilities, transport, ...), kept simply: an
amount in TMT, a date, a category, the location it belongs to and an optional receipt photo.

An expense can be corrected (every change is audited with the old and the new value) or voided
with a reason, never deleted."""

from django.db import models
from django.db.models import Q
from django.db.models.functions import Lower

from apps.common.models import TimestampedModel, UUIDModel


class ExpenseCategory(UUIDModel, TimestampedModel):
    business = models.ForeignKey("businesses.Business", on_delete=models.PROTECT, related_name="+")
    name = models.CharField(max_length=120)
    is_active = models.BooleanField(default=True)

    class Meta:
        ordering = ["name", "id"]
        verbose_name_plural = "expense categories"
        constraints = [
            models.UniqueConstraint(
                "business", Lower("name"), name="expenses_category_name_ci_unique"
            )
        ]

    def __str__(self) -> str:
        return self.name


class Expense(UUIDModel, TimestampedModel):
    business = models.ForeignKey("businesses.Business", on_delete=models.PROTECT, related_name="+")
    category = models.ForeignKey(ExpenseCategory, on_delete=models.PROTECT, related_name="expenses")
    location = models.ForeignKey("businesses.Location", on_delete=models.PROTECT, related_name="+")
    amount = models.DecimalField(max_digits=14, decimal_places=2)  # TMT
    spent_on = models.DateField()  # the shop's calendar day, never in the future
    description = models.CharField(max_length=500, blank=True)
    # An optional photo or scan of the receipt (a private file of the same business).
    attachment = models.ForeignKey(
        "attachments.Attachment", null=True, blank=True, on_delete=models.PROTECT, related_name="+"
    )
    created_by = models.ForeignKey("accounts.User", on_delete=models.PROTECT, related_name="+")
    voided_at = models.DateTimeField(null=True, blank=True)
    voided_by = models.ForeignKey(
        "accounts.User", null=True, blank=True, on_delete=models.PROTECT, related_name="+"
    )
    void_reason = models.CharField(max_length=500, blank=True)

    class Meta:
        ordering = ["-spent_on", "-created_at", "id"]
        constraints = [
            models.CheckConstraint(condition=Q(amount__gt=0), name="expenses_amount_positive"),
            # A voided expense always says why; a live one never carries a reason.
            models.CheckConstraint(
                condition=Q(voided_at__isnull=True, void_reason="")
                | (Q(voided_at__isnull=False) & ~Q(void_reason="")),
                name="expenses_void_has_reason",
            ),
        ]
        indexes = [
            models.Index(fields=["business", "-spent_on"]),
            models.Index(fields=["business", "category"]),
        ]

    @property
    def is_voided(self) -> bool:
        return self.voided_at is not None

    def __str__(self) -> str:
        return f"{self.spent_on} {self.amount}"
