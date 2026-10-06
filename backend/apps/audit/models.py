from django.conf import settings
from django.db import models
from django.utils import timezone

from apps.common.models import AppendOnlyModel, UUIDModel


class AuditEvent(UUIDModel, AppendOnlyModel):
    """Who did what, when, to which record. Append-only (ORM guard + PostgreSQL trigger)."""

    business = models.ForeignKey(
        "businesses.Business", on_delete=models.PROTECT, null=True, blank=True, related_name="+"
    )
    actor = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.PROTECT, null=True, blank=True, related_name="+"
    )
    action = models.CharField(max_length=80)
    object_type = models.CharField(max_length=60, blank=True)
    object_id = models.CharField(max_length=64, blank=True)
    request_id = models.CharField(max_length=64, blank=True)
    metadata = models.JSONField(default=dict, blank=True)
    created_at = models.DateTimeField(default=timezone.now)

    class Meta:
        ordering = ["-created_at"]
        indexes = [models.Index(fields=["business", "-created_at"])]


class IdempotencyRecord(UUIDModel):
    """The stored outcome of a stock-changing command, keyed by the client's operation key.
    A retry with the same key returns this outcome instead of acting twice."""

    business = models.ForeignKey("businesses.Business", on_delete=models.PROTECT, related_name="+")
    actor = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.PROTECT, related_name="+")
    action = models.CharField(max_length=80)
    key = models.UUIDField()
    fingerprint = models.CharField(max_length=64)
    response_status = models.PositiveSmallIntegerField()
    response_body = models.JSONField()
    created_at = models.DateTimeField(default=timezone.now)

    class Meta:
        constraints = [
            models.UniqueConstraint(
                fields=["business", "actor", "action", "key"], name="audit_idempotency_unique"
            )
        ]
