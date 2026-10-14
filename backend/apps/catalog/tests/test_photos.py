"""Product pictures: made small and clean, kept privately, replaced and removed, by every role."""

import os
from io import BytesIO

from django.core.files.uploadedfile import SimpleUploadedFile
from django.db import connection
from django.test.utils import CaptureQueriesContext
from PIL import Image

from apps.attachments.storage import PrivateStorage
from apps.audit.models import AuditEvent
from apps.businesses.models import Role
from apps.catalog.models import ProductPhoto
from apps.common.testing import APITestCase
from apps.inventory.tests.support import World, make_product


def picture(fmt="JPEG", size=(640, 480), color=(200, 30, 30), mode="RGB", exif=None):
    """An image file's bytes. `exif` is a dict of tag -> value (e.g. orientation, GPS)."""
    image = Image.new(mode, size, color)
    out = BytesIO()
    options = {}
    if exif is not None:
        info = Image.Exif()
        for tag, value in exif.items():
            info[tag] = value
        options["exif"] = info
    image.save(out, fmt, **options)
    return out.getvalue()


def upload(data, name="photo.jpg", content_type="image/jpeg"):
    return {"file": SimpleUploadedFile(name, data, content_type=content_type)}


class PhotoCase(APITestCase):
    def setUp(self):
        super().setUp()
        self.w = World()
        self.owner = self.w.api[Role.OWNER]
        self.pad = self.w.pad
        self.url = f"{self.w.base}/products/{self.pad.pk}/photo/"

    def put(self, data=None, client=None, product=None, **kw):
        url = self.url if product is None else f"{self.w.base}/products/{product.pk}/photo/"
        return (client or self.owner).post(
            url, upload(data if data is not None else picture(), **kw), format="multipart"
        )

    def get(self, size="full", client=None, **extra):
        return (client or self.owner).get(self.url, {"size": size}, **extra)

    def stored_files(self):
        storage = PrivateStorage()
        folder = f"{self.w.a.pk}/product-photos/{self.pad.pk}"
        if not storage.exists(folder):
            return []
        return sorted(storage.listdir(folder)[1])

    @staticmethod
    def decode(response):
        return Image.open(BytesIO(response.content))


class MakingAndServingTests(PhotoCase):
    def test_an_upload_becomes_a_full_and_a_thumbnail_jpeg(self):
        response = self.put(picture(size=(3000, 2000)))
        self.assertEqual(response.status_code, 201, response.content)
        version = response.json()["photo"]["version"]
        full, thumb = self.get("full"), self.get("thumb")
        for r in (full, thumb):
            self.assertEqual(r.status_code, 200)
            self.assertEqual(r["Content-Type"], "image/jpeg")
            self.assertEqual(r["X-Content-Type-Options"], "nosniff")
            self.assertEqual(r["Cache-Control"], "private, max-age=86400")
            self.assertEqual(r["ETag"], f'"{version}-{"full" if r is full else "thumb"}"')
        self.assertEqual(self.decode(full).size, (1024, 683))
        self.assertEqual(self.decode(thumb).size, (320, 213))
        self.assertEqual(self.decode(full).format, "JPEG")
        self.assertEqual(len(self.stored_files()), 2)

    def test_a_small_picture_is_not_blown_up(self):
        self.put(picture(size=(200, 100)))
        self.assertEqual(self.decode(self.get("full")).size, (200, 100))
        self.assertEqual(self.decode(self.get("thumb")).size, (200, 100))

    def test_the_default_size_is_the_full_one(self):
        self.put(picture(size=(1500, 1500)))
        response = self.owner.get(self.url)
        self.assertEqual(self.decode(response).size, (1024, 1024))

    def test_png_and_webp_are_accepted(self):
        for fmt, name in (("PNG", "a.png"), ("WEBP", "a.webp")):
            with self.subTest(fmt=fmt):
                self.assertEqual(self.put(picture(fmt=fmt), name=name).status_code, 201)
                self.assertEqual(self.decode(self.get()).format, "JPEG")

    def test_transparency_becomes_white(self):
        self.put(picture(fmt="PNG", mode="RGBA", size=(64, 64), color=(0, 0, 0, 0)), name="t.png")
        pixel = self.decode(self.get()).getpixel((5, 5))
        self.assertTrue(all(channel > 245 for channel in pixel), pixel)

    def test_the_cameras_rotated_flag_becomes_real_rotation(self):
        # 400 wide, 200 high, "rotate 90 degrees": the picture is meant to stand upright
        self.put(picture(size=(400, 200), exif={0x0112: 6}))
        self.assertEqual(self.decode(self.get()).size, (200, 400))

    def test_where_the_photo_was_taken_is_not_kept(self):
        gps = {0x010F: "SecretCameraMaker", 0x0112: 1}
        data = picture(exif=gps)
        self.assertIn(b"SecretCameraMaker", data)  # the upload does carry it
        self.put(data)
        for size in ("full", "thumb"):
            served = self.get(size).content
            self.assertNotIn(b"SecretCameraMaker", served)
            self.assertNotIn(b"Exif", served[:64])
            self.assertEqual(dict(self.decode(self.get(size)).getexif()), {})

    def test_the_browser_may_keep_it_until_it_changes(self):
        version = self.put().json()["photo"]["version"]
        again = self.get("full", HTTP_IF_NONE_MATCH=f'"{version}-full"')
        self.assertEqual(again.status_code, 304)
        self.assertEqual(again.content, b"")
        other = self.get("thumb", HTTP_IF_NONE_MATCH=f'"{version}-full"')
        self.assertEqual(other.status_code, 200)


