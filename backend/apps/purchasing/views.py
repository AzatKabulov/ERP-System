from django.shortcuts import get_object_or_404
from rest_framework import generics
from rest_framework.response import Response

from apps.audit import services as audit
from apps.audit.services import run_idempotent
from apps.businesses.access import (
    BusinessAPIView,
    BusinessScopedMixin,
    require_location,
    restrict_to_locations,
)
from apps.businesses.permissions import has_permission

from . import reorder, services
from . import returns as supplier_returns
from .models import PurchaseOrder, Supplier, SupplierReturn
from .serializers import (
    CancelSerializer,
    OrderWriteSerializer,
    PurchaseOrderSerializer,
    PurchaseOrderSummarySerializer,
    ReceiveSerializer,
    ReorderRowSerializer,
    SupplierReturnInputSerializer,
    SupplierReturnSerializer,
    SupplierSerializer,
)


def _context(request) -> dict:
    return {
        "request": request,
        "business": request.business,
        "can_view_cost": has_permission(request.membership.role, "purchasing.cost.view"),
    }


def _orders(request):
    return restrict_to_locations(
        PurchaseOrder.objects.filter(business=request.business)
        .select_related("supplier", "location", "created_by")
        .prefetch_related(
            "lines__product__unit",
            "deliveries__lines__order_line__product__unit",
            "deliveries__lines__return_lines",
            "deliveries__received_by",
        ),
        request.membership,
    )


def _order_response(request, order_id, status=200) -> Response:
    order = get_object_or_404(_orders(request), pk=order_id)
    return Response(PurchaseOrderSerializer(order, context=_context(request)).data, status=status)


# ---- suppliers ----------------------------------------------------------------------------


class SupplierListCreateView(BusinessScopedMixin, generics.GenericAPIView):
    permission_by_method = {"GET": "supplier.view", "POST": "supplier.manage"}

    def get(self, request, business_id):
        qs = Supplier.objects.filter(business=request.business)
        active = request.query_params.get("active", "1")
        if active == "1":
            qs = qs.filter(is_active=True)
        elif active == "0":
            qs = qs.filter(is_active=False)
        for token in request.query_params.get("q", "").casefold().split():
            qs = qs.filter(name__icontains=token)
        page = self.paginate_queryset(qs)
        return self.get_paginated_response(
            SupplierSerializer(page, many=True, context={"business": request.business}).data
        )

    def post(self, request, business_id):
        serializer = SupplierSerializer(data=request.data, context={"business": request.business})
        serializer.is_valid(raise_exception=True)
        supplier = serializer.save(business=request.business)
        audit.record(
            "supplier.created",
            actor=request.user,
            business=request.business,
            obj=supplier,
            metadata={"name": supplier.name},
        )
        return Response(serializer.data, status=201)


class SupplierDetailView(BusinessAPIView):
    permission_by_method = {"GET": "supplier.view", "PATCH": "supplier.manage"}

    def get(self, request, business_id, supplier_id):
        supplier = get_object_or_404(Supplier, pk=supplier_id, business=request.business)
        return Response(SupplierSerializer(supplier, context={"business": request.business}).data)

    def patch(self, request, business_id, supplier_id):
        supplier = get_object_or_404(Supplier, pk=supplier_id, business=request.business)
        serializer = SupplierSerializer(
            supplier, data=request.data, partial=True, context={"business": request.business}
        )
        serializer.is_valid(raise_exception=True)
        serializer.save()
        audit.record(
            "supplier.updated",
            actor=request.user,
            business=request.business,
            obj=supplier,
            metadata={"fields": sorted(request.data.keys())},
        )
        return Response(serializer.data)


# ---- purchase orders ----------------------------------------------------------------------


class OrderListCreateView(BusinessScopedMixin, generics.GenericAPIView):
    permission_by_method = {"GET": "purchasing.view", "POST": "purchasing.manage"}

    def get(self, request, business_id):
        params = request.query_params
        qs = _orders(request)
        if params.get("status"):
            qs = qs.filter(status__in=params["status"].split(","))
        if params.get("supplier"):
            qs = qs.filter(supplier_id=params["supplier"])
        if params.get("location"):
            qs = qs.filter(location_id=params["location"])
        page = self.paginate_queryset(qs)
        return self.get_paginated_response(
            PurchaseOrderSummarySerializer(page, many=True, context=_context(request)).data
        )

    def post(self, request, business_id):
        serializer = OrderWriteSerializer(data=request.data, context={"business": request.business})
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data
        require_location(request.membership, data["location"].pk)
        order = services.create_order(request.business, request.user, data)
        return _order_response(request, order.pk, status=201)


