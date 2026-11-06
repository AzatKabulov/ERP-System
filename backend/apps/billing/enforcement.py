"""The one place where a lapsed subscription changes what the API does. Called from
HasBusinessPermission, after the person is known to belong to the business."""

from rest_framework.permissions import SAFE_METHODS

from apps.common.errors import ApiError

from .status import READ_ONLY, SUSPENDED, status_of


def check_subscription(request, view, business) -> None:
    """Suspended: nothing works (HTTP 402 subscription_suspended). Past the grace days: looking
    and exporting work, anything that changes data is refused (402 subscription_expired).
    A view marked `subscription_exempt` always works, so a store can still write to us and see
    its own subscription."""
    if getattr(view, "subscription_exempt", False):
        return
    state = status_of(business).state
    if state == SUSPENDED:
        raise ApiError("subscription_suspended", "This subscription is suspended", status_code=402)
    if state == READ_ONLY and request.method not in SAFE_METHODS:
        raise ApiError(
            "subscription_expired",
            "The subscription has ended: the data can be viewed but not changed",
            status_code=402,
        )
