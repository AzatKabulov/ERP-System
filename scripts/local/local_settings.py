"""Settings of the local test run (scripts/local/run_local.py): the real settings, plus a URL
configuration that also serves the web app, the install page and the Android file, so one
program is the whole system. Nothing here is used by a real server."""

import os
from pathlib import Path

from config.settings import *  # noqa: F401,F403

ROOT_URLCONF = "local_urls"

# Local sample-shop testing only; never imported by production settings.
LOCAL_TEST_LOGIN_ENABLED = True

# This program speaks plain http, on localhost or a Wi-Fi address; "secure-only" cookies would be
# dropped there and nobody could sign in to the owner console. Real servers keep them (settings.py).
SESSION_COOKIE_SECURE = False
CSRF_COOKIE_SECURE = False

# Where run_local.py collects the owner console's style files (outside the repository).
if os.environ.get("ERP_LOCAL_STATIC"):
    STATIC_ROOT = Path(os.environ["ERP_LOCAL_STATIC"])
