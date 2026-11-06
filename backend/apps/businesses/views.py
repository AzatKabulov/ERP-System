from django.core.exceptions import ValidationError as DjangoValidationError
from django.db import transaction
from django.shortcuts import get_object_or_404
from rest_framework import generics
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.accounts import services as account_services
from apps.accounts.serializers import UserSerializer, password_errors
from apps.audit import services as audit
from apps.billing import api as billing_api
from apps.common.errors import ApiError

from . import services
from .access import BusinessAPIView, BusinessScopedMixin, restrict_to_locations
from .models import Business, ExchangeRate, Location, Membership
from .permissions import has_permission, permissions_for
from .serializers import (
    BusinessSerializer,
    ExchangeRateSerializer,
    LocationSerializer,
    StaffCreateSerializer,
    StaffSerializer,
    StaffUpdateSerializer,
)


class MeView(APIView):
    """Who is signed in, and what they may do in each business they belong to."""

    permission_classes = [IsAuthenticated]

    def _payload(self, user):
        memberships = (
            Membership.objects.filter(user=user, is_active=True, business__is_active=True)
            .select_related("business", "business__client")
            .prefetch_related("locations")
            .order_by("business__name")
        )
        return {
            "user": UserSerializer(user).data,
            "announcements": billing_api.announcements_for(user.preferred_language),
            "platform": billing_api.platform_payload(),
            "memberships": [
                {
                    "id": m.id,
                    "business": BusinessSerializer(m.business).data,
                    "role": m.role,
                    "permissions": permissions_for(m.role),
                    "subscription": billing_api.subscription_payload(m),
                    "locations": [
                        {"id": loc.id, "name": loc.name, "kind": loc.kind}
                        for loc in (
                            m.business.locations.filter(is_active=True)
                            if m.location_ids() is None
                            else m.locations.filter(is_active=True)
                        ).order_by("name")
                    ],
                }
                for m in memberships
            ],
        }

    def get(self, request):
        return Response(self._payload(request.user))

    def patch(self, request):
        serializer = UserSerializer(request.user, data=request.data, partial=True)
        serializer.is_valid(raise_exception=True)
        serializer.save()
        return Response(self._payload(request.user))


class BusinessDetailView(BusinessAPIView):
    permission_by_method = {"GET": "business.view", "PATCH": "business.manage"}

    def get(self, request, business_id):
        return Response(BusinessSerializer(request.business).data)

    def patch(self, request, business_id):
        serializer = BusinessSerializer(request.business, data=request.data, partial=True)
        serializer.is_valid(raise_exception=True)
        serializer.save()
        audit.record(
            "business.updated",
            actor=request.user,
            business=request.business,
            obj=request.business,
            metadata=serializer.validated_data,
        )
        return Response(serializer.data)


class ExchangeRateListCreateView(BusinessScopedMixin, generics.ListCreateAPIView):
    """History of the USD -> TMT rate; entering a new rate supersedes the old one."""

    serializer_class = ExchangeRateSerializer
    permission_by_method = {"GET": "exchange_rate.view", "POST": "exchange_rate.manage"}

    def get_queryset(self):
        return ExchangeRate.objects.filter(business=self.request.business).select_related("set_by")

    def perform_create(self, serializer):
        rate = serializer.save(business=self.request.business, set_by=self.request.user)
        audit.record(
            "exchange_rate.created",
            actor=self.request.user,
            business=self.request.business,
            obj=rate,
            metadata={"currency": rate.currency, "rate": str(rate.rate)},
        )


class LocationListCreateView(BusinessScopedMixin, generics.ListCreateAPIView):
    serializer_class = LocationSerializer
    permission_by_method = {"GET": "location.view", "POST": "location.manage"}

    def get_serializer_context(self):
        return {**super().get_serializer_context(), "business": self.request.business}

    def get_queryset(self):
        qs = restrict_to_locations(
            Location.objects.filter(business=self.request.business), self.request.membership, "id"
        )
        manage = has_permission(self.request.membership.role, "location.manage")
        if not (manage and self.request.query_params.get("include_inactive") == "1"):
            qs = qs.filter(is_active=True)
        return qs

    def create(self, request, *args, **kwargs):
        """One business is one shop (owner, 2026-10-31): the warehouse is the shop's own back
        room, not a second place, so a business cannot add another location. Otherwise one
        licence could run several shops. The business row is locked so two requests cannot both
        pass the check."""
        with transaction.atomic():
            Business.objects.select_for_update().get(pk=request.business.pk)
            if Location.objects.filter(business=request.business).exists():
                raise ApiError(
                    "single_location",
                    "A business has one shop; its warehouse is part of it",
                    status_code=409,
                )
            return super().create(request, *args, **kwargs)

    def perform_create(self, serializer):
        location = serializer.save(business=self.request.business)
        audit.record(
            "location.created",
            actor=self.request.user,
            business=self.request.business,
            obj=location,
            metadata={"name": location.name},
        )


