from django.urls import path

from . import api
from . import platform_api as platform

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
    path("platform/overview/", platform.OverviewView.as_view(), name="platform-overview"),
    path("platform/clients/", platform.ClientListView.as_view(), name="platform-clients"),
    path(
        "platform/clients/<uuid:client_id>/",
        platform.ClientDetailView.as_view(),
        name="platform-client",
    ),
    path(
        "platform/clients/<uuid:client_id>/notes/",
        platform.ClientNoteView.as_view(),
        name="platform-client-notes",
    ),
    path(
        "platform/clients/<uuid:client_id>/actions/<str:action>/",
        platform.ClientActionView.as_view(),
        name="platform-client-action",
    ),
    path("platform/support/", platform.SupportListView.as_view(), name="platform-support"),
    path(
        "platform/support/<uuid:ticket_id>/",
        platform.SupportDetailView.as_view(),
        name="platform-support-detail",
    ),
    path(
        "platform/support/<uuid:ticket_id>/reply/",
        platform.SupportReplyView.as_view(),
        name="platform-support-reply",
    ),
    path(
        "platform/support/<uuid:ticket_id>/close/",
        platform.SupportCloseView.as_view(),
        name="platform-support-close",
    ),
    path(
        "platform/announcements/",
        platform.AnnouncementListView.as_view(),
        name="platform-announcements",
    ),
    path(
        "platform/announcements/<uuid:announcement_id>/",
        platform.AnnouncementDetailView.as_view(),
        name="platform-announcement",
    ),
    path("platform/plans/", platform.PlanListView.as_view(), name="platform-plans"),
    path(
        "platform/plans/<uuid:plan_id>/",
        platform.PlanDetailView.as_view(),
        name="platform-plan",
    ),
]
