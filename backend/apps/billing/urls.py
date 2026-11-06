from django.urls import path

from . import api

urlpatterns = [
    path(
        "businesses/<uuid:business_id>/support/",
        api.SupportListCreateView.as_view(),
        name="support-list",
    ),
    path(
        "businesses/<uuid:business_id>/support/<uuid:request_id>/messages/",
        api.SupportReplyView.as_view(),
        name="support-reply",
    ),
]
