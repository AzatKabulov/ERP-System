from django.contrib.auth import password_validation
from django.core.exceptions import ValidationError as DjangoValidationError
from rest_framework import serializers

from apps.accounts.models import USERNAME_VALIDATOR, User, normalize_username
from apps.accounts.serializers import password_errors

from .models import LANGUAGES, Business, Location, Membership, Role


class BusinessSerializer(serializers.ModelSerializer):
    class Meta:
        model = Business
        fields = [
            "id",
            "name",
            "currency",
            "default_language",
            "document_language",
            "timezone",
            "is_active",
            "created_at",
        ]
        read_only_fields = ["id", "currency", "is_active", "created_at"]


class LocationSerializer(serializers.ModelSerializer):
    class Meta:
        model = Location
        fields = ["id", "name", "kind", "is_active"]
        read_only_fields = ["id"]

    def validate_name(self, value: str) -> str:
        value = value.strip()
        clash = Location.objects.filter(business=self.context["business"], name__iexact=value)
        if self.instance is not None:
            clash = clash.exclude(pk=self.instance.pk)
        if clash.exists():
            raise serializers.ValidationError(
                "A location with this name exists.", code="name_taken"
            )
        return value


class StaffUserSerializer(serializers.ModelSerializer):
    class Meta:
        model = User
        fields = ["id", "username", "full_name", "email", "preferred_language", "is_active"]


class StaffSerializer(serializers.ModelSerializer):
    user = StaffUserSerializer(read_only=True)
    locations = serializers.PrimaryKeyRelatedField(many=True, read_only=True)

    class Meta:
        model = Membership
        fields = ["id", "user", "role", "all_locations", "locations", "is_active"]


class _LocationsMixin:
    def validate_locations(self, value):
        business = self.context["business"]
        for location in value:
            if location.business_id != business.pk or not location.is_active:
                raise serializers.ValidationError(
                    "Unknown or inactive location.", code="invalid_location"
                )
        return value

    def check_location_rules(self, role, all_locations, locations):
        if role in (Role.SALES, Role.WAREHOUSE) and not all_locations and not locations:
            raise serializers.ValidationError(
                {
                    "locations": [
                        serializers.ErrorDetail("Pick at least one location.", "locations_required")
                    ]
                }
            )


class StaffCreateSerializer(_LocationsMixin, serializers.Serializer):
    username = serializers.CharField(max_length=64)
    email = serializers.EmailField()
    full_name = serializers.CharField(max_length=200, required=False, allow_blank=True, default="")
    preferred_language = serializers.ChoiceField(choices=LANGUAGES, default="ru")
    role = serializers.ChoiceField(choices=Role.choices)
    all_locations = serializers.BooleanField(default=False)
    locations = serializers.PrimaryKeyRelatedField(
        many=True, queryset=Location.objects.all(), required=False, default=list
    )
    # Optional. Without it the person receives an emailed code to choose their own password.
    password = serializers.CharField(
        max_length=256, trim_whitespace=False, required=False, write_only=True
    )

    def validate_username(self, value):
        value = normalize_username(value)  # accept any capitalisation, store lowercase
        try:
            USERNAME_VALIDATOR(value)
        except DjangoValidationError as exc:
            raise serializers.ValidationError(exc.messages[0], code="invalid_username") from exc
        if User.objects.filter(username=value).exists():
            raise serializers.ValidationError("This username is taken.", code="username_taken")
        return value

    def validate_email(self, value):
        value = value.strip()
        if User.objects.filter(email__iexact=value).exists():
            raise serializers.ValidationError("This email is already used.", code="email_taken")
        return value

    def validate(self, attrs):
        self.check_location_rules(attrs["role"], attrs["all_locations"], attrs["locations"])
        if attrs.get("password"):
            candidate = User(
                username=attrs["username"], email=attrs["email"], full_name=attrs["full_name"]
            )
            try:
                password_validation.validate_password(attrs["password"], candidate)
            except DjangoValidationError as exc:
                raise password_errors(exc, field="password") from exc
        return attrs


class StaffUpdateSerializer(_LocationsMixin, serializers.Serializer):
    role = serializers.ChoiceField(choices=Role.choices, required=False)
    all_locations = serializers.BooleanField(required=False)
    locations = serializers.PrimaryKeyRelatedField(
        many=True, queryset=Location.objects.all(), required=False
    )
    is_active = serializers.BooleanField(required=False)

    def validate(self, attrs):
        member = self.context["membership"]
        self.check_location_rules(
            attrs.get("role", member.role),
            attrs.get("all_locations", member.all_locations),
            attrs["locations"] if "locations" in attrs else list(member.locations.all()),
        )
        return attrs
