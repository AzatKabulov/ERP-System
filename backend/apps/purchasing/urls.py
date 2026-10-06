from django.urls import path

from . import views

B = "businesses/<uuid:business_id>/"

urlpatterns = [
    path(f"{B}suppliers/", views.SupplierListCreateView.as_view(), name="supplier-list"),
    path(
        f"{B}suppliers/<uuid:supplier_id>/",
        views.SupplierDetailView.as_view(),
        name="supplier-detail",
    ),
    path(f"{B}purchase-orders/", views.OrderListCreateView.as_view(), name="order-list"),
    path(
        f"{B}purchase-orders/<uuid:order_id>/",
        views.OrderDetailView.as_view(),
        name="order-detail",
    ),
    path(
        f"{B}purchase-orders/<uuid:order_id>/submit/",
        views.OrderSubmitView.as_view(),
        name="order-submit",
    ),
    path(
        f"{B}purchase-orders/<uuid:order_id>/cancel/",
        views.OrderCancelView.as_view(),
        name="order-cancel",
    ),
    path(
        f"{B}purchase-orders/<uuid:order_id>/deliveries/",
        views.DeliveryCreateView.as_view(),
        name="order-receive",
    ),
]
