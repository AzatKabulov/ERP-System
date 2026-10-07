from decimal import Decimal

from django.db.models import Sum
from rest_framework import serializers

from apps.businesses.models import Location
from apps.catalog.models import Product
from apps.common.fields import BusinessScopedField

from . import returns
from .models import (
    Customer,
    PaymentMethod,
    ReturnCondition,
    Sale,
    SaleLine,
    SaleReturn,
    SaleReturnLine,
)

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
    # What the seller charges for one unit (TMT). Prices are not fixed: any amount from zero up.
    unit_price = serializers.DecimalField(max_digits=14, decimal_places=2, min_value=Decimal("0"))


class SaleInputSerializer(serializers.Serializer):
    location = BusinessScopedField(queryset=Location.objects.all())
    customer = BusinessScopedField(queryset=Customer.objects.all(), allow_null=True, required=False)
    note = serializers.CharField(max_length=500, allow_blank=True, default="")
    payment_method = serializers.ChoiceField(choices=PaymentMethod.choices, default="cash")
    lines = SaleLineInputSerializer(many=True, allow_empty=False, max_length=100)

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
            "line_total",
            "cost_total",
            "warranty_months",
            "warranty_terms",
            "return_days",
        ]

    def to_representation(self, instance):
        data = super().to_representation(instance)
        returned = getattr(instance, "returned_quantity", None)
        refunded = getattr(instance, "refunded_total", None)
        if returned is None or refunded is None:
            totals = instance.return_lines.aggregate(q=Sum("quantity"), r=Sum("refund_amount"))
            returned, refunded = totals["q"] or Decimal(0), totals["r"] or Decimal(0)
        data["returned_quantity"] = str(returned)
        data["returnable_quantity"] = str(instance.quantity - returned)
        data["refunded_total"] = str(refunded.quantize(CENT))
        if not self.context.get("can_view_cost"):
            data.pop("cost_total", None)
        else:
            data["cost_total"] = str(instance.cost_total.quantize(CENT))
        return data


class SaleSerializer(serializers.ModelSerializer):
    """The full sale. `cost_total` and `profit` are removed on the server for roles without
    `sales.cost.view`."""

    location = serializers.SerializerMethodField()
    cashier = serializers.SerializerMethodField()
    customer = serializers.SerializerMethodField()
    lines = SaleLineSerializer(many=True)
    returns = serializers.SerializerMethodField()

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
            "payment_method",
            "note",
            "lines",
            "returns",
        ]

    def get_returns(self, sale):
        return [
            {
                "id": str(r.pk),
                "number": r.number,
                "created_at": r.created_at,
                "refund_total": str(r.refund_total),
            }
            for r in sorted(sale.returns.all(), key=lambda r: r.number)
        ]

    def get_location(self, sale):
        return {"id": str(sale.location_id), "name": sale.location.name}

    def get_cashier(self, sale):
        return _person(sale.cashier)

    def get_customer(self, sale):
        if sale.customer_id is None:
            return None
        return {"id": str(sale.customer_id), "name": sale.customer_name}

    def to_representation(self, instance):
        data = super().to_representation(instance)
        for line_data, line in zip(data["lines"], instance.lines.all(), strict=True):
            until = returns.return_until(instance.business, instance, line)
            line_data["return_until"] = until.isoformat() if until else None
        if self.context.get("can_view_cost"):
            cost = sum((line.cost_total for line in instance.lines.all()), Decimal(0))
            data["cost_total"] = str(cost.quantize(CENT))
            data["profit"] = str((instance.total - cost).quantize(CENT))
        return data


class SaleSummarySerializer(serializers.ModelSerializer):
    location = serializers.SerializerMethodField()
    cashier = serializers.SerializerMethodField()
    line_count = serializers.SerializerMethodField()

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
            "payment_method",
            "line_count",
        ]

    def get_location(self, sale):
        return {"id": str(sale.location_id), "name": sale.location.name}

    def get_cashier(self, sale):
        return _person(sale.cashier)

    def get_line_count(self, sale):
        return len(sale.lines.all())


