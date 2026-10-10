from django.db.models import Q
from django.shortcuts import get_object_or_404
from rest_framework import generics
from rest_framework.response import Response

from apps.audit.services import run_idempotent
from apps.businesses.access import (
    BusinessAPIView,
    BusinessScopedMixin,
    require_location,
    restrict_to_locations,
)

from . import services
from .models import StockCount, Transfer
from .serializers import (
    CountEntrySerializer,
    CountSerializer,
    CountStartSerializer,
    CountSummarySerializer,
    ReasonInputSerializer,
    ReceiveInputSerializer,
    TransferInputSerializer,
    TransferSerializer,
    TransferSummarySerializer,
)


def _number(text: str, prefix: str) -> int | None:
    digits = text.strip().upper().removeprefix(prefix).lstrip("-").lstrip("0")
    return int(digits) if digits.isdigit() else None


# ---- transfers ------------------------------------------------------------------------------


def _transfers(request):
    qs = (
        Transfer.objects.filter(business=request.business)
        .select_related("from_location", "to_location", "created_by", "received_by", "cancelled_by")
        .prefetch_related("lines__product__unit")
    )
    allowed = request.membership.location_ids()
    if allowed is not None:
        qs = qs.filter(Q(from_location_id__in=allowed) | Q(to_location_id__in=allowed))
    return qs


class TransferListCreateView(BusinessScopedMixin, generics.GenericAPIView):
    permission_by_method = {"GET": "transfer.view", "POST": "transfer.create"}

    def get(self, request, business_id):
        qs = _transfers(request)
        params = request.query_params
        if params.get("status"):
            qs = qs.filter(status=params["status"])
        if params.get("location"):
            qs = qs.filter(
                Q(from_location_id=params["location"]) | Q(to_location_id=params["location"])
            )
        number = _number(params.get("q", ""), "T")
        if params.get("q", "").strip():
            qs = qs.filter(number=number) if number is not None else qs.none()
        page = self.paginate_queryset(qs)
        return self.get_paginated_response(TransferSummarySerializer(page, many=True).data)

    def post(self, request, business_id):
        serializer = TransferInputSerializer(
            data=request.data, context={"business": request.business}
        )
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data
        require_location(request.membership, data["from_location"].pk)

        def handler():
            transfer = services.dispatch_transfer(
                request.business, request.user, request.membership, data
            )
            fresh = get_object_or_404(_transfers(request), pk=transfer.pk)
            return 201, TransferSerializer(fresh).data

        return run_idempotent(
            request, business=request.business, action="transfer_dispatch", handler=handler
        )


class TransferDetailView(BusinessAPIView):
    required_permission = "transfer.view"

    def get(self, request, business_id, transfer_id):
        transfer = get_object_or_404(_transfers(request), pk=transfer_id)
        return Response(TransferSerializer(transfer).data)


class TransferReceiveView(BusinessAPIView):
    required_permission = "transfer.receive"

    def post(self, request, business_id, transfer_id):
        serializer = ReceiveInputSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data

        def handler():
            services.receive_transfer(
                request.business, request.user, request.membership, transfer_id, data
            )
            fresh = get_object_or_404(_transfers(request), pk=transfer_id)
            return 200, TransferSerializer(fresh).data

        return run_idempotent(
            request, business=request.business, action="transfer_receive", handler=handler
        )


class TransferCancelView(BusinessAPIView):
    required_permission = "transfer.create"

    def post(self, request, business_id, transfer_id):
        serializer = ReasonInputSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        reason = serializer.validated_data["reason"]

        def handler():
            services.cancel_transfer(
                request.business, request.user, request.membership, transfer_id, reason
            )
            fresh = get_object_or_404(_transfers(request), pk=transfer_id)
            return 200, TransferSerializer(fresh).data

        return run_idempotent(
            request, business=request.business, action="transfer_cancel", handler=handler
        )


# ---- counts ---------------------------------------------------------------------------------


def _counts(request):
    return restrict_to_locations(
        StockCount.objects.filter(business=request.business)
        .select_related("location", "business", "created_by", "submitted_by", "decided_by")
        .prefetch_related("lines__product__unit"),
        request.membership,
        "location_id",
    )


class CountListCreateView(BusinessScopedMixin, generics.GenericAPIView):
    permission_by_method = {"GET": "count.view", "POST": "count.perform"}

    def get(self, request, business_id):
        qs = _counts(request)
        params = request.query_params
        if params.get("status"):
            qs = qs.filter(status=params["status"])
        if params.get("location"):
            qs = qs.filter(location_id=params["location"])
        page = self.paginate_queryset(qs)
        return self.get_paginated_response(CountSummarySerializer(page, many=True).data)

    def post(self, request, business_id):
        serializer = CountStartSerializer(data=request.data, context={"business": request.business})
        serializer.is_valid(raise_exception=True)
        count = services.start_count(
            request.business, request.user, request.membership, serializer.validated_data
        )
        return Response(
            CountSerializer(get_object_or_404(_counts(request), pk=count.pk)).data, status=201
        )


class CountDetailView(BusinessAPIView):
    required_permission = "count.view"

    def get(self, request, business_id, count_id):
        return Response(CountSerializer(get_object_or_404(_counts(request), pk=count_id)).data)


class CountLinesView(BusinessAPIView):
    required_permission = "count.perform"

    def put(self, request, business_id, count_id):
        serializer = CountEntrySerializer(data=request.data, context={"business": request.business})
        serializer.is_valid(raise_exception=True)
        services.enter_counts(
            request.business,
            request.user,
            request.membership,
            count_id,
            serializer.validated_data["lines"],
        )
        return Response(CountSerializer(get_object_or_404(_counts(request), pk=count_id)).data)


class CountSubmitView(BusinessAPIView):
    required_permission = "count.perform"

    def post(self, request, business_id, count_id):
        services.submit_count(request.business, request.user, request.membership, count_id)
        return Response(CountSerializer(get_object_or_404(_counts(request), pk=count_id)).data)


class CountApproveView(BusinessAPIView):
    required_permission = "count.approve"

    def post(self, request, business_id, count_id):
        serializer = ReasonInputSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        reason = serializer.validated_data["reason"]

        def handler():
            services.approve_count(
                request.business, request.user, request.membership, count_id, reason
            )
            fresh = get_object_or_404(_counts(request), pk=count_id)
            return 200, CountSerializer(fresh).data

        return run_idempotent(
            request, business=request.business, action="count_approve", handler=handler
        )


class CountCancelView(BusinessAPIView):
    required_permission = "count.perform"

    def post(self, request, business_id, count_id):
        serializer = ReasonInputSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        services.cancel_count(
            request.business,
            request.user,
            request.membership,
            count_id,
            serializer.validated_data["reason"],
        )
        return Response(CountSerializer(get_object_or_404(_counts(request), pk=count_id)).data)
