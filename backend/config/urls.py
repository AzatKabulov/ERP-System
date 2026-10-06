from django.contrib import admin
from django.urls import include, path

from apps.common.views import health
from config import env

handler404 = "apps.common.errors.not_found"
handler500 = "apps.common.errors.server_error"

api = [
    path("health/", health, name="health"),
    path("", include("apps.accounts.urls")),
    path("", include("apps.businesses.urls")),
    path("", include("apps.catalog.urls")),
    path("", include("apps.inventory.urls")),
    path("", include("apps.purchasing.urls")),
    path("", include("apps.audit.urls")),
]

urlpatterns = [
    path(env.get("DJANGO_ADMIN_PATH", "admin/"), admin.site.urls),
    path("api/v1/", include(api)),
]

from django.conf import settings  # noqa: E402

if settings.EXPOSE_API_SCHEMA:
    from drf_spectacular.views import SpectacularAPIView

    urlpatterns.append(path("api/v1/schema/", SpectacularAPIView.as_view(), name="schema"))