# ---- returns -------------------------------------------------------------------------------


class ReturnLineInputSerializer(serializers.Serializer):
    sale_line = serializers.UUIDField()
    quantity = serializers.DecimalField(max_digits=14, decimal_places=3, min_value=Decimal("0.001"))
    condition = serializers.ChoiceField(choices=ReturnCondition.choices, default="sellable")


class ReturnInputSerializer(serializers.Serializer):
    reason = serializers.CharField(max_length=300)
    note = serializers.CharField(max_length=500, allow_blank=True, default="")
    lines = ReturnLineInputSerializer(many=True, allow_empty=False, max_length=100)

    def validate_reason(self, value: str) -> str:
        value = value.strip()
        if not value:
            raise serializers.ValidationError("This field may not be blank.", code="blank")
        return value


class InspectionRowSerializer(serializers.Serializer):
    return_line = serializers.UUIDField()
    outcome = serializers.ChoiceField(choices=["sellable", "damaged"])
    quantity = serializers.DecimalField(max_digits=14, decimal_places=3, min_value=Decimal("0.001"))


class InspectionInputSerializer(serializers.Serializer):
    lines = InspectionRowSerializer(many=True, allow_empty=False, max_length=100)


class ReturnLineSerializer(serializers.ModelSerializer):
    product = serializers.UUIDField(source="product_id")
    sale_line = serializers.UUIDField(source="sale_line_id")

    class Meta:
        model = SaleReturnLine
        fields = [
            "id",
            "sale_line",
            "product",
            "sku",
            "name",
            "unit_symbol",
            "unit_decimals",
            "quantity",
            "condition",
            "refund_amount",
            "cost_total",
        ]

    def to_representation(self, instance):
        data = super().to_representation(instance)
        waiting = Decimal(0)
        if instance.condition == ReturnCondition.INSPECTION:
            decided = sum((i.quantity for i in instance.inspections.all()), Decimal(0))
            waiting = instance.quantity - decided
        data["awaiting_inspection"] = str(waiting)
        if not self.context.get("can_view_cost"):
            data.pop("cost_total", None)
        else:
            data["cost_total"] = str(instance.cost_total.quantize(CENT))
        return data


class ReturnSerializer(serializers.ModelSerializer):
    sale = serializers.SerializerMethodField()
    location = serializers.SerializerMethodField()
    created_by = serializers.SerializerMethodField()
    lines = ReturnLineSerializer(many=True)

    class Meta:
        model = SaleReturn
        fields = [
            "id",
            "number",
            "created_at",
            "sale",
            "location",
            "created_by",
            "reason",
            "note",
            "refund_total",
            "payment_method",
            "lines",
        ]

    def get_sale(self, ret):
        return {"id": str(ret.sale_id), "number": ret.sale.number}

    def get_location(self, ret):
        return {"id": str(ret.location_id), "name": ret.location.name}

    def get_created_by(self, ret):
        return _person(ret.created_by)


class ReturnSummarySerializer(serializers.ModelSerializer):
    sale = serializers.SerializerMethodField()
    location = serializers.SerializerMethodField()
    awaiting_inspection = serializers.SerializerMethodField()

    class Meta:
        model = SaleReturn
        fields = [
            "id",
            "number",
            "created_at",
            "sale",
            "location",
            "reason",
            "refund_total",
            "awaiting_inspection",
        ]

    def get_sale(self, ret):
        return {"id": str(ret.sale_id), "number": ret.sale.number}

    def get_location(self, ret):
        return {"id": str(ret.location_id), "name": ret.location.name}

    def get_awaiting_inspection(self, ret) -> bool:
        for line in ret.lines.all():
            if line.condition == ReturnCondition.INSPECTION:
                decided = sum((i.quantity for i in line.inspections.all()), Decimal(0))
                if line.quantity > decided:
                    return True
        return False
