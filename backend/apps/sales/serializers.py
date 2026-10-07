from decimal import Decimal

from rest_framework import serializers

from apps.businesses.models import Location
from apps.catalog.models import Product
from apps.common.fields import BusinessScopedField

from .models import Customer, PaymentMethod, Sale, SaleLine, SalePayment

CENT = Decimal("0.01")


class CustomerSerializer(serializers.ModelSerializer):
    name = serializers.CharField(max_length=200)
    phone = serializers.CharField(max_length=60, allow_blank=True, required=False)
    notes = serializers.CharField(max_length=2000, allow_blank=True, required=False)

    class Meta:
        model = Customer
        fields = ["id", "name", "phone", "notes", "is_active", "created_at"]
        read_only_fields = ["id", "created_at"]

    def validate_name(self, value: str) -> str:
        value = value.strip()
        if not value:
            raise serializers.ValidationError("This field may not be blank.", code="blank")
        return value


# ---- input ---------------------------------------------------------------------------------


class SaleLineInputSerializer(serializers.Serializer):
    product = BusinessScopedField(queryset=Product.objects.select_related("unit"))
    quantity = serializers.DecimalField(max_digits=14, decimal_places=3, min_value=Decimal("0.001"))
    discount = serializers.DecimalField(
        max_digits=14, decimal_places=2, min_value=Decimal("0"), default=Decimal("0")
    )


class PaymentInputSerializer(serializers.Serializer):
    method = serializers.ChoiceField(choices=PaymentMethod.choices)
    amount = serializers.DecimalField(max_digits=14, decimal_places=2, min_value=CENT)


class SaleInputSerializer(serializers.Serializer):
    location = BusinessScopedField(queryset=Location.objects.all())
    customer = BusinessScopedField(queryset=Customer.objects.all(), allow_null=True, required=False)
    note = serializers.CharField(max_length=500, allow_blank=True, default="")
    # What the cashier saw. If prices moved meanwhile the sale is refused (price_changed).
    expected_total = serializers.DecimalField(
        max_digits=14, decimal_places=2, min_value=Decimal("0"), required=False
    )
    lines = SaleLineInputSerializer(many=True, allow_empty=False, max_length=100)
    payments = PaymentInputSerializer(many=True, required=False, default=list, max_length=10)

    def validate_customer(self, customer):
        if customer is not None and not customer.is_active:
            raise serializers.ValidationError("Inactive customer.", code="inactive_reference")
        return customer


# ---- output --------------------------------------------------------------------------------


def _person(user) -> dict:
    return {"id": str(user.pk), "name": user.full_name or user.username}


class SaleLineSerializer(serializers.ModelSerializer):
    product = serializers.UUIDField(source="product_id")

    class Meta:
        model = SaleLine
        fields = [
            "id",
            "product",
            "sku",
            "name",
            "unit_symbol",
            "unit_decimals",
            "quantity",
            "price_amount",
            "price_currency",
            "unit_price",
            "gross",
            "discount",
            "line_total",
            "cost_total",
            "warranty_months",
            "warranty_terms",
        ]

    def to_representation(self, instance):
        data = super().to_representation(instance)
        if not self.context.get("can_view_cost"):
            data.pop("cost_total", None)
        else:
            data["cost_total"] = str(instance.cost_total.quantize(CENT))
        return data


class SalePaymentSerializer(serializers.ModelSerializer):
    class Meta:
        model = SalePayment
        fields = ["method", "amount"]


def _paid(sale: Sale) -> Decimal:
    return sum((p.amount for p in sale.payments.all()), Decimal(0))


def _discount(sale: Sale) -> Decimal:
    return sum((line.discount for line in sale.lines.all()), Decimal(0))


class SaleSerializer(serializers.ModelSerializer):
    """The full sale. `cost_total` and `profit` are removed on the server for roles without
    `sales.cost.view`."""

    location = serializers.SerializerMethodField()
    cashier = serializers.SerializerMethodField()
    customer = serializers.SerializerMethodField()
    lines = SaleLineSerializer(many=True)
    payments = SalePaymentSerializer(many=True)
    paid = serializers.SerializerMethodField()
    discount_total = serializers.SerializerMethodField()

    class Meta:
        model = Sale
        fields = [
            "id",
            "number",
            "created_at",
            "location",
            "cashier",
            "customer",
            "customer_name",
            "customer_phone",
            "total",
            "discount_total",
            "paid",
            "change_given",
            "usd_rate",
            "note",
            "lines",
            "payments",
        ]

    def get_location(self, sale):
        return {"id": str(sale.location_id), "name": sale.location.name}

    def get_cashier(self, sale):
        return _person(sale.cashier)

    def get_customer(self, sale):
        if sale.customer_id is None:
            return None
        return {"id": str(sale.customer_id), "name": sale.customer_name}

    def get_paid(self, sale):
        return str(_paid(sale))

    def get_discount_total(self, sale):
        return str(_discount(sale))

    def to_representation(self, instance):
        data = super().to_representation(instance)
        if self.context.get("can_view_cost"):
            cost = sum((line.cost_total for line in instance.lines.all()), Decimal(0))
            data["cost_total"] = str(cost.quantize(CENT))
            data["profit"] = str((instance.total - cost).quantize(CENT))
        return data


class SaleSummarySerializer(serializers.ModelSerializer):
    location = serializers.SerializerMethodField()
    cashier = serializers.SerializerMethodField()
    line_count = serializers.SerializerMethodField()
    discount_total = serializers.SerializerMethodField()
    methods = serializers.SerializerMethodField()

    class Meta:
        model = Sale
        fields = [
            "id",
            "number",
            "created_at",
            "location",
            "cashier",
            "customer_name",
            "total",
            "discount_total",
            "line_count",
            "methods",
        ]

    def get_location(self, sale):
        return {"id": str(sale.location_id), "name": sale.location.name}

    def get_cashier(self, sale):
        return _person(sale.cashier)

    def get_line_count(self, sale):
        return len(sale.lines.all())

    def get_discount_total(self, sale):
        return str(_discount(sale))

    def get_methods(self, sale):
        return sorted({p.method for p in sale.payments.all()})
