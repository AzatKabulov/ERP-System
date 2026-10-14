"""Product pictures: taking an uploaded photo, making it small and safe, keeping it, serving it.

A phone photo is several megabytes, carries the place it was taken in its metadata and may be
turned sideways by a flag. What is kept is two plain JPEG files made from it: a larger one
(at most 1024 px on its long side) for the product page and a thumbnail (320 px) for lists and the
gallery. Orientation is applied, transparency becomes white and every piece of metadata is
dropped, so the stored files hold the picture and nothing else.

What a file is comes from its first bytes (JPEG, PNG or WebP) and from the image library actually
decoding it, never from its name. A picture with an absurd number of pixels is refused before it is
decoded. The files live under the private files root, at a name that carries the picture's
version, and are served only through the permission-checked API.
"""

import uuid
from io import BytesIO

from django.core.files.base import ContentFile
from django.db import transaction
from PIL import Image, ImageOps, UnidentifiedImageError

from apps.attachments.services import MAX_BYTES, detect_content_type, too_large
from apps.attachments.storage import PrivateStorage
from apps.audit import services as audit
from apps.common.errors import ApiError

from .models import Product, ProductPhoto

MAX_PIXELS = 40_000_000  # a 40 megapixel camera is the largest we accept
FULL_EDGE = 1024
THUMB_EDGE = 320
ALLOWED = {"image/jpeg", "image/png", "image/webp"}
SIZES = ("full", "thumb")


def _invalid() -> ApiError:
    return ApiError(
        "invalid_image",
        "This is not a picture the system can use",
        fields={"file": [{"code": "invalid_image", "message": "Not a usable picture"}]},
    )


def _jpeg(image: Image.Image, edge: int, quality: int) -> bytes:
    small = image.copy()
    small.thumbnail((edge, edge), Image.Resampling.LANCZOS)
    out = BytesIO()
    small.save(out, "JPEG", quality=quality, optimize=True)  # no exif= : metadata is dropped
    return out.getvalue()


def make_versions(data: bytes) -> tuple[bytes, bytes]:
    """(full, thumbnail) JPEG bytes made from an uploaded picture. Raises `invalid_image`."""
    if detect_content_type(data[:16]) not in ALLOWED:
        raise _invalid()
    try:
        image = Image.open(BytesIO(data))
        if image.width * image.height > MAX_PIXELS:
            raise _invalid()
        image = ImageOps.exif_transpose(image)  # the camera's "rotated" flag becomes real pixels
        image.load()
    except (UnidentifiedImageError, OSError, ValueError, Image.DecompressionBombError) as exc:
        raise _invalid() from exc
    if image.mode in ("RGBA", "LA") or (image.mode == "P" and "transparency" in image.info):
        rgba = image.convert("RGBA")
        flat = Image.new("RGB", rgba.size, "white")
        flat.paste(rgba, mask=rgba.getchannel("A"))
        image = flat
    else:
        image = image.convert("RGB")
    return _jpeg(image, FULL_EDGE, 85), _jpeg(image, THUMB_EDGE, 80)


def _delete_files(business_id, product_id, version) -> None:
    storage = PrivateStorage()
    for size in SIZES:
        name = f"{business_id}/product-photos/{product_id}/{version}-{size}.jpg"
        if storage.exists(name):
            storage.delete(name)


def set_photo(business, actor, product: Product, upload) -> ProductPhoto:
    """Keep `upload` (Django's uploaded file) as the product's picture, replacing the old one."""
    if upload is None or not upload.size:
        raise ApiError(
            "file_required",
            "Send the picture in the form field 'file'",
            fields={"file": [{"code": "required", "message": "Required"}]},
        )
    if upload.size > MAX_BYTES:
        raise too_large()
    full, thumb = make_versions(upload.read())
    storage = PrivateStorage()
    with transaction.atomic():
        # one picture at a time per product: two tablets taking one at once cannot mix files
        locked = Product.objects.select_for_update().get(pk=product.pk, business=business)
        old = ProductPhoto.objects.filter(product=locked).first()
        photo = old or ProductPhoto(product=locked, business=business)
        previous = old.version if old else None
        photo.version = uuid.uuid4()
        photo.full_size, photo.thumb_size = len(full), len(thumb)
        photo.updated_by = actor
        photo.save()
        for size, data in zip(SIZES, (full, thumb), strict=True):
            stored = storage.save(photo.storage_name(size), ContentFile(data))
            if stored != photo.storage_name(size):  # a version is never reused
                raise RuntimeError("a product picture file already exists under this version")
        audit.record(
            "product.photo_set",
            actor=actor,
            business=business,
            obj=locked,
            metadata={"sku": locked.sku, "bytes": photo.full_size + photo.thumb_size},
        )
        if previous is not None:
            transaction.on_commit(lambda: _delete_files(business.pk, locked.pk, previous))
    return photo


def remove_photo(business, actor, product: Product) -> None:
    with transaction.atomic():
        locked = Product.objects.select_for_update().get(pk=product.pk, business=business)
        photo = ProductPhoto.objects.filter(product=locked).first()
        if photo is None:
            return
        version = photo.version
        photo.delete()
        audit.record(
            "product.photo_removed",
            actor=actor,
            business=business,
            obj=locked,
            metadata={"sku": locked.sku},
        )
        transaction.on_commit(lambda: _delete_files(business.pk, locked.pk, version))


def read_photo(photo: ProductPhoto, size: str) -> bytes:
    try:
        with PrivateStorage().open(photo.storage_name(size), "rb") as handle:
            return handle.read()
    except FileNotFoundError as exc:
        raise ApiError("file_missing", "The picture is not available", status_code=404) from exc
