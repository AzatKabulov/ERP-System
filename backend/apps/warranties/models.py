"""Warranty claims: a customer brings back something sold with a warranty and says what is wrong.

A claim is opened against one sale line (the warranty terms are the ones that line was sold with)
and closed once, with one outcome: repaired, replaced from stock, refunded (a customer return of
the sale), or rejected. Everything that happens is a `WarrantyEvent`; those rows are written once.
The stock movements and the return a claim causes are the history; these rows are the document
they belong to."""

from django.db import models
from django.db.models import Q

from apps.common.models import AppendOnlyModel, UUIDModel


class WarrantyClaim(UUIDModel):
    class Status(models.TextChoices):
        OPEN = "open", "Open"
        CLOSED = "closed", "Closed"

    class Outcome(models.TextChoices):
        REPAIR = "repair", "Repaired"
        REPLACEMENT = "replacement", "Replaced"
        REFUND = "refund", "Refunded"
        REJECTED = "rejected", "Rejected"

    business = models.ForeignKey("businesses.Business", on_delete=models.PROTECT, related_name="+")
    number = models.PositiveIntegerField()  # W-0001, per business
    sale = models.ForeignKey("sales.Sale", on_delete=models.PROTECT, related_name="warranty_claims")
    sale_line = models.ForeignKey(
        "sales.SaleLine", on_delete=models.PROTECT, related_name="warranty_claims"
    )
    product = models.ForeignKey("catalog.Product", on_delete=models.PROTECT, related_name="+")
    sku = models.CharField(max_length=64)  # snapshot
    name = models.CharField(max_length=255)  # snapshot
    # How many units are claimed (at most what was sold and not yet returned when it was opened).
    quantity = models.DecimalField(max_digits=14, decimal_places=3)
    customer_name = models.CharField(max_length=200, blank=True)  # snapshot from the sale
    customer_phone = models.CharField(max_length=60, blank=True)  # snapshot from the sale
    problem = models.CharField(max_length=1000)
    status = models.CharField(max_length=8, choices=Status.choices, default=Status.OPEN)
    outcome = models.CharField(max_length=12, choices=Outcome.choices, null=True, blank=True)
    # The warranty had run out, or the product had none, and the owner or a manager accepted the
    # claim anyway (the reason is the claim's first event).
    out_of_warranty = models.BooleanField(default=False)
    opened_by = models.ForeignKey("accounts.User", on_delete=models.PROTECT, related_name="+")
    opened_at = models.DateTimeField(auto_now_add=True)
    closed_by = models.ForeignKey(
        "accounts.User", null=True, blank=True, on_delete=models.PROTECT, related_name="+"
    )
    closed_at = models.DateTimeField(null=True, blank=True)
    resolution_note = models.TextField(blank=True)
    # The customer return a refund created (sales.SaleReturn; it points back at this claim).
    return_id = models.UUIDField(null=True, blank=True)

    class Meta:
        ordering = ["-number"]
        constraints = [
            models.UniqueConstraint(fields=["business", "number"], name="warranties_claim_number"),
            models.CheckConstraint(
                condition=Q(quantity__gt=0), name="warranties_claim_quantity_positive"
            ),
            # An open claim has no outcome yet; a closed one always has one, and a time.
            models.CheckConstraint(
                condition=Q(status="open", outcome__isnull=True, closed_at__isnull=True)
                | Q(status="closed", outcome__isnull=False, closed_at__isnull=False),
                name="warranties_claim_status_outcome",
            ),
            models.CheckConstraint(
                condition=Q(return_id__isnull=True) | Q(outcome="refund"),
                name="warranties_claim_return_only_refund",
            ),
        ]
        indexes = [
            models.Index(fields=["business", "status"]),
            models.Index(fields=["business", "-opened_at"]),
        ]

    def __str__(self) -> str:
        return f"W-{self.number:04d}"


class WarrantyEvent(UUIDModel, AppendOnlyModel):
    """What happened to a claim, in order: it was opened, notes were added, it was closed."""

    class Kind(models.TextChoices):
        OPENED = "opened", "Opened"
        NOTE = "note", "Note"
        CLOSED = "closed", "Closed"

    claim = models.ForeignKey(WarrantyClaim, on_delete=models.PROTECT, related_name="events")
    kind = models.CharField(max_length=8, choices=Kind.choices)
    note = models.TextField(blank=True)
    outcome = models.CharField(
        max_length=12, choices=WarrantyClaim.Outcome.choices, null=True, blank=True
    )  # set on the closing event
    actor = models.ForeignKey("accounts.User", on_delete=models.PROTECT, related_name="+")
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["created_at", "id"]
        indexes = [models.Index(fields=["claim", "created_at"])]
