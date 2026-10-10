from decimal import Decimal

from rest_framework import serializers

from apps.common.refs import person
from apps.sales.models import SaleReturn

from .entitlement import warranty_until
from .models import WarrantyClaim, WarrantyEvent


class OpenClaimSerializer(serializers.Serializer):
    sale_line = serializers.UUIDField()
    quantity = serializers.DecimalField(max_digits=14, decimal_places=3, min_value=Decimal("0.001"))
    problem = serializers.CharField(max_length=1000)
    # Only someone with warranty.override may set this, and then a note is mandatory.
    override = serializers.BooleanField(default=False)
    override_note = serializers.CharField(max_length=1000, allow_blank=True, required=False)


class NoteSerializer(serializers.Serializer):
    note = serializers.CharField(max_length=1000)  # blank is refused


class CloseClaimSerializer(serializers.Serializer):
    outcome = serializers.ChoiceField(choices=WarrantyClaim.Outcome.choices)
    # Becomes the note of the customer return when the outcome is a refund (that note is 500).
    note = serializers.CharField(max_length=500, allow_blank=True, default="")


class EventSerializer(serializers.ModelSerializer):
    actor = serializers.SerializerMethodField()

    class Meta:
        model = WarrantyEvent
        fields = ["id", "kind", "note", "outcome", "created_at", "actor"]

    def get_actor(self, event):
        return person(event.actor)


class ClaimSerializer(serializers.ModelSerializer):
    """A claim. The context carries `business` (for the time zone of the warranty date); the
    detail form adds `events` (`with_events`), and a list passes `return_numbers`, one query for
    the page, so the refund's return can be named without a query per claim."""

    sale = serializers.SerializerMethodField()
    sale_line = serializers.SerializerMethodField()
    product = serializers.SerializerMethodField()
    opened_by = serializers.SerializerMethodField()

    class Meta:
        model = WarrantyClaim
        fields = [
            "id",
            "number",
            "status",
            "outcome",
            "out_of_warranty",
            "sale",
            "sale_line",
            "product",
            "quantity",
            "customer_name",
            "customer_phone",
            "problem",
            "resolution_note",
            "opened_by",
            "opened_at",
            "closed_at",
        ]

    def get_sale(self, claim):
        return {"id": str(claim.sale_id), "number": claim.sale.number}

    def get_sale_line(self, claim):
        line = claim.sale_line
        until = warranty_until(self.context["business"], claim.sale, line)
        return {
            "id": str(line.pk),
            "warranty_months": line.warranty_months,
            "warranty_terms": line.warranty_terms,
            "warranty_until": until.isoformat() if until else None,
            "unit_price": str(line.unit_price),
            "quantity": str(line.quantity),
        }

    def get_product(self, claim):
        return {
            "sku": claim.sku,
            "name": claim.name,
            "unit_symbol": claim.sale_line.unit_symbol,
            "unit_decimals": claim.sale_line.unit_decimals,
        }

    def get_opened_by(self, claim):
        return person(claim.opened_by)

    def _return_number(self, claim) -> int | None:
        numbers = self.context.get("return_numbers")
        if numbers is not None:
            return numbers.get(claim.return_id)
        return (
            SaleReturn.objects.filter(pk=claim.return_id).values_list("number", flat=True).first()
        )

    def to_representation(self, claim):
        data = super().to_representation(claim)
        data["return"] = (
            None
            if claim.return_id is None
            else {"id": str(claim.return_id), "number": self._return_number(claim)}
        )
        if self.context.get("with_events"):
            data["events"] = EventSerializer(claim.events.all(), many=True).data
        return data
