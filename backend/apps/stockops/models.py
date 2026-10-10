"""Moving goods between locations, and counting what is on the shelves.

A transfer is dispatched from one location (the goods leave its sellable stock and wait
"in transit" at the destination, so they are never available in two places) and then received
there, or cancelled (they go back). A stock count records what a person found on the shelf
against what the system said when the count started; an authorised user approves it and the
differences are posted as adjustments through the ledger. The stock movements are the history;
these rows are the documents they belong to."""

from django.db import models
from django.db.models import F, Q

from apps.common.models import TimestampedModel, UUIDModel


class Transfer(UUIDModel, TimestampedModel):
    class Status(models.TextChoices):
        DISPATCHED = "dispatched", "In transit"
        RECEIVED = "received", "Received"
        PARTIALLY_RECEIVED = "partially_received", "Received, some missing"
        CANCELLED = "cancelled", "Cancelled"

    business = models.ForeignKey("businesses.Business", on_delete=models.PROTECT, related_name="+")
    number = models.PositiveIntegerField()  # T-0001, per business
    from_location = models.ForeignKey(
        "businesses.Location", on_delete=models.PROTECT, related_name="+"
    )
    to_location = models.ForeignKey(
        "businesses.Location", on_delete=models.PROTECT, related_name="+"
    )
    status = models.CharField(max_length=24, choices=Status.choices, default=Status.DISPATCHED)
    note = models.CharField(max_length=500, blank=True)
    created_by = models.ForeignKey("accounts.User", on_delete=models.PROTECT, related_name="+")
    received_by = models.ForeignKey(
        "accounts.User", null=True, blank=True, on_delete=models.PROTECT, related_name="+"
    )
    received_at = models.DateTimeField(null=True, blank=True)
    discrepancy_reason = models.TextField(blank=True)
    cancelled_by = models.ForeignKey(
        "accounts.User", null=True, blank=True, on_delete=models.PROTECT, related_name="+"
    )
    cancelled_at = models.DateTimeField(null=True, blank=True)
    cancel_reason = models.TextField(blank=True)

    class Meta:
        ordering = ["-number"]
        constraints = [
            models.UniqueConstraint(fields=["business", "number"], name="stockops_transfer_number"),
            models.CheckConstraint(
                condition=~Q(from_location=F("to_location")), name="stockops_transfer_two_places"
            ),
        ]
        indexes = [models.Index(fields=["business", "status"])]

    def __str__(self) -> str:
        return f"T-{self.number:04d}"


class TransferLine(UUIDModel):
    transfer = models.ForeignKey(Transfer, on_delete=models.CASCADE, related_name="lines")
    product = models.ForeignKey("catalog.Product", on_delete=models.PROTECT, related_name="+")
    quantity = models.DecimalField(max_digits=14, decimal_places=3)
    received_quantity = models.DecimalField(
        max_digits=14, decimal_places=3, null=True, blank=True
    )  # set when the transfer is received

    class Meta:
        ordering = ["id"]
        constraints = [
            models.UniqueConstraint(fields=["transfer", "product"], name="stockops_tline_product"),
            models.CheckConstraint(
                condition=Q(quantity__gt=0), name="stockops_tline_quantity_positive"
            ),
        ]


class StockCount(UUIDModel, TimestampedModel):
    class Status(models.TextChoices):
        OPEN = "open", "Counting"
        SUBMITTED = "submitted", "Waiting for approval"
        APPROVED = "approved", "Approved"
        CANCELLED = "cancelled", "Cancelled"

    class Scope(models.TextChoices):
        FULL = "full", "Everything at the location"
        PARTIAL = "partial", "Chosen products"

    business = models.ForeignKey("businesses.Business", on_delete=models.PROTECT, related_name="+")
    number = models.PositiveIntegerField()  # C-0001, per business
    location = models.ForeignKey("businesses.Location", on_delete=models.PROTECT, related_name="+")
    scope = models.CharField(max_length=8, choices=Scope.choices, default=Scope.FULL)
    status = models.CharField(max_length=12, choices=Status.choices, default=Status.OPEN)
    note = models.CharField(max_length=500, blank=True)
    created_by = models.ForeignKey("accounts.User", on_delete=models.PROTECT, related_name="+")
    # The moment the system quantities were noted. Anything that moves after it is flagged.
    started_at = models.DateTimeField()
    submitted_by = models.ForeignKey(
        "accounts.User", null=True, blank=True, on_delete=models.PROTECT, related_name="+"
    )
    submitted_at = models.DateTimeField(null=True, blank=True)
    decided_by = models.ForeignKey(
        "accounts.User", null=True, blank=True, on_delete=models.PROTECT, related_name="+"
    )
    decided_at = models.DateTimeField(null=True, blank=True)
    decision_reason = models.TextField(blank=True)

    class Meta:
        ordering = ["-number"]
        constraints = [
            models.UniqueConstraint(fields=["business", "number"], name="stockops_count_number")
        ]
        indexes = [models.Index(fields=["business", "status"])]

    def __str__(self) -> str:
        return f"C-{self.number:04d}"


class StockCountLine(UUIDModel):
    count = models.ForeignKey(StockCount, on_delete=models.CASCADE, related_name="lines")
    product = models.ForeignKey("catalog.Product", on_delete=models.PROTECT, related_name="+")
    # Sellable quantity the system showed when the count started.
    baseline_quantity = models.DecimalField(max_digits=14, decimal_places=3)
    counted_quantity = models.DecimalField(max_digits=14, decimal_places=3, null=True, blank=True)
    note = models.CharField(max_length=300, blank=True)

    class Meta:
        ordering = ["id"]
        constraints = [
            models.UniqueConstraint(fields=["count", "product"], name="stockops_cline_product"),
            models.CheckConstraint(
                condition=Q(counted_quantity__isnull=True) | Q(counted_quantity__gte=0),
                name="stockops_cline_counted_nonneg",
            ),
        ]
