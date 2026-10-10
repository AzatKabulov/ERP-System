from decimal import Decimal

from rest_framework import serializers

from apps.attachments.models import Attachment
from apps.attachments.serializers import AttachmentRefSerializer
from apps.businesses.models import Location
from apps.common.fields import BusinessScopedField
from apps.common.refs import person

from .models import Expense, ExpenseCategory


class ExpenseCategorySerializer(serializers.ModelSerializer):
    """Names are unique per business, ignoring case."""

    name = serializers.CharField(max_length=120)

    class Meta:
        model = ExpenseCategory
        fields = ["id", "name", "is_active"]
        read_only_fields = ["id"]

    def validate_name(self, value: str) -> str:
        clash = ExpenseCategory.objects.filter(
            business=self.context["business"], name__iexact=value.strip()
        )
        if self.instance is not None:
            clash = clash.exclude(pk=self.instance.pk)
        if clash.exists():
            raise serializers.ValidationError("This name is already used.", code="name_taken")
        return value.strip()


class ExpenseWriteSerializer(serializers.Serializer):
    category = BusinessScopedField(queryset=ExpenseCategory.objects.all())
    location = BusinessScopedField(queryset=Location.objects.all())
    amount = serializers.DecimalField(max_digits=14, decimal_places=2, min_value=Decimal("0.01"))
    spent_on = serializers.DateField()
    description = serializers.CharField(max_length=500, allow_blank=True, default="")
    attachment = BusinessScopedField(
        queryset=Attachment.objects.all(), allow_null=True, required=False
    )

    def validate_spent_on(self, value):
        if value > self.context["business"].local_today():
            raise serializers.ValidationError("The date is in the future.", code="future_date")
        return value

    def validate(self, attrs):
        instance = self.context.get("instance")
        for field in ("category", "location"):
            ref = attrs.get(field)
            current = getattr(instance, field, None) if instance else None
            if ref is not None and not ref.is_active and ref != current:
                raise serializers.ValidationError(
                    {field: [serializers.ErrorDetail("Inactive reference.", "inactive_reference")]}
                )
        return attrs


class VoidSerializer(serializers.Serializer):
    reason = serializers.CharField(max_length=500)  # blank is refused: a reason is mandatory


class ExpenseSerializer(serializers.ModelSerializer):
    category = serializers.SerializerMethodField()
    location = serializers.SerializerMethodField()
    attachment = AttachmentRefSerializer(allow_null=True)
    created_by = serializers.SerializerMethodField()
    voided = serializers.SerializerMethodField()

    class Meta:
        model = Expense
        fields = [
            "id",
            "category",
            "location",
            "amount",
            "spent_on",
            "description",
            "attachment",
            "created_by",
            "created_at",
            "voided",
            "void_reason",
        ]

    def get_category(self, expense):
        return {"id": str(expense.category_id), "name": expense.category.name}

    def get_location(self, expense):
        return {"id": str(expense.location_id), "name": expense.location.name}

    def get_created_by(self, expense):
        return person(expense.created_by)

    def get_voided(self, expense) -> bool:
        return expense.is_voided
