from django.core.exceptions import ValidationError as DjangoValidationError
from rest_framework import serializers
from rest_framework.exceptions import ErrorDetail

from .models import User


class UserSerializer(serializers.ModelSerializer):
    class Meta:
        model = User
        fields = ["id", "username", "full_name", "email", "preferred_language"]
        read_only_fields = ["id", "username", "email"]


class LoginSerializer(serializers.Serializer):
    username = serializers.CharField(max_length=150)
    password = serializers.CharField(max_length=256, trim_whitespace=False)


class RefreshSerializer(serializers.Serializer):
    refresh = serializers.CharField()


class PasswordChangeSerializer(serializers.Serializer):
    old_password = serializers.CharField(max_length=256, trim_whitespace=False)
    new_password = serializers.CharField(max_length=256, trim_whitespace=False)


class ResetRequestSerializer(serializers.Serializer):
    identifier = serializers.CharField(max_length=254)


class ResetConfirmSerializer(serializers.Serializer):
    identifier = serializers.CharField(max_length=254)
    code = serializers.CharField(max_length=32)
    new_password = serializers.CharField(max_length=256, trim_whitespace=False)


def password_errors(
    exc: DjangoValidationError, field: str = "new_password"
) -> serializers.ValidationError:
    """Keep Django's password-validator codes (e.g. password_too_short) so the app can
    show a translated message for each."""
    details = [
        ErrorDetail(e.message % e.params if e.params else e.message, code=e.code or "invalid")
        for e in exc.error_list
    ]
    return serializers.ValidationError({field: details})
