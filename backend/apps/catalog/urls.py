from django.urls import path

from . import views

B = "businesses/<uuid:business_id>/"

urlpatterns = [
    path(f"{B}products/", views.ProductListCreateView.as_view(), name="product-list"),
    path(
        f"{B}products/<uuid:product_id>/", views.ProductDetailView.as_view(), name="product-detail"
    ),
    path(
        f"{B}products/<uuid:product_id>/reorder-settings/",
        views.ReorderSettingsView.as_view(),
        name="product-reorder",
    ),
    path(f"{B}barcodes/lookup/", views.BarcodeLookupView.as_view(), name="barcode-lookup"),
    path(f"{B}units/", views.UnitListCreateView.as_view(), name="unit-list"),
    path(f"{B}units/<uuid:ref_id>/", views.UnitDetailView.as_view(), name="unit-detail"),
    path(f"{B}categories/", views.CategoryListCreateView.as_view(), name="category-list"),
    path(
        f"{B}categories/<uuid:ref_id>/", views.CategoryDetailView.as_view(), name="category-detail"
    ),
    path(f"{B}brands/", views.BrandListCreateView.as_view(), name="brand-list"),
    path(f"{B}brands/<uuid:ref_id>/", views.BrandDetailView.as_view(), name="brand-detail"),
]
