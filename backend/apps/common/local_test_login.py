"""Password-free role selection for the local sample shop only.

These views are deliberately absent from config.urls and production settings.
"""

from ipaddress import ip_address, ip_network

from django.conf import settings
from django.contrib.auth.models import update_last_login
from rest_framework.decorators import api_view, authentication_classes, permission_classes
from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.accounts.models import User
from apps.accounts.services import issue_tokens
from apps.audit import services as audit
from apps.businesses.models import Membership
from apps.common.errors import ApiError
from apps.common.views import health

ROLES = ("owner", "manager", "sales", "warehouse")
# The platform owner (our own back office): the local operator, no password and no code. Local
# test run only, behind the same checks as the shop roles.
PLATFORM = "platform"
SAMPLE_SHOP = "Sample Auto Parts (test data)"


def _local(address):
    if address == "localhost":
        return True
    try:
        ip = ip_address(address)
        return ip.is_loopback or (
            ip.version == 4 and any(ip in network for network in _PRIVATE_NETWORKS)
        )
    except ValueError:
        return False


_PRIVATE_NETWORKS = tuple(
    ip_network(value) for value in ("10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16")
)


# Headers that a reverse proxy or a tunnel (Caddy, nginx, Cloudflare Tunnel, ngrok) adds. A proxy
# on the same computer connects from 127.0.0.1, so the address check alone would pass for anyone
# on the internet; a request that went through one is never "local".
_PROXY_HEADERS = (
    "HTTP_X_FORWARDED_FOR",
    "HTTP_X_FORWARDED_HOST",
    "HTTP_X_FORWARDED_PROTO",
    "HTTP_FORWARDED",
    "HTTP_X_REAL_IP",
    "HTTP_TRUE_CLIENT_IP",
    "HTTP_CF_CONNECTING_IP",
    "HTTP_CF_RAY",
)


def _direct(request):
    return not any(request.META.get(header) for header in _PROXY_HEADERS)


def _enabled(request):
    from urllib.parse import urlsplit

    if getattr(settings, "PUBLIC_TEST_LOGIN", False):
        return settings.DJANGO_ENV == "development"
    return (
        getattr(settings, "LOCAL_TEST_LOGIN_ENABLED", False)
        and settings.DJANGO_ENV == "development"
        and _direct(request)
        and _local(urlsplit("http://" + request.get_host()).hostname)
        and _local(request.META.get("REMOTE_ADDR", ""))
    )


def _members(request):
    if not _enabled(request):
        return Membership.objects.none()
    shop = {} if getattr(settings, "PUBLIC_TEST_LOGIN", False) else {"business__name": SAMPLE_SHOP}
    return Membership.objects.filter(
        **shop,
        business__is_active=True,
        is_active=True,
        user__is_active=True,
    ).select_related("user")


@api_view(["GET"])
@authentication_classes([])
@permission_classes([AllowAny])
def local_health(request):
    response = health(request._request)
    if response.status_code == 200:
        response.data["test_login_roles"] = [
            role
            for role in ROLES
            if _members(request).filter(role=role, user__username=role).exists()
        ]
        if response.data["test_login_roles"] and _operator(request) is not None:
            response.data["test_login_roles"].append(PLATFORM)
    return response


def _operator(request):
    if not _enabled(request):
        return None
    return User.objects.filter(is_staff=True, is_active=True).order_by("date_joined").first()


class LocalTestLogin(APIView):
    authentication_classes = []
    permission_classes = [AllowAny]

    def post(self, request):
        if not _enabled(request):
            raise ApiError("not_found", "Not found", status_code=404)
        role = request.data.get("role")
        if role == PLATFORM:
            operator = _operator(request)
            if operator is None:
                raise ApiError("not_found", "Test role unavailable", status_code=404)
            update_last_login(None, operator)
            audit.record("auth.local_test_login", actor=operator)
            return Response(issue_tokens(operator))
        if role not in ROLES:
            raise ApiError("validation_error", "Unknown test role")
        members = list(_members(request).filter(role=role, user__username=role)[:2])
        if len(members) != 1:
            raise ApiError("not_found", "Test role unavailable", status_code=404)
        user = members[0].user
        update_last_login(None, user)
        audit.record("auth.local_test_login", actor=user, business=members[0].business)
        return Response(issue_tokens(user))
