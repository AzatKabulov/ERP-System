from django.urls import path

from . import views

B = "businesses/<uuid:business_id>/stock/"

urlpatterns = [
    path(B, views.StockListView.as_view(), name="stock-list"),
    path(f"{B}movements/", views.StockMovementListView.as_view(), name="stock-movements"),
    path(f"{B}opening/", views.OpeningStockView.as_view(), name="stock-opening"),
    path(f"{B}adjustments/", views.AdjustmentView.as_view(), name="stock-adjustments"),
]
