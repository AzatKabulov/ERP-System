from django.urls import path

from .views import OperationStatusView

urlpatterns = [
    path(
        "businesses/<uuid:business_id>/operations/<slug:action>/<uuid:key>/",
        OperationStatusView.as_view(),
        name="operation-status",
    ),
]
