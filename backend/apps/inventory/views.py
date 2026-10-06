from decimal import ROUND_HALF_UP, Decimal

from rest_framework import generics

from apps.audit.services import run_idempotent
from apps.businesses.access import (
    BusinessAPIView,
    BusinessScopedMixin,
    require_location,
    restrict_to_locations,
)
from apps.businesses.permissions import has_permission

from . import services
from .models import MovementType, StockBalance, StockMovement
from .serializers import (
    AdjustmentSerializer,
    OpeningSerializer,
    StockBalanceSerializer,
    StockMovementSerializer,
)

CENT = Decimal("0.01")


def _can_view_cost(request) -> bool:
    return has_permission(request.membership.role, "stock.cost.view")


class StockListView(BusinessScopedMixin, generics.GenericAPIView):
    """Current stock per product, location and condition. Only the caller's locations.
    Costs appear only for roles with `stock.cost.view`."""

    required_permission = "stock.view"

    def get_queryset(self):
        params = self.request.query_params
        qs = restrict_to_locations(
            StockBalance.objects.filter(business=self.request.business).select_related(
                "product__unit", "location"
            ),
            self.request.membership,
        )
        if params.get("include_zero") != "1":
            qs = qs.filter(quantity__gt=0)
        if params.get("location"):
            qs = qs.filter(location_id=params["location"])
        if params.get("product"):
            qs = qs.filter(product_id=params["product"])
        if params.get("condition"):
            qs = qs.filter(condition=params["condition"])
        for token in params.get("q", "").casefold().split():
            qs = qs.filter(product__search_key__contains=token)
        return qs.order_by("product__name", "location__name", "condition", "id")

    def get(self, request, business_id):
        page = self.paginate_queryset(self.get_queryset())
        rows = StockBalanceSerializer(page, many=True).data
        if _can_view_cost(request):
            values = services.stock_values([b.pk for b in page])
            for row, balance in zip(rows, page, strict=True):
                value = (values.get(balance.pk) or Decimal("0")).quantize(
                    CENT, rounding=ROUND_HALF_UP
                )
                row["value"] = str(value)
                row["average_cost"] = (
                    str((value / balance.quantity).quantize(CENT, rounding=ROUND_HALF_UP))
                    if balance.quantity
                    else None
                )
        return self.get_paginated_response(rows)


class StockMovementListView(BusinessScopedMixin, generics.GenericAPIView):
    """The ledger, newest first. Read-only; there is no endpoint that edits it."""

    required_permission = "stock.history.view"

    def get_queryset(self):
        params = self.request.query_params
        qs = restrict_to_locations(
            StockMovement.objects.filter(business=self.request.business).select_related(
                "product__unit", "location", "actor"
            ),
            self.request.membership,
        )
        for param, field in (
            ("product", "product_id"),
            ("location", "location_id"),
            ("condition", "condition"),
        ):
            if params.get(param):
                qs = qs.filter(**{field: params[param]})
        if params.get("type") in MovementType.values:
            qs = qs.filter(movement_type=params["type"])
        if params.get("document"):
            qs = qs.filter(document_id=params["document"])
        return qs

    def get(self, request, business_id):
        page = self.paginate_queryset(self.get_queryset())
        data = StockMovementSerializer(
            page, many=True, context={"can_view_cost": _can_view_cost(request)}
        ).data
        return self.get_paginated_response(data)


def _movement_summary(posted) -> list[dict]:
    return [
        {
            "product": str(m.product_id),
            "condition": m.condition,
            "quantity": str(m.quantity),
            "unit_cost": str(m.unit_cost),
        }
        for m in posted.movements
    ]


class OpeningStockView(BusinessAPIView):
    required_permission = "stock.opening.post"

    def post(self, request, business_id):
        serializer = OpeningSerializer(data=request.data, context={"business": request.business})
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data
        require_location(request.membership, data["location"].pk)

        def handler():
            result = services.post_opening_stock(
                request.business, request.user, data["location"], data["lines"], data["note"]
            )
            return 201, {
                "document_id": result["document_id"],
                "location": data["location"].pk,
                "movements": _movement_summary(result["posted"]),
            }

        return run_idempotent(
            request, business=request.business, action="stock_opening", handler=handler
        )


class AdjustmentView(BusinessAPIView):
    required_permission = "stock.adjust"

    def post(self, request, business_id):
        serializer = AdjustmentSerializer(data=request.data, context={"business": request.business})
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data
        require_location(request.membership, data["location"].pk)

        def handler():
            result = services.post_adjustment(
                request.business, request.user, data["location"], data["lines"], data["reason"]
            )
            return 201, {
                "document_id": result["document_id"],
                "location": data["location"].pk,
                "movements": _movement_summary(result["posted"]),
            }

        return run_idempotent(
            request, business=request.business, action="stock_adjust", handler=handler
        )
