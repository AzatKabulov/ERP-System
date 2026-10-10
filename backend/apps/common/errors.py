"""One error envelope for the whole API:

    {"error": {"code": "...", "message": "...", "params": {...}, "fields": {...},
               "request_id": "..."}}

`code` (and `params`) are what the app translates; `message` is an English diagnostic
for logs. Tracebacks and other businesses' data are never exposed.
"""

from django.core.exceptions import PermissionDenied as DjangoPermissionDenied
from django.core.exceptions import ValidationError as DjangoValidationError
from django.http import Http404, JsonResponse
from rest_framework import exceptions
from rest_framework.response import Response
from rest_framework.views import set_rollback


class ApiError(exceptions.APIException):
    """A business-rule failure with a stable, translatable code."""

    def __init__(
        self,
        code: str,
        message: str = "",
        *,
        status_code: int = 400,
        params: dict | None = None,
        fields: dict | None = None,
    ):
        super().__init__(detail=message or code, code=code)
        self.code = code
        self.status_code = status_code
        self.params = params or {}
        self.fields = fields or {}


def envelope(request, code: str, message: str, params=None, fields=None) -> dict:
    body = {"code": code, "message": message, "request_id": getattr(request, "request_id", None)}
    if params:
        body["params"] = params
    if fields:
        body["fields"] = fields
    return {"error": body}


def flatten(detail, prefix: str = "") -> dict[str, list[dict]]:
    """Turn DRF validation detail into {field: [{code, message}]}."""
    out: dict[str, list[dict]] = {}
    if isinstance(detail, dict):
        for key, value in detail.items():
            out.update(flatten(value, f"{prefix}.{key}" if prefix else str(key)))
    elif isinstance(detail, list):
        for index, item in enumerate(detail):
            if isinstance(item, (dict, list)):
                out.update(flatten(item, f"{prefix}.{index}" if prefix else str(index)))
            else:
                out.setdefault(prefix or "non_field_errors", []).append(
                    {"code": getattr(item, "code", "invalid"), "message": str(item)}
                )
    else:
        out.setdefault(prefix or "non_field_errors", []).append(
            {"code": getattr(detail, "code", "invalid"), "message": str(detail)}
        )
    return out


def exception_handler(exc, context):
    request = context.get("request")
    if isinstance(exc, DjangoValidationError):
        exc = exceptions.ValidationError(
            detail=exc.message_dict if hasattr(exc, "error_dict") else exc.messages
        )
    elif isinstance(exc, Http404):
        exc = exceptions.NotFound()
    elif isinstance(exc, DjangoPermissionDenied):
        exc = exceptions.PermissionDenied()
    if not isinstance(exc, exceptions.APIException):
        return None  # becomes a 500 via server_error() below

    headers = {}
    params = None
    fields = None
    if isinstance(exc, ApiError):
        code, message, params, fields = exc.code, str(exc.detail), exc.params, exc.fields
    elif isinstance(exc, exceptions.ValidationError):
        code, message, fields = "validation_error", "Invalid input", flatten(exc.detail)
    elif isinstance(exc, exceptions.ParseError):
        code, message = "malformed_request", "Malformed request body"
    elif isinstance(exc, exceptions.NotAuthenticated):
        code, message = "not_authenticated", "Authentication credentials were not provided"
    elif isinstance(exc, exceptions.AuthenticationFailed):
        codes = exc.get_codes()  # a string, or a dict for SimpleJWT's InvalidToken
        raw = codes.get("detail") if isinstance(codes, dict) else codes
        code = (
            "invalid_token"
            if raw in {"token_not_valid", "bad_authorization_header"}
            else ("session_revoked" if raw == "session_revoked" else "authentication_failed")
        )
        message = "Authentication failed"
    elif isinstance(exc, exceptions.PermissionDenied):
        code, message = "permission_denied", "You do not have permission to do this"
    elif isinstance(exc, exceptions.NotFound):
        code, message = "not_found", "Not found"
    elif isinstance(exc, exceptions.MethodNotAllowed):
        code, message = "method_not_allowed", "Method not allowed"
    elif isinstance(exc, exceptions.UnsupportedMediaType):
        code, message = "unsupported_media_type", "Unsupported media type"
    elif isinstance(exc, exceptions.Throttled):
        code, message = "rate_limited", "Too many requests"
        params = {"retry_after": int(exc.wait) if exc.wait else None}
        if exc.wait:
            headers["Retry-After"] = str(int(exc.wait))
    else:
        code, message = "error", "Request failed"

    auth_header = getattr(exc, "auth_header", None)
    if auth_header:
        headers["WWW-Authenticate"] = auth_header
    set_rollback()
    return Response(
        envelope(request, code, message, params, fields), status=exc.status_code, headers=headers
    )


def server_error(request, *args, **kwargs):
    return JsonResponse(envelope(request, "server_error", "Internal server error"), status=500)


def not_found(request, *args, **kwargs):
    return JsonResponse(envelope(request, "not_found", "Not found"), status=404)
