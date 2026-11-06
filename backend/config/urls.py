from django.contrib import admin
from django.urls import include, path

from apps.billing.console import console_site
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
    path("", include("apps.sales.urls")),
    path("", include("apps.stockops.urls")),
    path("", include("apps.attachments.urls")),
    path("", include("apps.expenses.urls")),
    path("", include("apps.warranties.urls")),
    path("", include("apps.audit.urls")),
    path("", include("apps.reports.urls")),
    path("", include("apps.billing.urls")),
]

urlpatterns = [
    # Our own back office (clients, subscriptions, support): its own address, sign-in with a
    # password and an authenticator code. See apps/billing/console.py.
    path(env.get("DJANGO_CONSOLE_PATH", "console/"), console_site.urls),
    path("api/v1/", include(api)),
]

# Django's stock admin lists every store's sales, customers and stock. It is a development aid
# only: in production it is not mounted at all, so there is no address to attack.
if env.get_bool("DJANGO_ENABLE_DATA_ADMIN", env.get("DJANGO_ENV", "production") == "development"):
    urlpatterns.append(path(env.get("DJANGO_ADMIN_PATH", "admin/"), admin.site.urls))

from django.conf import settings  # noqa: E402

if settings.EXPOSE_API_SCHEMA:
    from drf_spectacular.views import SpectacularAPIView

    urlpatterns.append(path("api/v1/schema/", SpectacularAPIView.as_view(), name="schema"))
