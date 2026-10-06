"""Business and location access. The business always comes from the URL and is checked
against the caller's membership; a business ID in a request body never grants access."""

from rest_framework import exceptions
from rest_framework.permissions import BasePermission, IsAuthenticated
from rest_framework.views import APIView

from apps.common.errors import ApiError

from .models import Membership
from .permissions import has_permission


class HasBusinessPermission(BasePermission):
    """Resolves request.membership / request.business and checks the view's permission.

    * not a member (or business inactive)  -> 404, so another business's existence is not revealed
    * member without the permission         -> 403
    * view declares no permission           -> 403 (fail closed)
    """

    def has_permission(self, request, view) -> bool:
        membership = (
            Membership.objects.select_related("business", "user")
            .filter(
                user=request.user,
                business_id=view.kwargs.get("business_id"),
                is_active=True,
                business__is_active=True,
            )
            .first()
        )
        if membership is None:
            raise exceptions.NotFound()
        request.membership = membership
        request.business = membership.business
        code = view.required_permission_for(request)
        return bool(code) and has_permission(membership.role, code)


class BusinessScopedMixin:
    """Mix into every view under /api/v1/businesses/<business_id>/ (before the DRF base class).

    Declare `required_permission = "area.action"` or `permission_by_method = {"GET": ...}`."""

    permission_classes = [IsAuthenticated, HasBusinessPermission]
    required_permission: str | None = None
    permission_by_method: dict[str, str] | None = None

    def required_permission_for(self, request) -> str | None:
        if self.permission_by_method is not None:
            return self.permission_by_method.get(request.method)
        return self.required_permission


class BusinessAPIView(BusinessScopedMixin, APIView):
    pass


def restrict_to_locations(queryset, membership: Membership, field: str = "location_id"):
    """Limit a queryset to the locations this member may see."""
    allowed = membership.location_ids()
    return queryset if allowed is None else queryset.filter(**{f"{field}__in": allowed})


def require_location(membership: Membership, location_id) -> None:
    allowed = membership.location_ids()
    if allowed is not None and location_id not in allowed:
        raise ApiError(
            "location_not_permitted", "This location is not available to you", status_code=403
        )
