#!/usr/bin/env python3
"""Make an opt-in /fs/ artifact from an existing release web build. Never deploys.

    python3 scripts/build_fullscreen_preview.py

The normal build stays byte-for-byte unchanged. Serve build/web-fs at /fs/ later,
only after approval. Service-worker caches and the manifest identity are isolated.
"""

import argparse
import hashlib
import json
import re
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def make_preview(source: Path, destination: Path) -> None:
    source, destination = source.resolve(), destination.resolve()
    if (
        source == destination
        or source in destination.parents
        or destination in source.parents
    ):
        raise ValueError("Preview output must be separate from the normal build")
    index = (source / "index.html").read_text()
    if "$FLUTTER_BASE_HREF" in index or not (source / "main.dart.js").is_file():
        raise ValueError("Build the normal release web app first")
    if destination.exists():
        # Refuse to erase an unrelated existing directory.
        if not (destination / ".erp-fullscreen-preview").is_file():
            raise ValueError("Existing output is not an ERP fullscreen preview")
        shutil.rmtree(destination)
    shutil.copytree(source, destination)
    (destination / ".erp-fullscreen-preview").write_text(
        "local artifact; no deployment\n"
    )
    index = re.sub(r'<base href="[^"]*">', '<base href="/fs/">', index, count=1)
    index = re.sub(
        r'(<meta name="apple-mobile-web-app-status-bar-style" content=")[^"]*(">)',
        r"\g<1>black-translucent\2",
        index,
        count=1,
    )
    if 'name="apple-mobile-web-app-capable"' not in index:
        index = index.replace(
            '<meta name="mobile-web-app-capable" content="yes">',
            '<meta name="mobile-web-app-capable" content="yes">\n'
            '  <meta name="apple-mobile-web-app-capable" content="yes">',
        )
    viewport = '<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">'
    index = re.sub(r'<meta name="viewport"[^>]*>', "", index)
    bridge = (
        viewport
        + '\n  <script>window.erpFullScreen = true;</script>\n  <script src="fullscreen.js"></script>\n'
    )
    index = index.replace("  <script>", bridge + "  <script>", 1)
    # The opt-in document chooses black-translucent at install/launch time. The
    # normal document's current scheme behavior is deliberately untouched.
    index = re.sub(
        r"^[ \t]*set\('apple-mobile-web-app-status-bar-style'.*?;[ \t]*$",
        "",
        index,
        flags=re.MULTILINE,
    )
    index = index.replace('content="ERP System"', 'content="ERP full screen"')
    (destination / "index.html").write_text(index)
    shutil.copyfile(ROOT / "scripts/pwa/fullscreen.js", destination / "fullscreen.js")
    manifest_path = destination / "manifest.json"
    manifest = json.loads(manifest_path.read_text())
    manifest.update(
        id="/fs/",
        start_url="/fs/",
        scope="/fs/",
        name="ERP full screen",
        short_name="ERP FS",
    )
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")
    # Flutter's default cache names otherwise collide between / and /fs/.
    worker = destination / "flutter_service_worker.js"
    if worker.exists():
        text = worker.read_text()
        for original, isolated in [
            ("flutter-app-cache", "erp-fs-app-cache"),
            ("flutter-temp-cache", "erp-fs-temp-cache"),
            ("flutter-app-manifest", "erp-fs-app-manifest"),
        ]:
            text = text.replace(original, isolated)
        match = re.search(r"const RESOURCES = (\{.*?\});", text, re.DOTALL)
        if not match:
            if "self.registration.unregister()" not in text:
                raise ValueError("Unrecognized Flutter service-worker format")
            # Pinned Flutter emits a non-caching worker that removes an old
            # worker. Keep it intact; it has no shared caches to rename.
            worker.write_text(text)
            return
        resources = json.loads(match[1])
        for name in ["index.html", "manifest.json", "fullscreen.js"]:
            resources[name] = hashlib.md5((destination / name).read_bytes()).hexdigest()
        if "/" in resources:
            resources["/"] = resources["index.html"]
        text = (
            text[: match.start(1)]
            + json.dumps(resources, separators=(",", ":"))
            + text[match.end(1) :]
        )
        worker.write_text(text)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--web", type=Path, default=ROOT / "mobile/build/web")
    parser.add_argument("--output", type=Path, default=ROOT / "mobile/build/web-fs")
    args = parser.parse_args()
    make_preview(args.web, args.output)
    print(f"Created local /fs/ artifact: {args.output}")
    print("Normal build unchanged. Nothing pushed or deployed.")


if __name__ == "__main__":
    main()
