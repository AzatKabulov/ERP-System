"""Used automatically by `manage.py test`: identical settings, but a fast password hasher
(production keeps Django's slow, secure default) and a throw-away folder for uploaded files, so
a test run never writes into the real private files directory."""

import atexit
import shutil
import tempfile
from pathlib import Path

from .settings import *  # noqa: F401,F403

PASSWORD_HASHERS = ["django.contrib.auth.hashers.MD5PasswordHasher"]

PRIVATE_FILES_ROOT = Path(tempfile.mkdtemp(prefix="erp-test-files-"))
atexit.register(shutil.rmtree, PRIVATE_FILES_ROOT, ignore_errors=True)
