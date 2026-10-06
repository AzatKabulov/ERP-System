from decimal import Decimal

from rest_framework import serializers

from apps.businesses.models import Location
from apps.catalog.models import Product
from apps.catalog.serializers import UnitSerializer
from apps.common.fields import BusinessScopedField

from .models import Condition, StockBalance, StockMovement

QUANTITY = {"max_digits": 14, "decimal_places": 3, "min_value": Decimal("0.001")}
COST = {"max_digits": 14, "decimal_places": 2, "min_value": Decimal("0")}


class ProductRefSerializer(serializers.ModelSerializer):
    unit = UnitSerializer()

    class Meta:
        model = Product
        fields = ["id", "sku", "name", "unit"]


class LocationRefSerializer(serializers.ModelSerializer):
    class Meta:
        model = Location
        fields = ["id", "name"]


class StockBalanceSerializer(serializers.ModelSerializer):
    """`value` and `average_cost` are added by the view only for roles that may see costs."""

    product = ProductRefSerializer()
    location = LocationRefSerializer()

    class Meta:
        model = StockBalance
        fields = ["id", "product", "location", "condition", "quantity", "updated_at"]


class StockMovementSerializer(serializers.ModelSerializer):
    product = ProductRefSerializer()
    location = LocationRefSerializer()
    actor = serializers.SerializerMethodField()

    class Meta:
        model = StockMovement
        fields = [
            "id",
            "created_at",
            "movement_type",
            "product",
            "location",
            "condition",
            "quantity",
            "unit_cost",
            "document_type",
            "document_id",
            "reason",
            "actor",
        ]

    def get_actor(self, movement):
        user = movement.actor
        return {"id": str(user.pk), "name": user.full_name or user.username}

    def to_representation(self, instance):
        data = super().to_representation(instance)
        if not self.context.get("can_view_cost"):
            data.pop("unit_cost", None)
        return data


class OpeningLineSerializer(serializers.Serializer):
    product = BusinessScopedField(queryset=Product.objects.select_related("unit"))
    quantity = serializers.DecimalField(**QUANTITY)
    unit_cost = serializers.DecimalField(**COST)


class OpeningSerializer(serializers.Serializer):
    location = BusinessScopedField(queryset=Location.objects.all())
    note = serializers.CharField(max_length=500, allow_blank=True, default="")
    lines = OpeningLineSerializer(many=True, allow_empty=False, max_length=200)


class AdjustmentLineSerializer(serializers.Serializer):
    product = BusinessScopedField(queryset=Product.objects.select_related("unit"))
    direction = serializers.ChoiceField(choices=["in", "out"])
    quantity = serializers.DecimalField(**QUANTITY)
    unit_cost = serializers.DecimalField(allow_null=True, required=False, **COST)
    condition = serializers.ChoiceField(
        choices=[Condition.SELLABLE, Condition.DAMAGED, Condition.INSPECTION],
        default=Condition.SELLABLE,
    )

    def validate(self, attrs):
        if attrs["direction"] == "in" and attrs.get("unit_cost") is None:
            raise serializers.ValidationError(
                {"unit_cost": [serializers.ErrorDetail("Required for an increase.", "required")]}
            )
        return attrs


class AdjustmentSerializer(serializers.Serializer):
    location = BusinessScopedField(queryset=Location.objects.all())
    reason = serializers.CharField(max_length=500, allow_blank=False, trim_whitespace=True)
    lines = AdjustmentLineSerializer(many=True, allow_empty=False, max_length=200)
