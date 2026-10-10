from django.urls import path

from . import views

B = "businesses/<uuid:business_id>/"

urlpatterns = [
    path(f"{B}warranty-claims/", views.ClaimListCreateView.as_view(), name="warranty-claim-list"),
    path(
        f"{B}warranty-claims/<uuid:claim_id>/",
        views.ClaimDetailView.as_view(),
        name="warranty-claim-detail",
    ),
    path(
        f"{B}warranty-claims/<uuid:claim_id>/notes/",
        views.ClaimNoteView.as_view(),
        name="warranty-claim-note",
    ),
    path(
        f"{B}warranty-claims/<uuid:claim_id>/close/",
        views.ClaimCloseView.as_view(),
        name="warranty-claim-close",
    ),
]
