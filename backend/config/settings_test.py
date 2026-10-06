"""Used automatically by `manage.py test`: identical settings, but a fast password hasher
(production keeps Django's slow, secure default)."""

from .settings import *  # noqa: F401,F403

PASSWORD_HASHERS = ["django.contrib.auth.hashers.MD5PasswordHasher"]