class RefusedFilesTests(PhotoCase):
    def refused(self, response, code="invalid_image"):
        self.assertEqual(response.status_code, 400, response.content)
        self.assertEqual(response.json()["error"]["code"], code)
        self.assertFalse(ProductPhoto.objects.exists())
        self.assertEqual(self.stored_files(), [])

    def test_a_text_file_with_a_picture_name(self):
        self.refused(self.put(b"just some words", name="cream.jpg"))

    def test_a_pdf_is_not_a_picture(self):
        self.refused(self.put(b"%PDF-1.7 ...", name="a.pdf", content_type="application/pdf"))

    def test_junk_behind_a_jpeg_signature(self):
        self.refused(self.put(b"\xff\xd8\xff\xe0" + os.urandom(500)))

    def test_a_cut_off_picture(self):
        data = picture(size=(800, 600))
        self.refused(self.put(data[: len(data) // 3]))

    def test_an_absurdly_large_picture_is_refused_before_it_is_decoded(self):
        data = picture(fmt="PNG", size=(9000, 9000), mode="1", color=0)  # 81 megapixels, tiny file
        self.assertLess(len(data), 1_000_000)
        self.refused(self.put(data, name="big.png"))

    def test_no_file_and_an_empty_file(self):
        response = self.owner.post(self.url, {}, format="multipart")
        self.refused(response, "file_required")
        self.refused(self.put(b""), "file_required")

    def test_a_file_over_five_megabytes(self):
        self.refused(self.put(b"\xff\xd8\xff" + b"0" * (5 * 1024 * 1024)), "file_too_large")

    def test_a_refused_upload_keeps_the_old_picture(self):
        self.put()
        before = self.get().content
        self.put(b"not a picture")
        self.assertEqual(self.get().content, before)


class ReplaceAndRemoveTests(PhotoCase):
    def test_a_new_picture_replaces_the_old_one_and_its_files_go(self):
        first = self.put(picture(color=(255, 0, 0))).json()["photo"]["version"]
        with self.captureOnCommitCallbacks(execute=True):
            second = self.put(picture(color=(0, 0, 255))).json()["photo"]["version"]
        self.assertNotEqual(first, second)
        self.assertEqual(ProductPhoto.objects.count(), 1)
        self.assertEqual(self.stored_files(), [f"{second}-full.jpg", f"{second}-thumb.jpg"])
        red, green, blue = self.decode(self.get()).getpixel((10, 10))
        self.assertGreater(blue, 200)
        self.assertLess(red, 60)

    def test_removing_it(self):
        self.put()
        with self.captureOnCommitCallbacks(execute=True):
            response = self.owner.delete(self.url)
        self.assertEqual(response.status_code, 200, response.content)
        self.assertIsNone(response.json()["photo"])
        self.assertEqual(self.stored_files(), [])
        gone = self.get()
        self.assertEqual(gone.status_code, 404)
        self.assertEqual(gone.json()["error"]["code"], "photo_not_found")

    def test_removing_when_there_is_none_is_fine(self):
        self.assertEqual(self.owner.delete(self.url).status_code, 200)

    def test_the_product_says_whether_it_has_a_picture(self):
        detail = f"{self.w.base}/products/{self.pad.pk}/"
        self.assertIsNone(self.owner.get(detail).json()["photo"])
        version = self.put().json()["photo"]["version"]
        self.assertEqual(self.owner.get(detail).json()["photo"], {"version": version})
        listed = {
            p["sku"]: p["photo"]
            for p in self.owner.get(f"{self.w.base}/products/").json()["results"]
        }
        self.assertEqual(listed["BP-1"], {"version": version})
        self.assertIsNone(listed["OIL-1"])
        found = self.owner.get(f"{self.w.base}/barcodes/lookup/", {"code": "BP-1"}).json()
        self.assertEqual(found["photo"], {"version": version})

    def test_the_product_list_does_not_ask_the_database_more_for_more_pictures(self):
        extra = [make_product(self.w.a, f"X-{i}", f"Item {i}", self.w.unit) for i in range(5)]

        def queries():
            with CaptureQueriesContext(connection) as q:
                self.assertEqual(self.owner.get(f"{self.w.base}/products/").status_code, 200)
            return len(q)

        before = queries()
        for product in extra:
            self.put(product=product)
        self.assertEqual(queries(), before)

    def test_the_picture_of_an_archived_product_is_still_there(self):
        self.put()
        self.owner.patch(
            f"{self.w.base}/products/{self.pad.pk}/", {"is_active": False}, format="json"
        )
        self.assertEqual(self.get().status_code, 200)

    def test_changes_are_written_to_the_activity_history(self):
        self.put()
        self.owner.delete(self.url)
        actions = list(
            AuditEvent.objects.filter(business=self.w.a, action__startswith="product.photo")
            .order_by("created_at")
            .values_list("action", flat=True)
        )
        self.assertEqual(actions, ["product.photo_set", "product.photo_removed"])


class AccessTests(PhotoCase):
    def test_every_role_may_add_see_and_remove_a_picture(self):
        for role in (Role.WAREHOUSE, Role.SALES, Role.MANAGER, Role.OWNER):
            with self.subTest(role=role):
                client = self.w.api[role]
                self.assertEqual(self.put(client=client).status_code, 201)
                self.assertEqual(self.get(client=client).status_code, 200)
                self.assertEqual(client.delete(self.url).status_code, 200)

    def test_a_stranger_cannot_touch_it(self):
        self.put()
        b = self.w.b_api
        self.assertEqual(self.get(client=b).status_code, 404)
        self.assertEqual(self.put(client=b).status_code, 404)
        self.assertEqual(b.delete(self.url).status_code, 404)

    def test_another_business_cannot_be_reached_through_a_product_id(self):
        # business B's own URL with business A's product id
        url = f"/api/v1/businesses/{self.w.b.pk}/products/{self.pad.pk}/photo/"
        self.put()
        self.assertEqual(self.w.b_api.get(url).status_code, 404)
        self.assertEqual(
            self.w.b_api.post(url, upload(picture()), format="multipart").status_code, 404
        )

    def test_it_needs_a_signed_in_user(self):
        from rest_framework.test import APIClient

        self.assertEqual(APIClient().get(self.url).status_code, 401)
        self.assertEqual(
            APIClient().post(self.url, upload(picture()), format="multipart").status_code, 401
        )

    def test_a_wrong_size_word_is_refused(self):
        self.put()
        response = self.get("huge")
        self.assertEqual(response.status_code, 400)
        self.assertEqual(response.json()["error"]["code"], "validation_error")

    def test_the_picture_is_not_reachable_through_the_generic_file_route(self):
        self.put()
        self.assertEqual(ProductPhoto.objects.count(), 1)
        # product pictures are not attachments: nothing for the attachment routes to find
        from apps.attachments.models import Attachment

        self.assertEqual(Attachment.objects.count(), 0)