class OrderDetailView(BusinessAPIView):
    permission_by_method = {"GET": "purchasing.view", "PATCH": "purchasing.manage"}

    def get(self, request, business_id, order_id):
        return _order_response(request, order_id)

    def patch(self, request, business_id, order_id):
        serializer = OrderWriteSerializer(
            data=request.data, partial=True, context={"business": request.business}
        )
        serializer.is_valid(raise_exception=True)
        order = get_object_or_404(_orders(request), pk=order_id)
        data = serializer.validated_data
        if "location" in data:
            require_location(request.membership, data["location"].pk)
        services.update_order(request.business, request.user, order.pk, data)
        return _order_response(request, order_id)


class OrderSubmitView(BusinessAPIView):
    required_permission = "purchasing.manage"

    def post(self, request, business_id, order_id):
        get_object_or_404(_orders(request), pk=order_id)
        services.submit_order(request.business, request.user, order_id)
        return _order_response(request, order_id)


class OrderCancelView(BusinessAPIView):
    required_permission = "purchasing.manage"

    def post(self, request, business_id, order_id):
        serializer = CancelSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        get_object_or_404(_orders(request), pk=order_id)
        services.cancel_order(
            request.business, request.user, order_id, serializer.validated_data["reason"]
        )
        return _order_response(request, order_id)


class DeliveryCreateView(BusinessAPIView):
    """Receive goods against an order. Needs an Idempotency-Key: the app keeps the same key
    across a timeout, crash or restart, so a retry can never receive the goods twice."""

    required_permission = "purchasing.receive"

    def post(self, request, business_id, order_id):
        serializer = ReceiveSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        order = get_object_or_404(_orders(request), pk=order_id)
        require_location(request.membership, order.location_id)
        data = serializer.validated_data

        def handler():
            delivery = services.receive(
                request.business, request.user, order_id, data["lines"], data["note"]
            )
            fresh = get_object_or_404(_orders(request), pk=order_id)
            return 201, {
                "delivery": delivery.pk,
                "delivery_number": delivery.number,
                "order": PurchaseOrderSerializer(fresh, context=_context(request)).data,
            }

        return run_idempotent(
            request, business=request.business, action="purchase_receive", handler=handler
        )


# ---- returns to a supplier -----------------------------------------------------------------


def _supplier_returns(request):
    return restrict_to_locations(
        SupplierReturn.objects.filter(business=request.business)
        .select_related("supplier", "location", "created_by", "delivery__order")
        .prefetch_related("lines__product__unit"),
        request.membership,
    )


class SupplierReturnListCreateView(BusinessScopedMixin, generics.GenericAPIView):
    permission_by_method = {"GET": "supplier_return.view", "POST": "supplier_return.create"}

    def get(self, request, business_id):
        params = request.query_params
        qs = _supplier_returns(request)
        if params.get("supplier"):
            qs = qs.filter(supplier_id=params["supplier"])
        if params.get("delivery"):
            qs = qs.filter(delivery_id=params["delivery"])
        if params.get("location"):
            qs = qs.filter(location_id=params["location"])
        page = self.paginate_queryset(qs)
        return self.get_paginated_response(
            SupplierReturnSerializer(page, many=True, context=_context(request)).data
        )

    def post(self, request, business_id):
        serializer = SupplierReturnInputSerializer(
            data=request.data, context={"business": request.business}
        )
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data

        def handler():
            made = supplier_returns.return_to_supplier(
                request.business, request.user, request.membership, data
            )
            fresh = get_object_or_404(_supplier_returns(request), pk=made.pk)
            return 201, SupplierReturnSerializer(fresh, context=_context(request)).data

        return run_idempotent(
            request, business=request.business, action="supplier_return_create", handler=handler
        )


class SupplierReturnDetailView(BusinessAPIView):
    required_permission = "supplier_return.view"

    def get(self, request, business_id, return_id):
        found = get_object_or_404(_supplier_returns(request), pk=return_id)
        return Response(SupplierReturnSerializer(found, context=_context(request)).data)


# ---- what to buy again ---------------------------------------------------------------------


class ReorderSuggestionsView(BusinessAPIView):
    required_permission = "reorder.view"

    def get(self, request, business_id):
        rows = reorder.suggestions(
            request.business, request.membership, request.query_params.get("location")
        )
        context = {"can_view_cost": has_permission(request.membership.role, "purchasing.cost.view")}
        return Response(
            {
                "count": len(rows),
                "results": ReorderRowSerializer(rows, many=True, context=context).data,
            }
        )
