import hashlib
import json
import uuid

from django.core.serializers.json import DjangoJSONEncoder
from django.db import connection, transaction
from rest_framework.response import Response

from apps.common.errors import ApiError
from apps.common.middleware import current_request_id

from .models import AuditEvent, IdempotencyRecord

_SENSITIVE = {"password", "new_password", "old_password", "code", "token", "refresh", "access"}


def _clean(value):
    """Drop credentials/tokens from anything written to the audit trail."""
    if isinstance(value, dict):
        return {k: _clean(v) for k, v in value.items() if k.lower() not in _SENSITIVE}
    if isinstance(value, (list, tuple)):
        return [_clean(v) for v in value]
    return value


def record(action: str, *, actor=None, business=None, obj=None, metadata: dict | None = None):
    return AuditEvent.objects.create(
        action=action,
        actor=actor if getattr(actor, "pk", None) else None,
        business=business,
        object_type=type(obj).__name__ if obj is not None else "",
        object_id=str(obj.pk) if obj is not None else "",
        request_id=current_request_id()[:64],
        metadata=json.loads(json.dumps(_clean(metadata or {}), cls=DjangoJSONEncoder)),
    )


# ---- idempotent commands -------------------------------------------------------------------


def parse_key(request) -> uuid.UUID:
    raw = request.headers.get("Idempotency-Key")
    if not raw:
        raise ApiError(
            "idempotency_key_required",
            "This action needs an Idempotency-Key header",
            fields={"Idempotency-Key": [{"code": "required", "message": "Required"}]},
        )
    try:
        return uuid.UUID(raw)
    except ValueError as exc:
        raise ApiError("idempotency_key_invalid", "Idempotency-Key must be a UUID") from exc


def fingerprint(request) -> str:
    payload = json.dumps(
        request.data, sort_keys=True, separators=(",", ":"), ensure_ascii=False, default=str
    )
    return hashlib.sha256(f"{request.method}\n{request.path}\n{payload}".encode()).hexdigest()


def run_idempotent(request, *, business, action: str, handler) -> Response:
    """Run `handler() -> (status, body)` at most once per (business, user, action, key).

    * Same key, same request  -> the stored outcome is returned again (header Idempotent-Replay).
    * Same key, different request -> 422 idempotency_key_reused.
    * Concurrent duplicates serialise on an advisory lock; the second one sees the first's outcome.
    * The key is claimed in the same transaction as the work: if the work fails and rolls back,
      the key is free again, so a failed attempt never blocks a corrected retry.
    """
    key = parse_key(request)
    digest = fingerprint(request)
    with transaction.atomic():
        with connection.cursor() as cursor:
            cursor.execute(
                "SELECT pg_advisory_xact_lock(hashtextextended(%s, 0))",
                [f"{business.pk}:{request.user.pk}:{action}:{key}"],
            )
        existing = IdempotencyRecord.objects.filter(
            business=business, actor=request.user, action=action, key=key
        ).first()
        if existing is not None:
            if existing.fingerprint != digest:
                raise ApiError(
                    "idempotency_key_reused",
                    "This operation key was already used for a different request",
                    status_code=422,
                )
            return Response(
                existing.response_body,
                status=existing.response_status,
                headers={"Idempotent-Replay": "true"},
            )
        status, body = handler()
        body = json.loads(json.dumps(body, cls=DjangoJSONEncoder))
        IdempotencyRecord.objects.create(
            business=business,
            actor=request.user,
            action=action,
            key=key,
            fingerprint=digest,
            response_status=status,
            response_body=body,
        )
        return Response(body, status=status)