class LocationDetailView(BusinessScopedMixin, generics.RetrieveUpdateAPIView):
    serializer_class = LocationSerializer
    permission_by_method = {"GET": "location.view", "PATCH": "location.manage"}
    http_method_names = ["get", "patch", "head", "options"]
    lookup_url_kwarg = "location_id"

    def get_serializer_context(self):
        return {**super().get_serializer_context(), "business": self.request.business}

    def get_queryset(self):
        return restrict_to_locations(
            Location.objects.filter(business=self.request.business), self.request.membership, "id"
        )

    def perform_update(self, serializer):
        location = serializer.save()
        audit.record(
            "location.updated",
            actor=self.request.user,
            business=self.request.business,
            obj=location,
            metadata=serializer.validated_data,
        )


class StaffListCreateView(BusinessScopedMixin, generics.ListAPIView):
    serializer_class = StaffSerializer
    permission_by_method = {"GET": "staff.view", "POST": "staff.manage"}

    def get_queryset(self):
        return (
            Membership.objects.filter(business=self.request.business)
            .select_related("user")
            .prefetch_related("locations")
            .order_by("user__username")
        )

    def post(self, request, business_id):
        serializer = StaffCreateSerializer(
            data=request.data, context={"business": request.business}
        )
        serializer.is_valid(raise_exception=True)
        membership = services.create_staff(
            request.business, request.user, data=serializer.validated_data
        )
        return Response(StaffSerializer(membership).data, status=201)


class StaffSendCodeView(BusinessAPIView):
    """Emails a staff member a one-time code to (re)set their password."""

    required_permission = "staff.manage"

    def post(self, request, business_id, staff_id):
        membership = get_object_or_404(
            Membership.objects.select_related("user"), pk=staff_id, business=request.business
        )
        if membership.user.is_active:
            account_services.send_code(membership.user, "reset", request.business.name)
        audit.record(
            "staff.code_sent", actor=request.user, business=request.business, obj=membership
        )
        return Response({"status": "accepted"}, status=202)


class StaffTemporaryPasswordView(BusinessAPIView):
    """The owner gives a staff member a temporary password (typed, or generated and shown once)
    when they forgot theirs and have no email for a code. The person must choose their own at
    the next sign-in."""

    required_permission = "staff.manage"

    def post(self, request, business_id, staff_id):
        membership = get_object_or_404(
            Membership.objects.select_related("user"), pk=staff_id, business=request.business
        )
        user = membership.user
        if user.pk == request.user.pk:
            raise ApiError(
                "use_password_change", "Change your own password in Settings", status_code=409
            )
        # A person who works for another business too (or runs this system) keeps a password
        # that only they control: otherwise one owner could take over their other account.
        elsewhere = Membership.objects.filter(user=user).exclude(business=request.business)
        if user.is_staff or user.is_superuser or elsewhere.exists():
            raise ApiError(
                "account_shared", "This account is used outside your business", status_code=409
            )
        password = request.data.get("password") or account_services.generate_temporary_password()
        try:
            account_services.set_password(user, password, temporary=True)
        except DjangoValidationError as exc:
            raise password_errors(exc, field="password") from exc
        audit.record(
            "staff.temporary_password",
            actor=request.user,
            business=request.business,
            obj=membership,
        )
        return Response({"password": password})


class StaffDetailView(BusinessAPIView):
    permission_by_method = {"GET": "staff.view", "PATCH": "staff.manage"}

    def _membership(self, request, staff_id):
        return get_object_or_404(
            Membership.objects.select_related("user"), pk=staff_id, business=request.business
        )

    def get(self, request, business_id, staff_id):
        return Response(StaffSerializer(self._membership(request, staff_id)).data)

    def patch(self, request, business_id, staff_id):
        membership = self._membership(request, staff_id)
        serializer = StaffUpdateSerializer(
            data=request.data, context={"business": request.business, "membership": membership}
        )
        serializer.is_valid(raise_exception=True)
        membership = services.update_staff(
            request.business, request.user, membership, serializer.validated_data
        )
        return Response(StaffSerializer(membership).data)
