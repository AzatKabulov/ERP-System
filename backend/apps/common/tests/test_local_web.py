"""Public local web assets: compression must never change downloads or permit traversal."""

import gzip
import importlib.util
import os
import tempfile
from pathlib import Path

from django.conf import settings
from django.core.exceptions import SuspiciousFileOperation
from django.http import Http404
from django.test import RequestFactory, SimpleTestCase
from django.utils.http import http_date

local_script = Path(settings.BASE_DIR).parent / "scripts" / "local" / "local_urls.py"
spec = importlib.util.spec_from_file_location("erp_local_test_urls", local_script)
local_urls = importlib.util.module_from_spec(spec)
spec.loader.exec_module(local_urls)


class LocalWebAssetTests(SimpleTestCase):
    def setUp(self):
        folder = tempfile.TemporaryDirectory()
        self.addCleanup(folder.cleanup)
        self.root = Path(folder.name) / "web"
        self.root.mkdir()
        self.original = b"console.log('local web asset');\n" * 1000
        self.asset = self.root / "main.dart.js"
        self.asset.write_bytes(self.original)
        self.compressed = self.root / "main.dart.js.gz"
        self.compressed.write_bytes(gzip.compress(self.original))
        os.utime(self.asset, (1700000000, 1700000000))
        os.utime(self.compressed, (1700000000, 1700000000))
        self.view = local_urls._site(self.root)
        self.factory = RequestFactory()

    def response(self, encoding="", **headers):
        response = self.view(
            self.factory.get("/main.dart.js", HTTP_ACCEPT_ENCODING=encoding, **headers),
            "main.dart.js",
        )
        self.addCleanup(response.close)
        return response

    def test_negotiates_precompressed_javascript_with_the_original_content_type(self):
        response = self.response("gzip, deflate, br")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response["Content-Encoding"], "gzip")
        self.assertIn("javascript", response["Content-Type"])
        self.assertIn("Accept-Encoding", response["Vary"])
        self.assertEqual(gzip.decompress(b"".join(response.streaming_content)), self.original)
        self.assertLess(int(response["Content-Length"]), len(self.original) // 5)

    def test_clients_without_gzip_receive_the_original(self):
        response = self.response()
        self.assertNotIn("Content-Encoding", response)
        self.assertEqual(b"".join(response.streaming_content), self.original)

    def test_explicitly_disabled_gzip_is_respected(self):
        response = self.response("br, gzip;q=0")
        self.assertNotIn("Content-Encoding", response)
        self.assertEqual(b"".join(response.streaming_content), self.original)

    def test_compressed_assets_still_revalidate_after_an_update(self):
        response = self.response(
            "gzip", HTTP_IF_MODIFIED_SINCE=http_date(self.compressed.stat().st_mtime)
        )
        self.assertEqual(response.status_code, 304)
        self.assertEqual(response["Cache-Control"], "no-cache")
        self.assertIn("Accept-Encoding", response["Vary"])

    def test_a_missing_compressed_asset_falls_back_to_the_original(self):
        self.compressed.unlink()
        response = self.response("gzip")
        self.assertNotIn("Content-Encoding", response)
        self.assertEqual(b"".join(response.streaming_content), self.original)

    def test_an_updated_build_never_uses_stale_compressed_javascript(self):
        self.asset.write_bytes(b"updated build")
        os.utime(self.asset, (1700000100, 1700000100))
        response = self.response("gzip")
        self.assertNotIn("Content-Encoding", response)
        self.assertEqual(b"".join(response.streaming_content), b"updated build")

    def test_launcher_prepares_compressed_public_assets_with_matching_timestamps(self):
        launcher_spec = importlib.util.spec_from_file_location(
            "erp_local_test_launcher", local_script.with_name("run_local.py")
        )
        launcher = importlib.util.module_from_spec(launcher_spec)
        launcher_spec.loader.exec_module(launcher)
        picture = self.root / "picture.jpg"
        picture.write_bytes(b"pretend jpeg" * 1000)
        saved = launcher.compress_web_assets(self.root)
        self.assertGreater(saved, 0)
        self.assertEqual(gzip.decompress(self.compressed.read_bytes()), self.original)
        self.assertEqual(self.compressed.stat().st_mtime_ns, self.asset.stat().st_mtime_ns)
        self.assertFalse((self.root / "picture.jpg.gz").exists())

    def test_cannot_download_a_file_outside_the_web_folder(self):
        (self.root.parent / "private.js.gz").write_bytes(gzip.compress(b"not public"))
        with self.assertRaises((Http404, SuspiciousFileOperation)):
            self.view(
                self.factory.get("/../private.js", HTTP_ACCEPT_ENCODING="gzip"),
                "../private.js",
            )

    def test_android_downloads_are_not_recompressed(self):
        apk = self.root / "erp.apk"
        apk.write_bytes(b"apk bytes")
        response = local_urls._site(self.root, apk=True)(
            self.factory.get("/erp.apk", HTTP_ACCEPT_ENCODING="gzip"), "erp.apk"
        )
        self.addCleanup(response.close)
        self.assertEqual(response["Content-Type"], "application/vnd.android.package-archive")
        self.assertNotIn("Content-Encoding", response)
