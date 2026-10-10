from django.urls import path

from . import views

B = "businesses/<uuid:business_id>/"

urlpatterns = [
    path(f"{B}transfers/", views.TransferListCreateView.as_view(), name="transfer-list"),
    path(
        f"{B}transfers/<uuid:transfer_id>/",
        views.TransferDetailView.as_view(),
        name="transfer-detail",
    ),
    path(
        f"{B}transfers/<uuid:transfer_id>/receive/",
        views.TransferReceiveView.as_view(),
        name="transfer-receive",
    ),
    path(
        f"{B}transfers/<uuid:transfer_id>/cancel/",
        views.TransferCancelView.as_view(),
        name="transfer-cancel",
    ),
    path(f"{B}counts/", views.CountListCreateView.as_view(), name="count-list"),
    path(f"{B}counts/<uuid:count_id>/", views.CountDetailView.as_view(), name="count-detail"),
    path(f"{B}counts/<uuid:count_id>/lines/", views.CountLinesView.as_view(), name="count-lines"),
    path(
        f"{B}counts/<uuid:count_id>/submit/", views.CountSubmitView.as_view(), name="count-submit"
    ),
    path(
        f"{B}counts/<uuid:count_id>/approve/",
        views.CountApproveView.as_view(),
        name="count-approve",
    ),
    path(
        f"{B}counts/<uuid:count_id>/cancel/", views.CountCancelView.as_view(), name="count-cancel"
    ),
]
