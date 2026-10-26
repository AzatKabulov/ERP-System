"""Switch static bundles only on the explicitly marked disposable benchmark server."""

import argparse
import shutil
import tarfile
from pathlib import Path

p = argparse.ArgumentParser()
p.add_argument("--data", type=Path, required=True)
p.add_argument("--archive", type=Path, required=True)
a = p.parse_args()
if not (a.data / ".performance-sample").is_file():
    p.error("Not a disposable performance sample folder.")
incoming = a.data / "incoming-performance-web"
shutil.rmtree(incoming, ignore_errors=True)
incoming.mkdir()
with tarfile.open(a.archive) as archive:
    for member in archive.getmembers():
        parts = Path(member.name).parts
        if (
            not parts
            or parts[0] != "web"
            or ".." in parts
            or not (member.isfile() or member.isdir())
        ):
            p.error("Archive must contain only a web/ tree without links.")
    archive.extractall(incoming)  # All paths and member types were validated above.
web = a.data / "public/web"
shutil.rmtree(web)
shutil.move(incoming / "web", web)
incoming.rmdir()
