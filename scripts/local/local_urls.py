"""The API's own URLs plus the web app, the install page and the Android file (what Caddy does
in the Docker setup). For the local test run only."""

import os
from pathlib import Path

from django.urls import re_path
from django.views.static import serve

from config.urls import handler404, handler500  # noqa: F401
from config.urls import urlpatterns as api_urlpatterns

WEB = Path(os.environ.get("ERP_LOCAL_WEB_ROOT", "web"))
INSTALL_PAGE = Path(os.environ.get("ERP_LOCAL_INSTALL_PAGE", "install"))
DOWNLOADS = Path(os.environ.get("ERP_LOCAL_DOWNLOADS", "downloads"))


def _site(root: Path, *, apk: bool = False):
    def view(request, path=""):
        response = serve(request, path or "index.html", document_root=root)
        if apk and path.endswith(".apk"):
            response["Content-Type"] = "application/vnd.android.package-archive"
        # a test run: always show the newest build
        response["Cache-Control"] = "no-cache"
        return response

    return view


urlpatterns = [
    *api_urlpatterns,
    re_path(r"^install/(?P<path>.*)$", _site(INSTALL_PAGE)),
    re_path(r"^downloads/(?P<path>.*)$", _site(DOWNLOADS, apk=True)),
    re_path(r"^(?P<path>.*)$", _site(WEB)),
]
