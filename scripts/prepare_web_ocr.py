"""Fetch pinned OCR assets with verified integrity; never fetch a runtime CDN on shop devices."""

import base64
import hashlib
import io
import json
import tarfile
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "mobile/web/scanner/ocr"
PACKAGES = [
    (
        "https://registry.npmjs.org/tesseract.js/-/tesseract.js-6.0.1.tgz",
        "/sPvMvrCtgxnNRCjbTYbr7BRu0yfWDsMZQ2a/T5aN/L1t8wUQN6tTWv6p6FwzpoEBA0jrN2UD2SX4QQFRdoDbA==",
    ),
    (
        "https://registry.npmjs.org/tesseract.js-core/-/tesseract.js-core-6.0.0.tgz",
        "1Qncm/9oKM7xgrQXZXNB+NRh19qiXGhxlrR8EwFbK5SaUbPZnS5OMtP/ghtqfd23hsr1ZvZbZjeuAGcMxd/ooA==",
    ),
    (
        "https://registry.npmjs.org/@tesseract.js-data/eng/-/eng-1.0.0.tgz",
        "mbTumm6KQPUHyzTPQaF3ObXYnx0SqqfV2nabqFVQBwD6Kl7PhGSLSzOlfFTWy0P3BjghaSKA2W9GB19Jk+ZcTg==",
    ),
]


REQUIRED = {
    "tesseract.min.js",
    "worker.min.js",
    "tesseract-core-lstm.wasm.js",
    "tesseract-core-lstm.wasm",
    "eng.traineddata.gz",
}
PACKAGE_STAMP = hashlib.sha256(json.dumps(PACKAGES).encode()).hexdigest()


def prepare():
    OUT.mkdir(parents=True, exist_ok=True)
    if (OUT / "manifest.json").exists():
        try:
            manifest = json.loads((OUT / "manifest.json").read_text())
        except (ValueError, OSError):
            manifest = {}
        data = manifest.get("files", {})
        if (
            manifest.get("packages") == PACKAGE_STAMP
            and REQUIRED <= data.keys()
            and all(
                (OUT / n).is_file()
                and hashlib.sha256((OUT / n).read_bytes()).hexdigest() == h
                for n, h in data.items()
            )
        ):
            print("Pinned web OCR assets already verified.")
            return
    hashes = {}
    for index, (url, integrity) in enumerate(PACKAGES):
        with urllib.request.urlopen(url, timeout=60) as response:
            raw = response.read(60_000_001)
        if (
            len(raw) > 60_000_000
            or base64.b64encode(hashlib.sha512(raw).digest()).decode() != integrity
        ):
            raise ValueError("OCR package integrity mismatch")
        with tarfile.open(fileobj=io.BytesIO(raw), mode="r:gz") as archive:
            for member in archive.getmembers():
                name = member.name
                destination = None
                if index == 0 and name in (
                    "package/dist/tesseract.min.js",
                    "package/dist/worker.min.js",
                ):
                    destination = name.rsplit("/", 1)[1]
                if (
                    index == 1
                    and name.startswith("package/tesseract-core")
                    and name.endswith((".wasm", ".wasm.js"))
                ):
                    destination = name.rsplit("/", 1)[1]
                if index == 2 and name == "package/4.0.0_best_int/eng.traineddata.gz":
                    destination = "eng.traineddata.gz"
                if (
                    name.rsplit("/", 1)[-1].lower().startswith("license")
                    and member.isfile()
                ):
                    destination = str(index) + "-" + name.rsplit("/", 1)[1]
                if destination and member.isfile():
                    data = archive.extractfile(member).read()
                    (OUT / destination).write_bytes(data)
                    hashes[destination] = hashlib.sha256(data).hexdigest()
    for required in (
        "tesseract.min.js",
        "worker.min.js",
        "tesseract-core-lstm.wasm.js",
        "eng.traineddata.gz",
    ):
        if required not in hashes:
            raise ValueError("Required OCR asset missing: " + required)
    (OUT / "manifest.json").write_text(
        json.dumps({"packages": PACKAGE_STAMP, "files": hashes}, indent=2) + "\n"
    )
    print("Verified pinned OCR assets:", len(hashes))


if __name__ == "__main__":
    prepare()
