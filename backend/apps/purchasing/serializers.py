from decimal import Decimal

from rest_framework import serializers

from apps.businesses.models import Location
from apps.catalog.models import Product
from apps.common.fields import BusinessScopedField
from apps.inventory.serializers import LocationRefSerializer, ProductRefSerializer

from .models import (
    Delivery,
    DeliveryLine,
    PurchaseOrder,
    PurchaseOrderLine,
    Supplier,
    SupplierReturn,
    SupplierReturnLine,
)
from .services import line_total


class SupplierSerializer(serializers.ModelSerializer):
    name = serializers.CharField(max_length=160)

    class Meta:
        model = Supplier
        fields = [
            "id",
            "name",
            "contact_name",
            "phone",
            "email",
            "address",
            "notes",
            "is_active",
            "created_at",
        ]
        read_only_fields = ["id", "created_at"]

    def validate_name(self, value: str) -> str:
        value = value.strip()
        clash = Supplier.objects.filter(business=self.context["business"], name__iexact=value)
        if self.instance is not None:
            clash = clash.exclude(pk=self.instance.pk)
        if clash.exists():
            raise serializers.ValidationError("This name is already used.", code="name_taken")
        return value


class SupplierRefSerializer(serializers.ModelSerializer):
    class Meta:
        model = Supplier
        fields = ["id", "name"]


class OrderLineSerializer(serializers.ModelSerializer):
    product = ProductRefSerializer()
    outstanding = serializers.DecimalField(max_digits=14, decimal_places=3)

    class Meta:
        model = PurchaseOrderLine
        fields = ["id", "product", "quantity", "received_quantity", "outstanding", "unit_cost"]

    def to_representation(self, instance):
        data = super().to_representation(instance)
        if self.context.get("can_view_cost"):
            data["line_total"] = str(line_total(instance.quantity, instance.unit_cost))
        else:
            data.pop("unit_cost", None)
        return data


class DeliveryLineSerializer(serializers.ModelSerializer):
    order_line = serializers.UUIDField(source="order_line_id")
    product = ProductRefSerializer(source="order_line.product")

    class Meta:
        model = DeliveryLine
        fields = ["id", "order_line", "product", "quantity", "unit_cost"]

    def to_representation(self, instance):
        data = super().to_representation(instance)
        returned = sum((r.quantity for r in instance.return_lines.all()), Decimal(0))
        data["returned_quantity"] = str(returned)
        data["returnable_quantity"] = str(instance.quantity - returned)
        if not self.context.get("can_view_cost"):
            data.pop("unit_cost", None)
        return data


class DeliverySerializer(serializers.ModelSerializer):
    lines = DeliveryLineSerializer(many=True)
    received_by = serializers.SerializerMethodField()

    class Meta:
        model = Delivery
        fields = ["id", "number", "received_at", "received_by", "note", "lines"]

    def get_received_by(self, delivery):
        user = delivery.received_by
        return {"id": str(user.pk), "name": user.full_name or user.username}


class PurchaseOrderSerializer(serializers.ModelSerializer):
    """The full order with its lines and deliveries. Costs are removed on the server for
    roles without `purchasing.cost.view` (the warehouse sees quantities only)."""

    supplier = SupplierRefSerializer()
    location = LocationRefSerializer()
    lines = OrderLineSerializer(many=True)
    deliveries = DeliverySerializer(many=True)
    total = serializers.SerializerMethodField()
    created_by = serializers.SerializerMethodField()

    class Meta:
        model = PurchaseOrder
        fields = [
            "id",
            "number",
            "status",
            "supplier",
            "location",
            "expected_date",
            "notes",
            "created_by",
            "created_at",
            "ordered_at",
            "cancelled_at",
            "cancel_reason",
            "lines",
            "deliveries",
            "total",
        ]

    def get_created_by(self, order):
        user = order.created_by
        return {"id": str(user.pk), "name": user.full_name or user.username}

    def get_total(self, order):
        if not self.context.get("can_view_cost"):
            return None
        return str(
            sum(
                (line_total(line.quantity, line.unit_cost) for line in order.lines.all()),
                Decimal(0),
            )
        )

    def to_representation(self, instance):
        data = super().to_representation(instance)
        if not self.context.get("can_view_cost"):
            data.pop("total", None)
        return data


class PurchaseOrderSummarySerializer(serializers.ModelSerializer):
    supplier = SupplierRefSerializer()
    location = LocationRefSerializer()
    line_count = serializers.SerializerMethodField()
    ordered_quantity = serializers.SerializerMethodField()
    received_quantity = serializers.SerializerMethodField()
    total = serializers.SerializerMethodField()

    class Meta:
        model = PurchaseOrder
        fields = [
            "id",
            "number",
            "status",
            "supplier",
            "location",
            "expected_date",
            "created_at",
            "line_count",
            "ordered_quantity",
            "received_quantity",
            "total",
        ]

    def get_line_count(self, order):
        return len(order.lines.all())

    def get_ordered_quantity(self, order):
        return str(sum((line.quantity for line in order.lines.all()), Decimal(0)))

    def get_received_quantity(self, order):
        return str(sum((line.received_quantity for line in order.lines.all()), Decimal(0)))

    def get_total(self, order):
        return str(
            sum(
                (line_total(line.quantity, line.unit_cost) for line in order.lines.all()),
                Decimal(0),
            )
        )

    def to_representation(self, instance):
        data = super().to_representation(instance)
        if not self.context.get("can_view_cost"):
            data.pop("total", None)
        return data


