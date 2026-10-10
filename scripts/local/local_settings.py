"""Settings of the local test run (scripts/local/run_local.py): the real settings, plus a URL
configuration that also serves the web app, the install page and the Android file, so one
program is the whole system. Nothing here is used by a real server."""

from config.settings import *  # noqa: F401,F403

ROOT_URLCONF = "local_urls"
