"""Storing and reading private files.

What a file is comes from its first bytes (its signature), never from its extension or from
the content type the client claims. The client's file name is kept only as display text; the
bytes are stored under the attachment's own id."""

import hashlib
import logging

from django.core.files.base import ContentFile
from django.db import transaction

from apps.audit import services as audit
from apps.common.errors import ApiError

from .models import Attachment
from .storage import PrivateStorage

logger = logging.getLogger(__name__)

MAX_BYTES = 5 * 1024 * 1024  # 5 MB; the one place to change the limit


def detect_content_type(head: bytes) -> str | None:
    """JPEG, PNG, WebP or PDF by signature; None for anything else."""
    if head.startswith(b"\xff\xd8\xff"):
        return "image/jpeg"
    if head.startswith(b"\x89PNG\r\n\x1a\n"):
        return "image/png"
    if head[:4] == b"RIFF" and head[8:12] == b"WEBP":
        return "image/webp"
    if head.startswith(b"%PDF-"):
        return "application/pdf"
    return None


def clean_name(raw: str) -> str:
    """The client's file name made safe to show and to put in a header: no directories, no
    control characters, no quotes."""
    name = raw.replace("\\", "/").rsplit("/", 1)[-1]
    name = "".join(" " if ch.isspace() else ch for ch in name)
    name = "".join(ch for ch in name if ch.isprintable() and ch not in "\"'`")
    name = " ".join(name.split())[:255].strip()
    return name or "file"


def too_large() -> ApiError:
    return ApiError(
        "file_too_large",
        "The file is too large",
        params={"max_bytes": MAX_BYTES},
    )


def store_upload(business, actor, upload) -> Attachment:
    """Validate an uploaded file and keep it. `upload` is Django's uploaded file, or None."""
    if upload is None or not upload.size:
        raise ApiError(
            "file_required",
            "Send the file in the form field 'file'",
            fields={"file": [{"code": "required", "message": "Required"}]},
        )
    if upload.size > MAX_BYTES:
        raise too_large()
    data = upload.read()
    content_type = detect_content_type(data[:16])
    if content_type is None:
        raise ApiError(
            "file_type_not_allowed",
            "Only JPEG, PNG, WebP and PDF files are accepted",
            fields={"file": [{"code": "file_type_not_allowed", "message": "Not allowed"}]},
        )
    attachment = Attachment(
        business=business,
        name=clean_name(upload.name or ""),
        content_type=content_type,
        size=len(data),
        sha256=hashlib.sha256(data).hexdigest(),
        uploaded_by=actor,
    )
    with transaction.atomic():
        attachment.save(force_insert=True)
        stored = PrivateStorage().save(attachment.storage_name, ContentFile(data))
        if stored != attachment.storage_name:  # an id is never reused; refuse rather than guess
            raise RuntimeError("an attachment file already exists under this id")
        audit.record(
            "attachment.uploaded",
            actor=actor,
            business=business,
            obj=attachment,
            metadata={
                "name": attachment.name,
                "content_type": content_type,
                "size": attachment.size,
                "sha256": attachment.sha256,
            },
        )
    return attachment


def read_bytes(attachment: Attachment) -> bytes:
    try:
        with PrivateStorage().open(attachment.storage_name, "rb") as handle:
            return handle.read()
    except FileNotFoundError as exc:
        logger.error("attachment %s has a record but no file", attachment.pk)
        raise ApiError("file_missing", "The file is not available", status_code=404) from exc
