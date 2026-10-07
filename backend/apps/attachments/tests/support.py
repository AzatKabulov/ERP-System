"""Small files with real signatures, and an upload helper, shared by the attachment and expense
tests."""

from django.core.files.uploadedfile import SimpleUploadedFile

JPEG = b"\xff\xd8\xff\xe0\x00\x10JFIF\x00" + b"\x01" * 200 + b"\xff\xd9"
PNG = b"\x89PNG\r\n\x1a\n" + b"\x00\x00\x00\rIHDR" + b"\x02" * 100
WEBP = b"RIFF" + (4 + 100).to_bytes(4, "little") + b"WEBP" + b"VP8 " + b"\x03" * 96
PDF = b"%PDF-1.4\n1 0 obj\n<< /Type /Catalog >>\nendobj\n%%EOF\n"

SAMPLES = {
    "image/jpeg": ("receipt.jpg", JPEG),
    "image/png": ("receipt.png", PNG),
    "image/webp": ("receipt.webp", WEBP),
    "application/pdf": ("receipt.pdf", PDF),
}


def upload(client, base: str, content: bytes = JPEG, name: str = "receipt.jpg", **extra):
    """POST one file to /attachments/ the way the app does (multipart, field `file`)."""
    file = SimpleUploadedFile(name, content, content_type="image/jpeg")
    return client.post(f"{base}/attachments/", {"file": file}, format="multipart", **extra)
