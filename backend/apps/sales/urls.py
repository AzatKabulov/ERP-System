from django.urls import path

from . import views

B = "businesses/<uuid:business_id>/"

urlpatterns = [
    path(f"{B}customers/", views.CustomerListCreateView.as_view(), name="customer-list"),
    path(
        f"{B}customers/<uuid:customer_id>/",
        views.CustomerDetailView.as_view(),
        name="customer-detail",
    ),
    path(f"{B}sales/", views.SaleListCreateView.as_view(), name="sale-list"),
    path(f"{B}sales/<uuid:sale_id>/", views.SaleDetailView.as_view(), name="sale-detail"),
    path(
        f"{B}sales/<uuid:sale_id>/document/", views.SaleDocumentView.as_view(), name="sale-document"
    ),
    path(
        f"{B}sales/<uuid:sale_id>/returns/",
        views.SaleReturnCreateView.as_view(),
        name="sale-return-create",
    ),
    path(f"{B}returns/", views.ReturnListView.as_view(), name="return-list"),
    path(f"{B}returns/<uuid:return_id>/", views.ReturnDetailView.as_view(), name="return-detail"),
    path(
        f"{B}returns/<uuid:return_id>/inspections/",
        views.ReturnInspectView.as_view(),
        name="return-inspect",
    ),
]
