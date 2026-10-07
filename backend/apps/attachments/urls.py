from django.urls import path

from . import views

B = "businesses/<uuid:business_id>/"

urlpatterns = [
    path(f"{B}attachments/", views.AttachmentCreateView.as_view(), name="attachment-create"),
    path(
        f"{B}attachments/<uuid:attachment_id>/",
        views.AttachmentDetailView.as_view(),
        name="attachment-detail",
    ),
]
