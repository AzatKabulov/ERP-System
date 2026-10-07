"""Private files (a receipt photo, a scanned document).

The row is the record of what was uploaded; the bytes live outside the database under
`settings.PRIVATE_FILES_ROOT`, at `<business id>/<attachment id>`, never at a name the client
chose. A file is written once and never edited (ORM guard plus PostgreSQL trigger)."""

from django.db import models
from django.db.models import Q

from apps.common.models import AppendOnlyModel, UUIDModel


class Attachment(UUIDModel, AppendOnlyModel):
    business = models.ForeignKey("businesses.Business", on_delete=models.PROTECT, related_name="+")
    # The client's file name, cleaned up, for display only. Never part of a path.
    name = models.CharField(max_length=255)
    # Found from the file's first bytes, not from what the client claimed.
    content_type = models.CharField(max_length=64)
    size = models.PositiveIntegerField()  # bytes
    sha256 = models.CharField(max_length=64)
    uploaded_by = models.ForeignKey("accounts.User", on_delete=models.PROTECT, related_name="+")
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-created_at", "id"]
        constraints = [
            models.CheckConstraint(condition=Q(size__gt=0), name="attachments_size_positive")
        ]
        indexes = [models.Index(fields=["business", "-created_at"])]

    def __str__(self) -> str:
        return self.name

    @property
    def storage_name(self) -> str:
        """Where the bytes are, relative to the private files root."""
        return f"{self.business_id}/{self.pk}"
