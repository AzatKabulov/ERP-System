from decimal import Decimal

from rest_framework import serializers

from apps.businesses.models import Location
from apps.catalog.models import Product
from apps.common.fields import BusinessScopedField
from apps.inventory.serializers import LocationRefSerializer, ProductRefSerializer

from .models import StockCount, StockCountLine, Transfer, TransferLine
from .services import moved_since

QUANTITY = {"max_digits": 14, "decimal_places": 3, "min_value": Decimal("0.001")}


def _person(user) -> dict | None:
    return None if user is None else {"id": str(user.pk), "name": user.full_name or user.username}


# ---- transfers: input -----------------------------------------------------------------------


class TransferLineInputSerializer(serializers.Serializer):
    product = BusinessScopedField(queryset=Product.objects.select_related("unit"))
    quantity = serializers.DecimalField(**QUANTITY)


class TransferInputSerializer(serializers.Serializer):
    from_location = BusinessScopedField(queryset=Location.objects.all())
    to_location = BusinessScopedField(queryset=Location.objects.all())
    note = serializers.CharField(max_length=500, allow_blank=True, default="")
    lines = TransferLineInputSerializer(many=True, allow_empty=False, max_length=100)

    def validate(self, attrs):
        if attrs["from_location"].pk == attrs["to_location"].pk:
            raise serializers.ValidationError(
                {"to_location": "Choose another location."}, code="same_location"
            )
        return attrs


class ReceiveLineInputSerializer(serializers.Serializer):
    line = serializers.UUIDField()
    quantity = serializers.DecimalField(max_digits=14, decimal_places=3, min_value=Decimal("0"))


class ReceiveInputSerializer(serializers.Serializer):
    lines = ReceiveLineInputSerializer(many=True, required=False, max_length=100)
    reason = serializers.CharField(max_length=500, allow_blank=True, default="")


class ReasonInputSerializer(serializers.Serializer):
    reason = serializers.CharField(max_length=500, allow_blank=True, default="")


# ---- transfers: output ----------------------------------------------------------------------


class TransferLineSerializer(serializers.ModelSerializer):
    product = ProductRefSerializer()

    class Meta:
        model = TransferLine
        fields = ["id", "product", "quantity", "received_quantity"]


class TransferSummarySerializer(serializers.ModelSerializer):
    from_location = LocationRefSerializer()
    to_location = LocationRefSerializer()
    line_count = serializers.SerializerMethodField()

    class Meta:
        model = Transfer
        fields = [
            "id",
            "number",
            "status",
            "from_location",
            "to_location",
            "created_at",
            "line_count",
        ]

    def get_line_count(self, transfer):
        return len(transfer.lines.all())


class TransferSerializer(serializers.ModelSerializer):
    from_location = LocationRefSerializer()
    to_location = LocationRefSerializer()
    lines = TransferLineSerializer(many=True)
    created_by = serializers.SerializerMethodField()
    received_by = serializers.SerializerMethodField()
    cancelled_by = serializers.SerializerMethodField()

    class Meta:
        model = Transfer
        fields = [
            "id",
            "number",
            "status",
            "from_location",
            "to_location",
            "note",
            "created_by",
            "created_at",
            "received_by",
            "received_at",
            "discrepancy_reason",
            "cancelled_by",
            "cancelled_at",
            "cancel_reason",
            "lines",
        ]

    def get_created_by(self, transfer):
        return _person(transfer.created_by)

    def get_received_by(self, transfer):
        return _person(transfer.received_by)

    def get_cancelled_by(self, transfer):
        return _person(transfer.cancelled_by)


# ---- counts: input --------------------------------------------------------------------------


class CountStartSerializer(serializers.Serializer):
    location = BusinessScopedField(queryset=Location.objects.all())
    scope = serializers.ChoiceField(choices=StockCount.Scope.choices, default="full")
    products = serializers.ListField(
        child=BusinessScopedField(queryset=Product.objects.select_related("unit")),
        required=False,
        max_length=500,
    )
    note = serializers.CharField(max_length=500, allow_blank=True, default="")


class CountEntryLineSerializer(serializers.Serializer):
    product = BusinessScopedField(queryset=Product.objects.select_related("unit"))
    counted_quantity = serializers.DecimalField(
        max_digits=14, decimal_places=3, min_value=Decimal("0")
    )
    note = serializers.CharField(max_length=300, allow_blank=True, required=False)


class CountEntrySerializer(serializers.Serializer):
    lines = CountEntryLineSerializer(many=True, allow_empty=False, max_length=500)


# ---- counts: output -------------------------------------------------------------------------


class CountSummarySerializer(serializers.ModelSerializer):
    location = LocationRefSerializer()
    line_count = serializers.SerializerMethodField()
    counted_count = serializers.SerializerMethodField()
    difference_count = serializers.SerializerMethodField()

    class Meta:
        model = StockCount
        fields = [
            "id",
            "number",
            "status",
            "scope",
            "location",
            "created_at",
            "line_count",
            "counted_count",
            "difference_count",
        ]

    def get_line_count(self, count):
        return len(count.lines.all())

    def get_counted_count(self, count):
        return sum(1 for line in count.lines.all() if line.counted_quantity is not None)

    def get_difference_count(self, count):
        return sum(
            1
            for line in count.lines.all()
            if line.counted_quantity is not None and line.counted_quantity != line.baseline_quantity
        )


class CountLineSerializer(serializers.ModelSerializer):
    product = ProductRefSerializer()

    class Meta:
        model = StockCountLine
        fields = ["id", "product", "baseline_quantity", "counted_quantity", "note"]


class CountSerializer(serializers.ModelSerializer):
    """`variance` is counted - baseline; `moved_since_start` says the product's sellable stock
    changed after the count began (a sale or receipt), so the approver can look twice."""

    location = LocationRefSerializer()
    lines = CountLineSerializer(many=True)
    created_by = serializers.SerializerMethodField()
    submitted_by = serializers.SerializerMethodField()
    decided_by = serializers.SerializerMethodField()

    class Meta:
        model = StockCount
        fields = [
            "id",
            "number",
            "status",
            "scope",
            "location",
            "note",
            "created_by",
            "created_at",
            "started_at",
            "submitted_by",
            "submitted_at",
            "decided_by",
            "decided_at",
            "decision_reason",
            "lines",
        ]

    def get_created_by(self, count):
        return _person(count.created_by)

    def get_submitted_by(self, count):
        return _person(count.submitted_by)

    def get_decided_by(self, count):
        return _person(count.decided_by)

    def to_representation(self, instance):
        data = super().to_representation(instance)
        moved = moved_since(
            instance.business, instance.location, instance.started_at, exclude_document=instance.pk
        )
        by_id = {str(line.pk): line for line in instance.lines.all()}
        for row in data["lines"]:
            line = by_id[row["id"]]
            counted = line.counted_quantity
            row["variance"] = None if counted is None else str(counted - line.baseline_quantity)
            row["moved_since_start"] = bool(moved.get(line.product_id))
        return data
