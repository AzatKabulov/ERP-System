import logging

from django.contrib.auth import authenticate
from django.contrib.auth.models import update_last_login
from django.core.exceptions import ValidationError as DjangoValidationError
from django.db import transaction
from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from rest_framework.views import APIView
from rest_framework_simplejwt.exceptions import TokenError
from rest_framework_simplejwt.tokens import RefreshToken

from apps.audit import services as audit
from apps.common.errors import ApiError

from . import services
from .models import User
from .serializers import (
    LoginSerializer,
    PasswordChangeSerializer,
    RefreshSerializer,
    ResetConfirmSerializer,
    ResetRequestSerializer,
    UserSerializer,
    password_errors,
)
from .throttles import (
    LoginIdentityThrottle,
    LoginIPThrottle,
    ResetConfirmIPThrottle,
    ResetRequestIdentityThrottle,
    ResetRequestIPThrottle,
)

logger = logging.getLogger(__name__)


class PublicView(APIView):
    authentication_classes: list = []
    permission_classes = [AllowAny]


class LoginView(PublicView):
    throttle_classes = [LoginIdentityThrottle, LoginIPThrottle]

    def post(self, request):
        data = LoginSerializer(data=request.data)
        data.is_valid(raise_exception=True)
        user = authenticate(
            request,
            username=data.validated_data["username"],
            password=data.validated_data["password"],
        )
        if user is None:  # unknown user, wrong password and inactive account look the same
            logger.info("Failed sign-in attempt")
            raise ApiError("invalid_credentials", "Wrong username or password", status_code=401)
        update_last_login(None, user)
        audit.record("auth.login", actor=user)
        return Response({**services.issue_tokens(user), "user": UserSerializer(user).data})


class RefreshView(PublicView):
    """Exchanges a refresh token for a new pair. The old refresh token is blacklisted, so
    presenting it again is rejected; two simultaneous uses cannot both succeed."""

    throttle_classes = [LoginIPThrottle]

    def post(self, request):
        data = RefreshSerializer(data=request.data)
        data.is_valid(raise_exception=True)
        try:
            old = RefreshToken(data.validated_data["refresh"])
        except TokenError as exc:
            raise ApiError("invalid_token", "Refresh token is invalid", status_code=401) from exc
        user = User.objects.filter(pk=old.get("user_id"), is_active=True).first()
        if user is None or old.get("sv") != user.session_version:
            raise ApiError("invalid_token", "Refresh token is invalid", status_code=401)
        with transaction.atomic():
            _, created = old.blacklist()
            if not created:  # another request used this token a moment ago
                raise ApiError("invalid_token", "Refresh token is invalid", status_code=401)
        return Response(services.issue_tokens(user))


class LogoutView(PublicView):
    """Revokes the refresh token. Always answers 204 so it cannot be used to probe tokens."""

    throttle_classes = [LoginIPThrottle]

    def post(self, request):
        data = RefreshSerializer(data=request.data)
        if data.is_valid():
            try:
                RefreshToken(data.validated_data["refresh"]).blacklist()
            except TokenError:
                pass
        return Response(status=204)


class PasswordChangeView(APIView):
    def post(self, request):
        data = PasswordChangeSerializer(data=request.data)
        data.is_valid(raise_exception=True)
        user = request.user
        if not user.check_password(data.validated_data["old_password"]):
            raise ApiError(
                "invalid_old_password",
                "The current password is wrong",
                fields={"old_password": [{"code": "invalid_old_password", "message": "Wrong"}]},
            )
        try:
            services.set_password(user, data.validated_data["new_password"])
        except DjangoValidationError as exc:
            raise password_errors(exc) from exc
        audit.record("auth.password_changed", actor=user)
        # Every session was just revoked; give this device a fresh one.
        return Response(services.issue_tokens(user))


class PasswordResetRequestView(PublicView):
    throttle_classes = [ResetRequestIPThrottle, ResetRequestIdentityThrottle]

    def post(self, request):
        data = ResetRequestSerializer(data=request.data)
        data.is_valid(raise_exception=True)
        user = services.find_user(data.validated_data["identifier"])
        if user is not None:
            services.send_code(user, "reset")
            audit.record("auth.password_reset_requested", actor=user)
        # Same answer whether or not the account exists.
        return Response({"status": "accepted"}, status=202)


class PasswordResetConfirmView(PublicView):
    throttle_classes = [ResetConfirmIPThrottle]

    def post(self, request):
        data = ResetConfirmSerializer(data=request.data)
        data.is_valid(raise_exception=True)
        user = services.find_user(data.validated_data["identifier"])
        invalid = ApiError("invalid_reset_code", "The code is wrong or has expired")
        if user is None:
            raise invalid
        try:
            ok = services.consume_code(
                user, data.validated_data["code"], data.validated_data["new_password"]
            )
        except DjangoValidationError as exc:
            raise password_errors(exc) from exc
        if not ok:
            raise invalid
        audit.record("auth.password_reset_completed", actor=user)
        return Response({"status": "ok"})
