from django.urls import path

from .views import AuditActionsView, AuditListView, OperationStatusView

urlpatterns = [
    path("businesses/<uuid:business_id>/audit/", AuditListView.as_view(), name="audit-list"),
    path(
        "businesses/<uuid:business_id>/audit/actions/",
        AuditActionsView.as_view(),
        name="audit-actions",
    ),
    path(
        "businesses/<uuid:business_id>/operations/<slug:action>/<uuid:key>/",
        OperationStatusView.as_view(),
        name="operation-status",
    ),
]
