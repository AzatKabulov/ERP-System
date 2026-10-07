from django.conf import settings
from django.core.files.storage import FileSystemStorage


class PrivateStorage(FileSystemStorage):
    """Files under `settings.PRIVATE_FILES_ROOT`, readable only by this code. There is no URL
    for them on purpose: they are served by an API view after a permission check."""

    def __init__(self):
        # Built per use, so a changed setting (a test's temporary folder) is always honoured.
        super().__init__(
            location=str(settings.PRIVATE_FILES_ROOT),
            file_permissions_mode=0o600,
            directory_permissions_mode=0o700,
        )

    def url(self, name):
        raise ValueError("Private files have no URL")
