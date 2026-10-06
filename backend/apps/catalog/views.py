from django.shortcuts import get_object_or_404
from rest_framework import generics
from rest_framework.response import Response

from apps.audit import services as audit
from apps.businesses.access import (
    BusinessAPIView,
    BusinessScopedMixin,
    restrict_to_locations,
)
from apps.businesses.permissions import has_permission
from apps.businesses.rates import current_rate
from apps.common.errors import ApiError

from . import services
from .models import Barcode, Brand, Category, Product, ReorderSetting, Unit
from .serializers import (
    BrandSerializer,
    CategorySerializer,
    ProductSerializer,
    ProductWriteSerializer,
    ReorderSettingsSerializer,
    UnitSerializer,
)


def _product_context(request):
    return {
        "request": request,
        "business": request.business,
        "rate": current_rate(request.business),
        "can_view_cost": has_permission(request.membership.role, "catalog.cost.view"),
    }


def _products(business):
    return (
        Product.objects.filter(business=business)
        .select_related("category", "brand", "unit")
        .prefetch_related("barcodes")
    )


class ProductListCreateView(BusinessScopedMixin, generics.GenericAPIView):
    permission_by_method = {"GET": "catalog.view", "POST": "catalog.manage"}

    def get_serializer_class(self):
        return ProductWriteSerializer if self.request.method == "POST" else ProductSerializer

    def get_queryset(self):
        params = self.request.query_params
        qs = _products(self.request.business)
        active = params.get("active", "1")
        if active == "1":
            qs = qs.filter(is_active=True)
        elif active == "0":
            qs = qs.filter(is_active=False)
        if params.get("category"):
            qs = qs.filter(category_id=params["category"])
        if params.get("brand"):
            qs = qs.filter(brand_id=params["brand"])
        for token in params.get("q", "").casefold().split():
            qs = qs.filter(search_key__contains=token)
        return qs

    def get(self, request, business_id):
        page = self.paginate_queryset(self.get_queryset())
        serializer = ProductSerializer(page, many=True, context=_product_context(request))
        return self.get_paginated_response(serializer.data)

    def post(self, request, business_id):
        write = ProductWriteSerializer(data=request.data, context={"business": request.business})
        write.is_valid(raise_exception=True)
        product = services.create_product(request.business, request.user, write.validated_data)
        product = _products(request.business).get(pk=product.pk)
        return Response(
            ProductSerializer(product, context=_product_context(request)).data, status=201
        )


class ProductDetailView(BusinessAPIView):
    permission_by_method = {"GET": "catalog.view", "PATCH": "catalog.manage"}

    def _product(self, request, product_id):
        return get_object_or_404(_products(request.business), pk=product_id)

    def get(self, request, business_id, product_id):
        product = self._product(request, product_id)
        return Response(ProductSerializer(product, context=_product_context(request)).data)

    def patch(self, request, business_id, product_id):
        product = self._product(request, product_id)
        write = ProductWriteSerializer(
            data=request.data,
            partial=True,
            context={"business": request.business, "instance": product},
        )
        write.is_valid(raise_exception=True)
        services.update_product(request.business, request.user, product, write.validated_data)
        product = self._product(request, product_id)
        return Response(ProductSerializer(product, context=_product_context(request)).data)


class BarcodeLookupView(BusinessAPIView):
    """Read-only: finds the active product with this barcode. A scan never changes anything;
    the screen that asked decides what to do with the product."""

    required_permission = "catalog.view"

    def get(self, request, business_id):
        code = services.normalize_code(request.query_params.get("code", ""))
        barcode = (
            Barcode.objects.filter(business=request.business, code=code, product__is_active=True)
            .select_related("product")
            .first()
            if code
            else None
        )
        if barcode is None:
            raise ApiError(
                "barcode_not_found", "No active product has this barcode", status_code=404
            )
        product = _products(request.business).get(pk=barcode.product_id)
        return Response(ProductSerializer(product, context=_product_context(request)).data)


