"""What a store sees of the billing system: its own subscription status (inside /me/), our
announcements, and the support conversation. Nothing else of ours is reachable from here."""

from django.conf import settings
from django.db import transaction
from django.shortcuts import get_object_or_404
from django.utils import timezone
from rest_framework import serializers
from rest_framework.response import Response

from apps.businesses.access import BusinessAPIView
from apps.businesses.models import Role
from apps.common.errors import ApiError

from .models import Announcement, SupportMessage, SupportRequest
from .status import status_of


def subscription_payload(membership) -> dict | None:
    """The subscription as one member may see it. The owner and manager see the dates (money
    information, like cost prices); everyone else only learns that work is blocked."""
    status = status_of(membership.business)
    if membership.role in (Role.OWNER, Role.MANAGER):
        return {
            "state": status.state,
            "is_trial": status.is_trial,
            "ends_at": status.ends_at,
            "grace_ends_at": status.grace_ends_at,
            "days_left": status.days_left,
        }
    return {"state": status.state} if status.blocked else None


def announcements_for(language: str) -> list[dict]:
    now = timezone.now()
    rows = Announcement.objects.filter(is_active=True, starts_at__lte=now, ends_at__gte=now)
    return [{"id": a.id, "message": a.message_for(language)} for a in rows]


def platform_payload() -> dict:
    return {
        "support_phone": settings.PLATFORM_SUPPORT_PHONE,
        "support_note": settings.PLATFORM_SUPPORT_NOTE,
    }


class _SupportBase(BusinessAPIView):
    # A store must be able to reach us exactly when its subscription has a problem.
    subscription_exempt = True


class MessageSerializer(serializers.ModelSerializer):
    class Meta:
        model = SupportMessage
        fields = ["id", "from_store", "text", "created_at"]


class SupportRequestSerializer(serializers.ModelSerializer):
    messages = MessageSerializer(many=True, read_only=True)

    class Meta:
        model = SupportRequest
        fields = ["id", "subject", "status", "created_at", "updated_at", "messages"]


class SupportCreateSerializer(serializers.Serializer):
    subject = serializers.CharField(max_length=160)
    body = serializers.CharField(max_length=4000)
    screen = serializers.CharField(max_length=80, required=False, allow_blank=True, default="")
    app_version = serializers.CharField(max_length=40, required=False, allow_blank=True, default="")


class SupportReplySerializer(serializers.Serializer):
    body = serializers.CharField(max_length=4000)


class SupportListCreateView(_SupportBase):
    permission_by_method = {"GET": "support.view", "POST": "support.write"}

    def get(self, request, business_id):
        rows = (
            SupportRequest.objects.filter(business=request.business)
            .prefetch_related("messages")
            .order_by("-updated_at")[:50]
        )
        return Response({"results": SupportRequestSerializer(rows, many=True).data})

    def post(self, request, business_id):
        data = SupportCreateSerializer(data=request.data)
        data.is_valid(raise_exception=True)
        v = data.validated_data
        with transaction.atomic():
            ticket = SupportRequest.objects.create(
                business=request.business,
                raised_by=request.user,
                subject=v["subject"].strip(),
                screen=v["screen"],
                app_version=v["app_version"],
            )
            SupportMessage.objects.create(
                request=ticket, from_store=True, author=request.user, text=v["body"].strip()
            )
        return Response(SupportRequestSerializer(ticket).data, status=201)


class SupportReplyView(_SupportBase):
    permission_by_method = {"POST": "support.write"}

    def post(self, request, business_id, request_id):
        data = SupportReplySerializer(data=request.data)
        data.is_valid(raise_exception=True)
        with transaction.atomic():
            ticket = get_object_or_404(
                SupportRequest.objects.select_for_update(),
                pk=request_id,
                business=request.business,
            )
            if ticket.status == SupportRequest.Status.CLOSED:
                raise ApiError("support_closed", "This request is closed", status_code=409)
            SupportMessage.objects.create(
                request=ticket,
                from_store=True,
                author=request.user,
                text=data.validated_data["body"].strip(),
            )
            ticket.status = SupportRequest.Status.OPEN
            ticket.save(update_fields=["status", "updated_at"])
        return Response(SupportRequestSerializer(ticket).data, status=201)
