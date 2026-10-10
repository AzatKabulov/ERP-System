import uuid

from django.db.models import Prefetch, Q
from django.shortcuts import get_object_or_404
from rest_framework import generics
from rest_framework.response import Response

from apps.audit.services import run_idempotent
from apps.businesses.access import BusinessAPIView, BusinessScopedMixin, restrict_to_locations
from apps.common.errors import ApiError
from apps.sales.models import SaleReturn

from . import services
from .models import WarrantyClaim, WarrantyEvent
from .serializers import (
    ClaimSerializer,
    CloseClaimSerializer,
    NoteSerializer,
    OpenClaimSerializer,
)


def _claims(request):
    """The claims of this business at the locations the caller may see (a claim sits where its
    sale was made)."""
    return restrict_to_locations(
        WarrantyClaim.objects.filter(business=request.business).select_related(
            "sale", "sale_line", "opened_by"
        ),
        request.membership,
        "sale__location_id",
    )


def _detail(request, claim_id) -> dict:
    claim = get_object_or_404(
        _claims(request).prefetch_related(
            Prefetch("events", queryset=WarrantyEvent.objects.select_related("actor"))
        ),
        pk=claim_id,
    )
    context = {"business": request.business, "with_events": True}
    return ClaimSerializer(claim, context=context).data


def _number(text: str) -> int | None:
    digits = text.strip().upper().removeprefix("W").lstrip("-").lstrip("0")
    return int(digits) if digits.isdigit() else None


class ClaimListCreateView(BusinessScopedMixin, generics.GenericAPIView):
    permission_by_method = {"GET": "warranty.view", "POST": "warranty.open"}

    def get(self, request, business_id):
        params = request.query_params
        qs = _claims(request)
        if params.get("status"):
            if params["status"] not in WarrantyClaim.Status.values:
                raise ApiError(
                    "validation_error",
                    "status is open or closed",
                    fields={"status": [{"code": "invalid_choice", "message": "Invalid"}]},
                )
            qs = qs.filter(status=params["status"])
        if params.get("sale"):
            try:
                qs = qs.filter(sale_id=uuid.UUID(params["sale"]))
            except ValueError as exc:
                raise ApiError(
                    "validation_error",
                    "Not a valid id",
                    fields={"sale": [{"code": "invalid", "message": "Invalid"}]},
                ) from exc
        query = params.get("q", "").strip()
        if query:
            match = Q(customer_name__icontains=query) | Q(name__icontains=query)
            number = _number(query)
            if number is not None:
                match |= Q(number=number)
            qs = qs.filter(match)
        page = self.paginate_queryset(qs)
        numbers = dict(
            SaleReturn.objects.filter(
                pk__in=[c.return_id for c in page if c.return_id]
            ).values_list("pk", "number")
        )
        context = {"business": request.business, "return_numbers": numbers}
        return self.get_paginated_response(ClaimSerializer(page, many=True, context=context).data)

    def post(self, request, business_id):
        serializer = OpenClaimSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        claim = services.open_claim(
            request.business, request.user, request.membership, serializer.validated_data
        )
        return Response(_detail(request, claim.pk), status=201)


class ClaimDetailView(BusinessAPIView):
    required_permission = "warranty.view"

    def get(self, request, business_id, claim_id):
        return Response(_detail(request, claim_id))


class ClaimNoteView(BusinessAPIView):
    required_permission = "warranty.open"

    def post(self, request, business_id, claim_id):
        serializer = NoteSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        get_object_or_404(_claims(request), pk=claim_id)
        services.add_note(
            request.business,
            request.user,
            request.membership,
            claim_id,
            serializer.validated_data["note"],
        )
        return Response(_detail(request, claim_id), status=201)


class ClaimCloseView(BusinessAPIView):
    """Close a claim with its outcome. Needs an Idempotency-Key: a replacement moves stock and a
    refund gives money back, so a retry must never do either twice."""

    required_permission = "warranty.resolve"

    def post(self, request, business_id, claim_id):
        serializer = CloseClaimSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        get_object_or_404(_claims(request), pk=claim_id)
        data = serializer.validated_data

        def handler():
            services.close_claim(
                request.business,
                request.user,
                request.membership,
                claim_id,
                data["outcome"],
                data["note"],
            )
            return 200, _detail(request, claim_id)

        return run_idempotent(
            request, business=request.business, action="warranty_resolve", handler=handler
        )
