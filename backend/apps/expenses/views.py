import uuid
from datetime import date

from django.shortcuts import get_object_or_404
from rest_framework import generics
from rest_framework.response import Response

from apps.businesses.access import BusinessAPIView, BusinessScopedMixin, restrict_to_locations
from apps.common.errors import ApiError

from . import services
from .models import Expense, ExpenseCategory
from .serializers import (
    ExpenseCategorySerializer,
    ExpenseSerializer,
    ExpenseWriteSerializer,
    VoidSerializer,
)


def _invalid(name: str, message: str) -> ApiError:
    return ApiError(
        "validation_error", message, fields={name: [{"code": "invalid", "message": message}]}
    )


def _date_param(params, name: str) -> date | None:
    raw = params.get(name)
    if not raw:
        return None
    try:
        return date.fromisoformat(raw)
    except ValueError as exc:
        raise _invalid(name, "Dates are YYYY-MM-DD") from exc


def _uuid_param(params, name: str) -> uuid.UUID | None:
    raw = params.get(name)
    if not raw:
        return None
    try:
        return uuid.UUID(raw)
    except ValueError as exc:
        raise _invalid(name, "Not a valid id") from exc


def _expenses(request):
    return restrict_to_locations(
        Expense.objects.filter(business=request.business).select_related(
            "category", "location", "attachment", "created_by"
        ),
        request.membership,
    )


def _filtered(request, *, with_category: bool):
    """The expenses a request's filters select. Voided ones are left out unless asked for."""
    params = request.query_params
    qs = _expenses(request)
    date_from, date_to = _date_param(params, "date_from"), _date_param(params, "date_to")
    if date_from:
        qs = qs.filter(spent_on__gte=date_from)
    if date_to:
        qs = qs.filter(spent_on__lte=date_to)
    location = _uuid_param(params, "location")
    if location:
        qs = qs.filter(location_id=location)
    if with_category:
        category = _uuid_param(params, "category")
        if category:
            qs = qs.filter(category_id=category)
        query = params.get("q", "").strip()
        if query:
            qs = qs.filter(description__icontains=query)
        if params.get("include_void", "0").lower() not in {"1", "true"}:
            qs = qs.filter(voided_at__isnull=True)
    return qs


def _context(request, **extra) -> dict:
    return {"request": request, "business": request.business, **extra}


# ---- categories ----------------------------------------------------------------------------


class CategoryListCreateView(BusinessScopedMixin, generics.GenericAPIView):
    permission_by_method = {"GET": "expense.view", "POST": "expense.manage"}

    def get(self, request, business_id):
        qs = ExpenseCategory.objects.filter(business=request.business)
        active = request.query_params.get("active")
        if active == "1":
            qs = qs.filter(is_active=True)
        elif active == "0":
            qs = qs.filter(is_active=False)
        page = self.paginate_queryset(qs)
        return self.get_paginated_response(ExpenseCategorySerializer(page, many=True).data)

    def post(self, request, business_id):
        serializer = ExpenseCategorySerializer(data=request.data, context=_context(request))
        serializer.is_valid(raise_exception=True)
        category = services.save_category(request.business, request.user, serializer.validated_data)
        return Response(ExpenseCategorySerializer(category).data, status=201)


class CategoryDetailView(BusinessAPIView):
    permission_by_method = {"PATCH": "expense.manage"}

    def patch(self, request, business_id, category_id):
        category = get_object_or_404(ExpenseCategory, pk=category_id, business=request.business)
        serializer = ExpenseCategorySerializer(
            category, data=request.data, partial=True, context=_context(request)
        )
        serializer.is_valid(raise_exception=True)
        category = services.save_category(
            request.business, request.user, serializer.validated_data, category
        )
        return Response(ExpenseCategorySerializer(category).data)


# ---- expenses ------------------------------------------------------------------------------


class ExpenseListCreateView(BusinessScopedMixin, generics.GenericAPIView):
    permission_by_method = {"GET": "expense.view", "POST": "expense.manage"}

    def get(self, request, business_id):
        page = self.paginate_queryset(_filtered(request, with_category=True))
        return self.get_paginated_response(ExpenseSerializer(page, many=True).data)

    def post(self, request, business_id):
        serializer = ExpenseWriteSerializer(data=request.data, context=_context(request))
        serializer.is_valid(raise_exception=True)
        expense = services.create_expense(
            request.business, request.user, request.membership, serializer.validated_data
        )
        fresh = get_object_or_404(_expenses(request), pk=expense.pk)
        return Response(ExpenseSerializer(fresh).data, status=201)


class ExpenseDetailView(BusinessAPIView):
    permission_by_method = {"GET": "expense.view", "PATCH": "expense.manage"}

    def get(self, request, business_id, expense_id):
        return Response(
            ExpenseSerializer(get_object_or_404(_expenses(request), pk=expense_id)).data
        )

    def patch(self, request, business_id, expense_id):
        expense = get_object_or_404(_expenses(request), pk=expense_id)
        serializer = ExpenseWriteSerializer(
            data=request.data,
            partial=True,
            context=_context(request, instance=expense),
        )
        serializer.is_valid(raise_exception=True)
        services.update_expense(
            request.business,
            request.user,
            request.membership,
            expense_id,
            serializer.validated_data,
        )
        return Response(
            ExpenseSerializer(get_object_or_404(_expenses(request), pk=expense_id)).data
        )


class ExpenseVoidView(BusinessAPIView):
    required_permission = "expense.manage"

    def post(self, request, business_id, expense_id):
        get_object_or_404(_expenses(request), pk=expense_id)
        serializer = VoidSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        services.void_expense(
            request.business,
            request.user,
            request.membership,
            expense_id,
            serializer.validated_data["reason"],
        )
        return Response(
            ExpenseSerializer(get_object_or_404(_expenses(request), pk=expense_id)).data
        )


class ExpenseSummaryView(BusinessAPIView):
    required_permission = "expense.view"

    def get(self, request, business_id):
        return Response(services.summarize(_filtered(request, with_category=False)))
