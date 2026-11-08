"""Isolated artifact checks; never need a server or modify the real web build."""

import hashlib
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

MODULE = Path(__file__).resolve().parents[1] / "build_fullscreen_preview.py"
spec = importlib.util.spec_from_file_location("fullscreen_build", MODULE)
builder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(builder)


class FullscreenArtifactTests(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.TemporaryDirectory()
        self.addCleanup(self.folder.cleanup)
        self.root = Path(self.folder.name)
        self.source = self.root / "normal"
        self.source.mkdir()
        (self.source / "index.html").write_text("""<!doctype html><html><head>
  <base href="/">
  <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
  <script>
  window.erpSetScheme = function(dark) {
    set('theme-color', dark ? 'black' : 'white');
    set('apple-mobile-web-app-status-bar-style', dark ? 'black-translucent' : 'default');
  };
  </script>
  <meta name="mobile-web-app-capable" content="yes">
  <meta name="apple-mobile-web-app-status-bar-style" content="black">
  <meta name="apple-mobile-web-app-title" content="ERP System">
</head><body></body></html>""")
        (self.source / "main.dart.js").write_text("// release bundle")
        (self.source / "manifest.json").write_text(
            json.dumps({"start_url": ".", "display": "standalone"})
        )
        (self.source / "flutter_service_worker.js").write_text(
            "self.registration.unregister();"
        )
        self.output = self.root / "fullscreen"

    def test_normal_build_unchanged_preview_has_launch_time_opt_in(self):
        before = {f.name: f.read_bytes() for f in self.source.iterdir()}
        builder.make_preview(self.source, self.output)
        self.assertEqual(
            before, {f.name: f.read_bytes() for f in self.source.iterdir()}
        )
        html = (self.output / "index.html").read_text()
        self.assertIn('<base href="/fs/">', html)
        self.assertIn("window.erpFullScreen = true", html)
        self.assertIn('name="apple-mobile-web-app-capable" content="yes"', html)
        self.assertIn(
            'name="apple-mobile-web-app-status-bar-style" content="black-translucent"',
            html,
        )
        self.assertNotIn("set('apple-mobile-web-app-status-bar-style'", html)
        self.assertEqual(html.count('name="viewport"'), 1)
        self.assertLess(
            html.index('src="fullscreen.js"'), html.index("window.erpSetScheme")
        )
        manifest = json.loads((self.output / "manifest.json").read_text())
        self.assertEqual(
            [manifest[k] for k in ["id", "scope", "start_url"]], ["/fs/"] * 3
        )
        self.assertTrue((self.output / "fullscreen.js").is_file())
        builder.make_preview(
            self.source, self.output
        )  # safe, repeatable artifact generation

    def test_caching_worker_uses_separate_cache_names_and_patched_hashes(self):
        worker = self.source / "flutter_service_worker.js"
        worker.write_text("""const CACHE_NAME = 'flutter-app-cache';
const TEMP = 'flutter-temp-cache';
const MANIFEST = 'flutter-app-manifest';
const RESOURCES = {"index.html":"old","manifest.json":"old","/":"old"};""")
        builder.make_preview(self.source, self.output)
        result = (self.output / worker.name).read_text()
        self.assertIn("erp-fs-app-cache", result)
        self.assertNotIn("'flutter-app-cache'", result)
        checksum = hashlib.md5((self.output / "index.html").read_bytes()).hexdigest()
        self.assertIn(checksum, result)
        self.assertIn('"fullscreen.js":', result)

    def test_refuses_normal_tree_or_unrelated_existing_output(self):
        for output in [self.source, self.source / "fs", self.root]:
            with self.assertRaises(ValueError):
                builder.make_preview(self.source, output)
        self.output.mkdir()
        untouched = self.output / "keep.txt"
        untouched.write_text("keep")
        with self.assertRaises(ValueError):
            builder.make_preview(self.source, self.output)
        self.assertEqual(untouched.read_text(), "keep")


if __name__ == "__main__":
    unittest.main()
