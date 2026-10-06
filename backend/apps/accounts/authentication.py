from rest_framework import exceptions
from rest_framework_simplejwt.authentication import JWTAuthentication


class ERPJWTAuthentication(JWTAuthentication):
    """Rejects access tokens issued before the user's last password change/reset, so a stolen
    token stops working immediately instead of at expiry. (Deactivated users are already
    rejected by the base class.)"""

    def get_user(self, validated_token):
        user = super().get_user(validated_token)
        if validated_token.get("sv") != user.session_version:
            raise exceptions.AuthenticationFailed("Session revoked", code="session_revoked")
        return user
