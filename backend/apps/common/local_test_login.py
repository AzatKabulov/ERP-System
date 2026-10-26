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

from apps.accounts.services import issue_tokens
from apps.audit import services as audit
from apps.businesses.models import Membership
from apps.common.errors import ApiError
from apps.common.views import health

ROLES = ("owner", "manager", "sales", "warehouse")
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


def _enabled(request):
    from urllib.parse import urlsplit

    return (
        getattr(settings, "LOCAL_TEST_LOGIN_ENABLED", False)
        and settings.DJANGO_ENV == "development"
        and _local(urlsplit("http://" + request.get_host()).hostname)
        and _local(request.META.get("REMOTE_ADDR", ""))
    )


def _members(request):
    if not _enabled(request):
        return Membership.objects.none()
    return Membership.objects.filter(
        business__name=SAMPLE_SHOP,
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
    return response


class LocalTestLogin(APIView):
    authentication_classes = []
    permission_classes = [AllowAny]

    def post(self, request):
        if not _enabled(request):
            raise ApiError("not_found", "Not found", status_code=404)
        role = request.data.get("role")
        if role not in ROLES:
            raise ApiError("validation_error", "Unknown test role")
        members = list(_members(request).filter(role=role, user__username=role)[:2])
        if len(members) != 1:
            raise ApiError("not_found", "Test role unavailable", status_code=404)
        user = members[0].user
        update_last_login(None, user)
        audit.record("auth.local_test_login", actor=user, business=members[0].business)
        return Response(issue_tokens(user))
