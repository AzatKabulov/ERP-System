import uuid

from rest_framework.response import Response

from apps.businesses.access import BusinessAPIView
from apps.common.errors import ApiError

from .models import IdempotencyRecord


class OperationStatusView(BusinessAPIView):
    """After a timeout, crash or restart the app asks what became of an operation key.
    Only the caller's own operations are visible."""

    required_permission = "operations.view"

    def get(self, request, business_id, action: str, key: uuid.UUID):
        record = IdempotencyRecord.objects.filter(
            business=request.business, actor=request.user, action=action, key=key
        ).first()
        if record is None:
            raise ApiError(
                "operation_not_found", "No completed operation with this key", status_code=404
            )
        return Response(
            {
                "status": "completed",
                "action": action,
                "key": str(key),
                "response_status": record.response_status,
                "response": record.response_body,
                "completed_at": record.created_at,
            }
        )
