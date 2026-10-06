from django.urls import path

from . import views

urlpatterns = [
    path("me/", views.MeView.as_view(), name="me"),
    path("businesses/<uuid:business_id>/", views.BusinessDetailView.as_view(), name="business"),
    path(
        "businesses/<uuid:business_id>/locations/",
        views.LocationListCreateView.as_view(),
        name="location-list",
    ),
    path(
        "businesses/<uuid:business_id>/locations/<uuid:location_id>/",
        views.LocationDetailView.as_view(),
        name="location-detail",
    ),
    path(
        "businesses/<uuid:business_id>/staff/",
        views.StaffListCreateView.as_view(),
        name="staff-list",
    ),
    path(
        "businesses/<uuid:business_id>/staff/<uuid:staff_id>/",
        views.StaffDetailView.as_view(),
        name="staff-detail",
    ),
]
