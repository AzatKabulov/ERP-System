"""The business of selling access: who is a client, what they bought, until when, what we
told each other. Platform-level data: nothing here is reachable through a store's own
/businesses/<id>/ routes except the support conversation and the status the app shows."""

from django.conf import settings
from django.db import models
from django.utils import timezone

from apps.common.models import AppendOnlyModel, TimestampedModel, UUIDModel


class Plan(UUIDModel, TimestampedModel):
    """A package we sell. `months` is None for the free-form "custom days" plan."""

    code = models.SlugField(unique=True)
    name = models.CharField(max_length=80)
    months = models.PositiveSmallIntegerField(null=True, blank=True)
    price = models.DecimalField(max_digits=12, decimal_places=2, null=True, blank=True)
    currency = models.CharField(max_length=3, default="TMT")
    is_active = models.BooleanField(default=True)
    sort_order = models.PositiveSmallIntegerField(default=0)

    class Meta:
        ordering = ["sort_order", "months"]

    def __str__(self) -> str:
        return self.name


class Client(UUIDModel, TimestampedModel):
    """One paying store: its subscription state and whom to call. Exactly one per business
    that we sell to; a business with no Client row is treated as free (see status.py)."""

    class Override(models.TextChoices):
        NONE = "", "None"
        SUSPENDED = "suspended", "Suspended"  # cut off now, whatever was paid
        FREE = "free", "Free access"  # a demo or partner shop, never expires

    business = models.OneToOneField(
        "businesses.Business", on_delete=models.PROTECT, related_name="client"
    )
    contact_name = models.CharField(max_length=200, blank=True)
    contact_phone = models.CharField(max_length=60, blank=True)
    contact_email = models.EmailField(blank=True)
    plan = models.ForeignKey(
        Plan, null=True, blank=True, on_delete=models.PROTECT, related_name="+"
    )
    # The end of the last paid day, in the store's own time zone. Changed only through
    # services.py, which writes a SubscriptionEvent in the same transaction.
    paid_until = models.DateTimeField(null=True, blank=True)
    is_trial = models.BooleanField(default=False)
    override = models.CharField(max_length=16, choices=Override.choices, blank=True, default="")

    def __str__(self) -> str:
        return str(self.business)


class SubscriptionEvent(UUIDModel, AppendOnlyModel):
    """Every change to a client, never edited: a wrong entry is fixed by another entry."""

    class Kind(models.TextChoices):
        CREATED = "created", "Client created"
        TRIAL = "trial", "Free trial"
        RENEW = "renew", "Package"
        EXTEND = "extend", "Custom days"
        CORRECTION = "correction", "End date corrected"
        SUSPEND = "suspend", "Suspended"
        RESUME = "resume", "Resumed"
        FREE_ON = "free_on", "Free access on"
        FREE_OFF = "free_off", "Free access off"
        PASSWORD_RESET = "password_reset", "Owner password reset"

    class Method(models.TextChoices):
        CASH = "cash", "Cash"
        CARD = "card", "Card"
        TRANSFER = "transfer", "Bank transfer"
        OTHER = "other", "Other"

    client = models.ForeignKey(Client, on_delete=models.PROTECT, related_name="events")
    kind = models.CharField(max_length=16, choices=Kind.choices)
    plan = models.ForeignKey(
        Plan, null=True, blank=True, on_delete=models.PROTECT, related_name="+"
    )
    months = models.PositiveSmallIntegerField(null=True, blank=True)
    days = models.PositiveIntegerField(null=True, blank=True)
    old_until = models.DateTimeField(null=True, blank=True)
    new_until = models.DateTimeField(null=True, blank=True)
    amount = models.DecimalField(max_digits=12, decimal_places=2, null=True, blank=True)
    currency = models.CharField(max_length=3, blank=True)
    method = models.CharField(max_length=16, choices=Method.choices, blank=True)
    reference = models.CharField(max_length=120, blank=True)
    note = models.TextField(blank=True)
    actor = models.ForeignKey(
        settings.AUTH_USER_MODEL, null=True, on_delete=models.PROTECT, related_name="+"
    )
    created_at = models.DateTimeField(default=timezone.now)

    class Meta:
        ordering = ["-created_at"]
        indexes = [models.Index(fields=["client", "-created_at"])]


class ClientNote(UUIDModel, AppendOnlyModel):
    """Our own diary about a client: "called, will pay Friday"."""

    client = models.ForeignKey(Client, on_delete=models.PROTECT, related_name="notes")
    author = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.PROTECT, related_name="+")
    text = models.TextField()
    created_at = models.DateTimeField(default=timezone.now)

    class Meta:
        ordering = ["-created_at"]


class SupportRequest(UUIDModel, TimestampedModel):
    """A question from a store to us, with the conversation that follows."""

    class Status(models.TextChoices):
        OPEN = "open", "Waiting for us"
        ANSWERED = "answered", "Answered"
        CLOSED = "closed", "Closed"

    business = models.ForeignKey(
        "businesses.Business", on_delete=models.PROTECT, related_name="support_requests"
    )
    raised_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.PROTECT, related_name="+"
    )
    subject = models.CharField(max_length=160)
    status = models.CharField(max_length=10, choices=Status.choices, default=Status.OPEN)
    screen = models.CharField(max_length=80, blank=True)  # where in the app they were
    app_version = models.CharField(max_length=40, blank=True)

    class Meta:
        ordering = ["-updated_at"]
        indexes = [models.Index(fields=["business", "-updated_at"])]


class SupportMessage(UUIDModel, AppendOnlyModel):
    request = models.ForeignKey(SupportRequest, on_delete=models.PROTECT, related_name="messages")
    from_store = models.BooleanField()  # False: written by us
    author = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.PROTECT, related_name="+")
    text = models.TextField()
    created_at = models.DateTimeField(default=timezone.now)

    class Meta:
        ordering = ["created_at"]


class Announcement(UUIDModel, TimestampedModel):
    """A notice shown to every store ("maintenance tonight at 23:00")."""

    message_ru = models.TextField()
    message_tk = models.TextField(blank=True)  # falls back to Russian when empty
    starts_at = models.DateTimeField(default=timezone.now)
    ends_at = models.DateTimeField()
    is_active = models.BooleanField(default=True)

    class Meta:
        ordering = ["-starts_at"]

    def message_for(self, language: str) -> str:
        return self.message_tk if language == "tk" and self.message_tk else self.message_ru
