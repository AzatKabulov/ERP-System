"""The API's own URLs plus the web app, the install page and the Android file (what Caddy does
in the Docker setup). For the local test run only."""

import mimetypes
import os
from pathlib import Path

from django.urls import path, re_path
from django.utils._os import safe_join
from django.utils.cache import patch_vary_headers
from django.views.static import serve

from apps.common.local_test_login import LocalTestLogin, local_health
from config.urls import handler404, handler500  # noqa: F401
from config.urls import urlpatterns as api_urlpatterns

WEB = Path(os.environ.get("ERP_LOCAL_WEB_ROOT", "web"))
INSTALL_PAGE = Path(os.environ.get("ERP_LOCAL_INSTALL_PAGE", "install"))
DOWNLOADS = Path(os.environ.get("ERP_LOCAL_DOWNLOADS", "downloads"))


def _site(root: Path, *, apk: bool = False):
    def view(request, path=""):
        original = path or "index.html"
        selected = original
        compressed = False
        if not apk and _accepts_gzip(request):
            candidate = Path(safe_join(root, original + ".gz"))
            source = Path(safe_join(root, original))
            if (
                candidate.is_file()
                and source.is_file()
                and candidate.stat().st_mtime_ns >= source.stat().st_mtime_ns
            ):
                selected = original + ".gz"
                compressed = True
        response = serve(request, selected, document_root=root)
        if compressed:
            response["Content-Encoding"] = "gzip"
            response["Content-Type"] = (
                mimetypes.guess_type(original)[0] or "application/octet-stream"
            )
        if not apk:
            patch_vary_headers(response, ["Accept-Encoding"])
        if apk and path.endswith(".apk"):
            response["Content-Type"] = "application/vnd.android.package-archive"
        # a test run: always show the newest build
        response["Cache-Control"] = "no-cache"
        return response

    return view


def _accepts_gzip(request):
    for entry in request.headers.get("Accept-Encoding", "").lower().split(","):
        encoding, *parameters = (part.strip() for part in entry.split(";"))
        if encoding != "gzip":
            continue
        quality = next((part[2:] for part in parameters if part.startswith("q=")), "1")
        try:
            return 0 < float(quality) <= 1
        except ValueError:
            return False
    return False


urlpatterns = [
    path("api/v1/health/", local_health),
    path("api/v1/local-test-login/", LocalTestLogin.as_view()),
    *api_urlpatterns,
    re_path(r"^install/(?P<path>.*)$", _site(INSTALL_PAGE)),
    re_path(r"^downloads/(?P<path>.*)$", _site(DOWNLOADS, apk=True)),
    re_path(r"^(?P<path>.*)$", _site(WEB)),
]
