from decimal import Decimal

from rest_framework import serializers

from apps.businesses.models import Location
from apps.businesses.rates import to_tmt
from apps.common.fields import BusinessScopedField

from .models import Brand, Category, Product, Unit


class _NamedSerializer(serializers.ModelSerializer):
    """Shared by units, categories and brands: names are unique per business, ignoring case."""

    def validate_name(self, value: str) -> str:
        value = value.strip()
        clash = self.Meta.model.objects.filter(
            business=self.context["business"], name__iexact=value
        )
        if self.instance is not None:
            clash = clash.exclude(pk=self.instance.pk)
        if clash.exists():
            raise serializers.ValidationError("This name is already used.", code="name_taken")
        return value


class UnitSerializer(_NamedSerializer):
    symbol = serializers.CharField(max_length=16)
    decimal_places = serializers.IntegerField(min_value=0, max_value=3)

    class Meta:
        model = Unit
        fields = ["id", "name", "symbol", "decimal_places", "is_active"]
        read_only_fields = ["id"]


class CategorySerializer(_NamedSerializer):
    class Meta:
        model = Category
        fields = ["id", "name", "is_active"]
        read_only_fields = ["id"]


class BrandSerializer(_NamedSerializer):
    class Meta:
        model = Brand
        fields = ["id", "name", "is_active"]
        read_only_fields = ["id"]


class RefSerializer(serializers.Serializer):
    id = serializers.UUIDField()
    name = serializers.CharField()


class ProductSerializer(serializers.ModelSerializer):
    """What the app reads. Cost fields are removed here, on the server, for roles that may
    not see them; hiding them in the app would not be enough."""

    category = RefSerializer(allow_null=True)
    brand = RefSerializer(allow_null=True)
    unit = UnitSerializer()
    price = serializers.SerializerMethodField()
    price_tmt = serializers.SerializerMethodField()
    price_rate_missing = serializers.SerializerMethodField()
    barcodes = serializers.SerializerMethodField()

    class Meta:
        model = Product
        fields = [
            "id",
            "sku",
            "name",
            "category",
            "brand",
            "unit",
            "price",
            "price_tmt",
            "price_rate_missing",
            "default_purchase_cost",
            "warranty_months",
            "warranty_terms",
            "return_days",
            "barcodes",
            "is_active",
            "created_at",
            "updated_at",
        ]

    def get_price(self, product):
        return {"amount": str(product.price_amount), "currency": product.price_currency}

    def _tmt(self, product):
        return to_tmt(product.price_amount, product.price_currency, self.context.get("rate"))

    def get_price_tmt(self, product):
        value = self._tmt(product)
        return None if value is None else str(value)

    def get_price_rate_missing(self, product):
        return product.price_currency != "TMT" and self.context.get("rate") is None

    def get_barcodes(self, product):
        return [b.code for b in product.barcodes.all()]

    def to_representation(self, instance):
        data = super().to_representation(instance)
        if not self.context.get("can_view_cost"):
            data.pop("default_purchase_cost", None)
        return data


class ProductWriteSerializer(serializers.Serializer):
    sku = serializers.CharField(max_length=64)
    name = serializers.CharField(max_length=255)
    category = BusinessScopedField(queryset=Category.objects.all(), allow_null=True, required=False)
    brand = BusinessScopedField(queryset=Brand.objects.all(), allow_null=True, required=False)
    unit = BusinessScopedField(queryset=Unit.objects.all())
    price_amount = serializers.DecimalField(max_digits=14, decimal_places=2, min_value=Decimal("0"))
    price_currency = serializers.ChoiceField(choices=Product.PriceCurrency.choices, default="TMT")
    default_purchase_cost = serializers.DecimalField(
        max_digits=14, decimal_places=2, min_value=Decimal("0"), allow_null=True, required=False
    )
    warranty_months = serializers.IntegerField(min_value=0, max_value=120, default=0)
    warranty_terms = serializers.CharField(max_length=2000, allow_blank=True, default="")
    return_days = serializers.IntegerField(
        min_value=0, max_value=3650, allow_null=True, required=False
    )
    barcodes = serializers.ListField(
        child=serializers.CharField(max_length=64, allow_blank=False),
        required=False,
        max_length=20,
    )
    is_active = serializers.BooleanField(required=False)

    def validate_sku(self, value: str) -> str:
        value = value.strip()
        clash = Product.objects.filter(business=self.context["business"], sku__iexact=value)
        instance = self.context.get("instance")
        if instance is not None:
            clash = clash.exclude(pk=instance.pk)
        if clash.exists():
            raise serializers.ValidationError("This SKU is already used.", code="sku_taken")
        return value

    def validate(self, attrs):
        instance = self.context.get("instance")
        for field in ("category", "brand", "unit"):
            ref = attrs.get(field)
            current = getattr(instance, field, None) if instance else None
            if ref is not None and not ref.is_active and ref != current:
                raise serializers.ValidationError(
                    {field: [serializers.ErrorDetail("Inactive reference.", "inactive_reference")]}
                )
        return attrs


class ReorderRowSerializer(serializers.Serializer):
    location = BusinessScopedField(queryset=Location.objects.all())
    minimum = serializers.DecimalField(max_digits=14, decimal_places=3, min_value=Decimal("0"))
    target = serializers.DecimalField(max_digits=14, decimal_places=3, min_value=Decimal("0"))

    def validate(self, attrs):
        if attrs["target"] < attrs["minimum"]:
            raise serializers.ValidationError(
                {
                    "target": [
                        serializers.ErrorDetail("Target below minimum.", "target_below_minimum")
                    ]
                }
            )
        return attrs


class ReorderSettingsSerializer(serializers.Serializer):
    settings = ReorderRowSerializer(many=True, max_length=100)
