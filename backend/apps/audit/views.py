import uuid

from django.db.models import Q
from rest_framework import generics
from rest_framework.response import Response

from apps.businesses.access import BusinessAPIView, BusinessScopedMixin
from apps.common.errors import ApiError
from apps.common.pagination import StandardPagination
from apps.common.params import date_param, local_day_bounds, uuid_param

from .models import AuditEvent, IdempotencyRecord
from .serializers import AuditEventSerializer


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


class AuditPagination(StandardPagination):
    max_limit = 100  # a larger `limit` is clamped to this


class AuditListView(BusinessScopedMixin, generics.GenericAPIView):
    """The business's activity history, newest first (owner and manager). Only events of THIS
    business: events without a business (sign-ins, password changes) and other businesses'
    events never appear.

    Filters: `date_from` / `date_to` (calendar days in the business time zone, both included),
    `actor` (user id), `action` (the exact action, or a prefix up to a dot: `sale` matches
    `sale.completed`), `q` (case-insensitive text in the action, object type or object id).
    """

    required_permission = "audit.view"
    pagination_class = AuditPagination
    serializer_class = AuditEventSerializer

    def get_queryset(self):
        params = self.request.query_params
        events = AuditEvent.objects.filter(business=self.request.business)
        start, end = local_day_bounds(
            self.request.business, date_param(params, "date_from"), date_param(params, "date_to")
        )
        if start is not None:
            events = events.filter(created_at__gte=start)
        if end is not None:
            events = events.filter(created_at__lt=end)
        actor = uuid_param(params, "actor")
        if actor is not None:
            events = events.filter(actor_id=actor)
        action = params.get("action", "").strip()
        if action:
            events = events.filter(Q(action=action) | Q(action__startswith=f"{action}."))
        text = params.get("q", "").strip()
        if text:
            events = events.filter(
                Q(action__icontains=text)
                | Q(object_type__icontains=text)
                | Q(object_id__icontains=text)
            )
        return events.select_related("actor").order_by("-created_at", "-id")

    def get(self, request, business_id):
        page = self.paginate_queryset(self.get_queryset())
        return self.get_paginated_response(AuditEventSerializer(page, many=True).data)


class AuditActionsView(BusinessAPIView):
    """The distinct action names recorded for this business, sorted (for the filter's list)."""

    required_permission = "audit.view"

    def get(self, request, business_id):
        actions = (
            AuditEvent.objects.filter(business=request.business)
            .order_by("action")
            .values_list("action", flat=True)
            .distinct()
        )
        return Response({"actions": list(actions)})
