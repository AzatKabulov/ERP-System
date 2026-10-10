"""Guards shared by endpoints that accept an uploaded file."""

# Headroom for the multipart envelope around the file (boundaries, field headers).
_ENVELOPE_BYTES = 64 * 1024


def declared_size_exceeds(request, max_bytes: int) -> bool:
    """True when the request announces a body clearly larger than `max_bytes` of file. Checked
    before the body is parsed, so an oversized upload is refused without being read. A client
    that lies about its size is still caught by the size check on the parsed file."""
    try:
        declared = int(request.META.get("CONTENT_LENGTH") or 0)
    except ValueError:
        return False
    return declared > max_bytes + _ENVELOPE_BYTES