class OrderLineWriteSerializer(serializers.Serializer):
    product = BusinessScopedField(queryset=Product.objects.select_related("unit"))
    quantity = serializers.DecimalField(max_digits=14, decimal_places=3, min_value=Decimal("0.001"))
    unit_cost = serializers.DecimalField(max_digits=14, decimal_places=2, min_value=Decimal("0"))


class OrderWriteSerializer(serializers.Serializer):
    supplier = BusinessScopedField(queryset=Supplier.objects.all())
    location = BusinessScopedField(queryset=Location.objects.all())
    expected_date = serializers.DateField(allow_null=True, required=False)
    notes = serializers.CharField(max_length=2000, allow_blank=True, required=False)
    lines = OrderLineWriteSerializer(many=True, max_length=200, required=False)


class ReceiveLineSerializer(serializers.Serializer):
    order_line = serializers.UUIDField()
    quantity = serializers.DecimalField(max_digits=14, decimal_places=3, min_value=Decimal("0.001"))


class ReceiveSerializer(serializers.Serializer):
    note = serializers.CharField(max_length=500, allow_blank=True, default="")
    lines = ReceiveLineSerializer(many=True, allow_empty=False, max_length=200)


class CancelSerializer(serializers.Serializer):
    reason = serializers.CharField(max_length=500, allow_blank=True, default="")


# ---- returns to a supplier -----------------------------------------------------------------


class SupplierReturnLineInputSerializer(serializers.Serializer):
    delivery_line = serializers.UUIDField()
    quantity = serializers.DecimalField(max_digits=14, decimal_places=3, min_value=Decimal("0.001"))
    condition = serializers.ChoiceField(choices=["sellable", "damaged"], default="sellable")


class SupplierReturnInputSerializer(serializers.Serializer):
    delivery = BusinessScopedField(queryset=Delivery.objects.all())
    reason = serializers.CharField(max_length=300)
    note = serializers.CharField(max_length=500, allow_blank=True, default="")
    lines = SupplierReturnLineInputSerializer(many=True, allow_empty=False, max_length=200)

    def validate_reason(self, value: str) -> str:
        value = value.strip()
        if not value:
            raise serializers.ValidationError("This field may not be blank.", code="blank")
        return value


class SupplierReturnLineSerializer(serializers.ModelSerializer):
    delivery_line = serializers.UUIDField(source="delivery_line_id")
    product = ProductRefSerializer()

    class Meta:
        model = SupplierReturnLine
        fields = ["id", "delivery_line", "product", "quantity", "condition", "unit_cost"]

    def to_representation(self, instance):
        data = super().to_representation(instance)
        if not self.context.get("can_view_cost"):
            data.pop("unit_cost", None)
        return data


class SupplierReturnSerializer(serializers.ModelSerializer):
    supplier = SupplierRefSerializer()
    location = LocationRefSerializer()
    delivery = serializers.SerializerMethodField()
    created_by = serializers.SerializerMethodField()
    lines = SupplierReturnLineSerializer(many=True)

    class Meta:
        model = SupplierReturn
        fields = [
            "id",
            "number",
            "created_at",
            "supplier",
            "location",
            "delivery",
            "created_by",
            "reason",
            "note",
            "credit_total",
            "lines",
        ]

    def get_delivery(self, ret):
        delivery = ret.delivery
        return {
            "id": str(delivery.pk),
            "number": delivery.number,
            "order": str(delivery.order_id),
            "order_number": delivery.order.number,
        }

    def get_created_by(self, ret):
        user = ret.created_by
        return {"id": str(user.pk), "name": user.full_name or user.username}

    def to_representation(self, instance):
        data = super().to_representation(instance)
        if not self.context.get("can_view_cost"):
            data.pop("credit_total", None)
        return data


class ReorderRowSerializer(serializers.Serializer):
    product = serializers.SerializerMethodField()
    location = LocationRefSerializer()
    on_hand = serializers.DecimalField(max_digits=14, decimal_places=3)
    on_order = serializers.DecimalField(max_digits=14, decimal_places=3)
    minimum = serializers.DecimalField(max_digits=14, decimal_places=3)
    target = serializers.DecimalField(max_digits=14, decimal_places=3)
    suggested = serializers.DecimalField(max_digits=14, decimal_places=3)

    def get_product(self, row):
        data = ProductRefSerializer(row["product"]).data
        if self.context.get("can_view_cost"):
            cost = row["product"].default_purchase_cost
            data["default_purchase_cost"] = None if cost is None else str(cost)
        return data