class ReorderSettingsView(BusinessAPIView):
    permission_by_method = {"GET": "catalog.view", "PUT": "catalog.manage"}

    def _rows(self, request, product):
        qs = restrict_to_locations(
            ReorderSetting.objects.filter(product=product).select_related("location"),
            request.membership,
        )
        return [
            {
                "location": str(r.location_id),
                "location_name": r.location.name,
                "minimum": str(r.minimum),
                "target": str(r.target),
            }
            for r in qs.order_by("location__name")
        ]

    def get(self, request, business_id, product_id):
        product = get_object_or_404(Product, pk=product_id, business=request.business)
        return Response({"settings": self._rows(request, product)})

    def put(self, request, business_id, product_id):
        product = get_object_or_404(
            Product.objects.select_related("unit"), pk=product_id, business=request.business
        )
        serializer = ReorderSettingsSerializer(
            data=request.data, context={"business": request.business}
        )
        serializer.is_valid(raise_exception=True)
        services.replace_reorder_settings(
            request.business, request.user, product, serializer.validated_data["settings"]
        )
        return Response({"settings": self._rows(request, product)})


# ---- units, categories, brands -------------------------------------------------------------


class _ReferenceListCreate(BusinessScopedMixin, generics.ListCreateAPIView):
    model = None
    permission_by_method = {"GET": "catalog.view", "POST": "catalog.manage"}
    audit_name = ""

    def get_serializer_context(self):
        return {**super().get_serializer_context(), "business": self.request.business}

    def get_queryset(self):
        qs = self.model.objects.filter(business=self.request.business)
        if self.request.query_params.get("active", "1") == "1":
            qs = qs.filter(is_active=True)
        return qs

    def perform_create(self, serializer):
        obj = serializer.save(business=self.request.business)
        audit.record(
            f"{self.audit_name}.created",
            actor=self.request.user,
            business=self.request.business,
            obj=obj,
            metadata={"name": obj.name},
        )


class _ReferenceDetail(BusinessScopedMixin, generics.RetrieveUpdateAPIView):
    model = None
    permission_by_method = {"GET": "catalog.view", "PATCH": "catalog.manage"}
    http_method_names = ["get", "patch", "head", "options"]
    lookup_url_kwarg = "ref_id"
    audit_name = ""

    def get_serializer_context(self):
        return {**super().get_serializer_context(), "business": self.request.business}

    def get_queryset(self):
        return self.model.objects.filter(business=self.request.business)

    def perform_update(self, serializer):
        obj = serializer.save()
        self.after_update(obj)
        audit.record(
            f"{self.audit_name}.updated",
            actor=self.request.user,
            business=self.request.business,
            obj=obj,
            metadata=serializer.validated_data,
        )

    def after_update(self, obj):
        pass


class UnitListCreateView(_ReferenceListCreate):
    model, serializer_class, audit_name = Unit, UnitSerializer, "unit"


class UnitDetailView(_ReferenceDetail):
    model, serializer_class, audit_name = Unit, UnitSerializer, "unit"

    def perform_update(self, serializer):
        # Changing the precision after products use the unit could invalidate stock quantities.
        new_places = serializer.validated_data.get("decimal_places")
        unit = serializer.instance
        if new_places is not None and new_places != unit.decimal_places and unit.products.exists():
            raise ApiError(
                "unit_in_use",
                "The precision cannot change while products use this unit",
                status_code=409,
            )
        super().perform_update(serializer)


class CategoryListCreateView(_ReferenceListCreate):
    model, serializer_class, audit_name = Category, CategorySerializer, "category"


class CategoryDetailView(_ReferenceDetail):
    model, serializer_class, audit_name = Category, CategorySerializer, "category"

    def after_update(self, obj):
        services.rename_reference(obj, obj.name)  # keep product search keys in step


class BrandListCreateView(_ReferenceListCreate):
    model, serializer_class, audit_name = Brand, BrandSerializer, "brand"


class BrandDetailView(_ReferenceDetail):
    model, serializer_class, audit_name = Brand, BrandSerializer, "brand"

    def after_update(self, obj):
        services.rename_reference(obj, obj.name)
