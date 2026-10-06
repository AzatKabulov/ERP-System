"""A tiny test-only command endpoint that exercises run_idempotent()."""

import time

from django.urls import include, path

from apps.audit.services import record, run_idempotent
from apps.businesses.access import BusinessAPIView
from apps.common.errors import ApiError


class DemoCommand(BusinessAPIView):
    required_permission = "operations.view"

    def post(self, request, business_id):
        def handler():
            record(
                "test.side_effect",
                actor=request.user,
                business=request.business,
                metadata={"n": request.data.get("n")},
            )
            if request.data.get("sleep"):
                time.sleep(float(request.data["sleep"]))
            if request.data.get("fail"):
                raise ApiError("boom", "Deliberate failure", status_code=409)
            return 201, {"ok": True, "n": request.data.get("n"), "amount": "12.50"}

        return run_idempotent(request, business=request.business, action="demo", handler=handler)


urlpatterns = [
    path("api/v1/businesses/<uuid:business_id>/demo/", DemoCommand.as_view()),
    path("api/v1/", include("apps.audit.urls")),
]
