from datetime import date, datetime, time
from zoneinfo import ZoneInfo

from django.db.models import Q
from django.http import HttpResponse
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
from apps.businesses.permissions import has_permission
from apps.common.errors import ApiError
from apps.common.negotiation import IgnoreClientContentNegotiation

from . import services
from .documents import LABELS, number, render_document
from .models import Customer, Sale
from .serializers import (
    CustomerSerializer,
    SaleInputSerializer,
    SaleSerializer,
    SaleSummarySerializer,
)


def _sales(request):
    return restrict_to_locations(
        Sale.objects.filter(business=request.business)
        .select_related("location", "cashier", "business")
        .prefetch_related("lines", "payments"),
        request.membership,
    )


def _context(request) -> dict:
    return {
        "request": request,
        "business": request.business,
        "can_view_cost": has_permission(request.membership.role, "sales.cost.view"),
    }


def _day_bound(request, value: str, end: bool) -> datetime:
    try:
        day = date.fromisoformat(value)
    except ValueError as exc:
        raise ApiError("validation_error", "Dates are YYYY-MM-DD") from exc
    zone = ZoneInfo(request.business.timezone)
    return datetime.combine(day, time.max if end else time.min, tzinfo=zone)


# ---- customers -----------------------------------------------------------------------------


class CustomerListCreateView(BusinessScopedMixin, generics.GenericAPIView):
    permission_by_method = {"GET": "customer.view", "POST": "customer.manage"}

    def get(self, request, business_id):
        qs = Customer.objects.filter(business=request.business)
        active = request.query_params.get("active", "1")
        if active == "1":
            qs = qs.filter(is_active=True)
        elif active == "0":
            qs = qs.filter(is_active=False)
        for token in request.query_params.get("q", "").casefold().split():
            qs = qs.filter(search_key__contains=token)
        page = self.paginate_queryset(qs)
        return self.get_paginated_response(CustomerSerializer(page, many=True).data)

    def post(self, request, business_id):
        serializer = CustomerSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        customer = services.save_customer(request.business, request.user, serializer.validated_data)
        return Response(CustomerSerializer(customer).data, status=201)


class CustomerDetailView(BusinessAPIView):
    permission_by_method = {"GET": "customer.view", "PATCH": "customer.manage"}

    def get(self, request, business_id, customer_id):
        customer = get_object_or_404(Customer, pk=customer_id, business=request.business)
        return Response(CustomerSerializer(customer).data)

    def patch(self, request, business_id, customer_id):
        customer = get_object_or_404(Customer, pk=customer_id, business=request.business)
        serializer = CustomerSerializer(customer, data=request.data, partial=True)
        serializer.is_valid(raise_exception=True)
        customer = services.save_customer(
            request.business, request.user, serializer.validated_data, customer
        )
        return Response(CustomerSerializer(customer).data)


# ---- sales ---------------------------------------------------------------------------------


class SaleListCreateView(BusinessScopedMixin, generics.GenericAPIView):
    permission_by_method = {"GET": "sales.view", "POST": "sales.create"}

    def get_queryset(self):
        params = self.request.query_params
        qs = _sales(self.request)
        if params.get("location"):
            qs = qs.filter(location_id=params["location"])
        if params.get("cashier"):
            qs = qs.filter(cashier_id=params["cashier"])
        if params.get("date_from"):
            qs = qs.filter(created_at__gte=_day_bound(self.request, params["date_from"], False))
        if params.get("date_to"):
            qs = qs.filter(created_at__lte=_day_bound(self.request, params["date_to"], True))
        query = params.get("q", "").strip()
        if query:
            digits = query.upper().removeprefix("S-").lstrip("0")
            match = Q(customer_name__icontains=query)
            if digits.isdigit():
                match |= Q(number=int(digits))
            qs = qs.filter(match)
        return qs

    def get(self, request, business_id):
        page = self.paginate_queryset(self.get_queryset())
        return self.get_paginated_response(
            SaleSummarySerializer(page, many=True, context=_context(request)).data
        )

    def post(self, request, business_id):
        serializer = SaleInputSerializer(data=request.data, context={"business": request.business})
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data
        require_location(request.membership, data["location"].pk)

        def handler():
            sale = services.complete_sale(request.business, request.user, request.membership, data)
            fresh = _sales(request).get(pk=sale.pk)
            return 201, SaleSerializer(fresh, context=_context(request)).data

        return run_idempotent(
            request, business=request.business, action="sale_complete", handler=handler
        )


class SaleDetailView(BusinessAPIView):
    required_permission = "sales.view"

    def get(self, request, business_id, sale_id):
        sale = get_object_or_404(_sales(request), pk=sale_id)
        return Response(SaleSerializer(sale, context=_context(request)).data)


class SaleDocumentView(BusinessAPIView):
    """The receipt (80 mm roll) or invoice (A4) as a PDF, in the requested language. The
    language defaults to the business's document language, whatever the interface language is."""

    required_permission = "sales.view"
    content_negotiation_class = IgnoreClientContentNegotiation

    def get(self, request, business_id, sale_id):
        kind = request.query_params.get("kind", "receipt")
        lang = request.query_params.get("lang") or request.business.document_language
        if kind not in ("receipt", "invoice") or lang not in LABELS:
            raise ApiError(
                "validation_error",
                "kind is receipt or invoice; lang is ru or tk",
                fields={
                    "kind" if kind not in ("receipt", "invoice") else "lang": [
                        {"code": "invalid_choice", "message": "Invalid"}
                    ]
                },
            )
        sale = get_object_or_404(_sales(request), pk=sale_id)
        response = HttpResponse(
            render_document(sale, kind=kind, lang=lang), content_type="application/pdf"
        )
        response["Content-Disposition"] = f'inline; filename="{kind}-{number(sale)}.pdf"'
        response["Cache-Control"] = "private, no-store"
        return response
