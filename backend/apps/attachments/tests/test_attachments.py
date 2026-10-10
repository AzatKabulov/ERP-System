import hashlib
import uuid
from unittest import mock

from django.core.files.uploadedfile import SimpleUploadedFile
from django.db import DatabaseError, connection, transaction
from rest_framework.test import APIClient

from apps.attachments import services
from apps.attachments.models import Attachment
from apps.attachments.storage import PrivateStorage
from apps.attachments.tests.support import JPEG, PDF, PNG, SAMPLES, WEBP, upload
from apps.audit.models import AuditEvent
from apps.businesses.models import Role
from apps.common.testing import APITestCase, PrivateFilesMixin
from apps.inventory.tests.support import World


class AttachmentCase(PrivateFilesMixin, APITestCase):
    def setUp(self):
        super().setUp()
        self.w = World()
        self.owner = self.w.api[Role.OWNER]

    def stored_files(self):
        return sorted(p for p in self.private_root.rglob("*") if p.is_file())


class UploadTests(AttachmentCase):
    def test_every_allowed_type_is_accepted_and_recognised_by_its_bytes(self):
        for content_type, (name, content) in SAMPLES.items():
            with self.subTest(content_type=content_type):
                response = upload(self.owner, self.w.base, content, name)
                self.assertEqual(response.status_code, 201, response.content)
                body = response.json()
                self.assertEqual(set(body), {"id", "name", "content_type", "size", "created_at"})
                self.assertEqual(body["content_type"], content_type)
                self.assertEqual(body["name"], name)
                self.assertEqual(body["size"], len(content))
                row = Attachment.objects.get(pk=body["id"])
                self.assertEqual(row.business, self.w.a)
                self.assertEqual(row.sha256, hashlib.sha256(content).hexdigest())
                self.assertEqual(row.uploaded_by, self.w.owner)

    def test_the_type_comes_from_the_bytes_not_from_the_name_or_the_declared_type(self):
        text = upload(self.owner, self.w.base, b"just some text, not a picture", "receipt.jpg")
        self.assertEqual(text.status_code, 400)
        self.assertEqual(text.json()["error"]["code"], "file_type_not_allowed")
        script = upload(self.owner, self.w.base, b"<script>alert(1)</script>", "x.pdf")
        self.assertEqual(script.status_code, 400)
        svg = upload(self.owner, self.w.base, b"<svg xmlns='http://www.w3.org/2000/svg'/>", "a.png")
        self.assertEqual(svg.status_code, 400)
        exe = upload(self.owner, self.w.base, b"MZ\x90\x00" + b"\x00" * 100, "setup.jpg")
        self.assertEqual(exe.status_code, 400)
        # a real JPEG with a .pdf name is a JPEG, whatever it is called
        renamed = upload(self.owner, self.w.base, JPEG, "scan.pdf")
        self.assertEqual(renamed.status_code, 201)
        self.assertEqual(renamed.json()["content_type"], "image/jpeg")
        self.assertEqual(Attachment.objects.count(), 1)
        self.assertEqual(len(self.stored_files()), 1)  # the refused ones left nothing behind

    def test_a_riff_file_that_is_not_webp_and_a_truncated_png_signature_are_refused(self):
        wave = b"RIFF" + (4).to_bytes(4, "little") + b"WAVE" + b"\x00" * 40
        self.assertEqual(upload(self.owner, self.w.base, wave, "a.webp").status_code, 400)
        self.assertEqual(upload(self.owner, self.w.base, PNG[:5], "a.png").status_code, 400)
        self.assertEqual(upload(self.owner, self.w.base, b"  %PDF-1.4", "a.pdf").status_code, 400)

    def test_no_file_or_an_empty_file_is_refused(self):
        none = self.owner.post(f"{self.w.base}/attachments/", {}, format="multipart")
        self.assertEqual(none.status_code, 400)
        self.assertEqual(none.json()["error"]["code"], "file_required")
        wrong_field = self.owner.post(
            f"{self.w.base}/attachments/",
            {"photo": SimpleUploadedFile("a.jpg", JPEG)},
            format="multipart",
        )
        self.assertEqual(wrong_field.json()["error"]["code"], "file_required")
        empty = upload(self.owner, self.w.base, b"", "empty.jpg")
        self.assertEqual(empty.status_code, 400)
        self.assertEqual(empty.json()["error"]["code"], "file_required")
        self.assertFalse(Attachment.objects.exists())

    def test_a_json_body_is_not_a_file_upload(self):
        response = self.owner.post(f"{self.w.base}/attachments/", {"file": "x"}, format="json")
        self.assertEqual(response.status_code, 415)

    def test_five_megabytes_is_the_limit(self):
        limit = services.MAX_BYTES
        self.assertEqual(limit, 5 * 1024 * 1024)
        exact = upload(self.owner, self.w.base, JPEG + b"\x00" * (limit - len(JPEG)), "big.jpg")
        self.assertEqual(exact.status_code, 201, exact.content)
        one_over = upload(self.owner, self.w.base, JPEG + b"\x00" * (limit - len(JPEG) + 1))
        self.assertEqual(one_over.status_code, 400)
        error = one_over.json()["error"]
        self.assertEqual(error["code"], "file_too_large")
        self.assertEqual(error["params"], {"max_bytes": limit})
        self.assertEqual(Attachment.objects.count(), 1)

    def test_a_request_that_announces_a_far_bigger_body_is_refused_unread(self):
        huge = upload(self.owner, self.w.base, JPEG + b"\x00" * (6 * 1024 * 1024))
        self.assertEqual(huge.status_code, 400)
        self.assertEqual(huge.json()["error"]["code"], "file_too_large")
        self.assertFalse(Attachment.objects.exists())

    def test_the_limit_is_one_constant(self):
        with mock.patch.object(services, "MAX_BYTES", 100):
            self.assertEqual(upload(self.owner, self.w.base, JPEG).status_code, 400)
        self.assertEqual(upload(self.owner, self.w.base, JPEG).status_code, 201)

    def test_the_upload_is_audited_without_the_file(self):
        body = upload(self.owner, self.w.base, PDF, "bill.pdf").json()
        event = AuditEvent.objects.get(action="attachment.uploaded")
        self.assertEqual(event.object_id, body["id"])
        self.assertEqual(event.actor, self.w.owner)
        self.assertEqual(event.business, self.w.a)
        self.assertEqual(event.metadata["sha256"], hashlib.sha256(PDF).hexdigest())
        self.assertEqual(event.metadata["size"], len(PDF))


class StorageTests(AttachmentCase):
    def test_the_bytes_are_stored_under_the_ids_and_never_under_the_clients_name(self):
        body = upload(self.owner, self.w.base, JPEG, "../../etc/passwd.jpg").json()
        self.assertEqual(body["name"], "passwd.jpg")  # the directories are dropped
        files = self.stored_files()
        self.assertEqual(
            [p.relative_to(self.private_root).as_posix() for p in files],
            [f"{self.w.a.pk}/{body['id']}"],
        )
        for path in self.private_root.rglob("*"):
            for part in path.relative_to(self.private_root).parts:
                self.assertNotIn("passwd", part)
                uuid.UUID(part)  # every folder and file is named by an id
        self.assertEqual(files[0].read_bytes(), JPEG)

    def test_a_file_name_cannot_smuggle_headers_or_quotes(self):
        body = upload(self.owner, self.w.base, JPEG, 'bad"name\r\nX-Evil: 1.jpg').json()
        self.assertNotIn("\r", body["name"])
        self.assertNotIn("\n", body["name"])
        self.assertNotIn('"', body["name"])
        response = self.owner.get(f"{self.w.base}/attachments/{body['id']}/")
        self.assertEqual(response.status_code, 200)
        self.assertNotIn("\n", response["Content-Disposition"])
        self.assertNotIn("X-Evil", response.headers)

    def test_the_files_have_no_url_and_the_api_never_shows_a_path(self):
        body = upload(self.owner, self.w.base).json()
        with self.assertRaises(ValueError):
            PrivateStorage().url("anything")
        for value in body.values():
            self.assertNotIn(str(self.private_root), str(value))
        detail = self.owner.get(f"{self.w.base}/attachments/{body['id']}/")
        for name, value in detail.headers.items():
            self.assertNotIn(str(self.private_root), value, name)

    def test_the_root_is_the_setting(self):
        upload(self.owner, self.w.base)
        self.assertEqual(len(self.stored_files()), 1)  # in the temporary folder of this test

    def test_a_record_whose_file_is_gone_is_a_404_not_a_crash(self):
        body = upload(self.owner, self.w.base).json()
        self.stored_files()[0].unlink()
        response = self.owner.get(f"{self.w.base}/attachments/{body['id']}/")
        self.assertEqual(response.status_code, 404)
        self.assertEqual(response.json()["error"]["code"], "file_missing")

    def test_a_failed_save_leaves_no_record(self):
        with mock.patch.object(PrivateStorage, "save", side_effect=OSError("disk full")):
            client = APIClient(raise_request_exception=False)
            client.force_authenticate(self.w.owner)
            response = upload(client, self.w.base)
        self.assertEqual(response.status_code, 500)
        self.assertFalse(Attachment.objects.exists())

    def test_attachment_rows_are_append_only(self):
        body = upload(self.owner, self.w.base).json()
        row = Attachment.objects.get(pk=body["id"])
        row.name = "other"
        with self.assertRaises(RuntimeError):
            row.save()
        with self.assertRaises(RuntimeError):
            row.delete()
        with self.assertRaises(DatabaseError), transaction.atomic():
            Attachment.objects.filter(pk=row.pk).update(name="other")
        with self.assertRaises(DatabaseError), transaction.atomic():
            with connection.cursor() as cursor:
                cursor.execute("DELETE FROM attachments_attachment")


class DownloadTests(AttachmentCase):
    def test_every_type_comes_back_byte_for_byte_with_safe_headers(self):
        for content_type, (name, content) in SAMPLES.items():
            with self.subTest(content_type=content_type):
                body = upload(self.owner, self.w.base, content, name).json()
                response = self.owner.get(f"{self.w.base}/attachments/{body['id']}/")
                self.assertEqual(response.status_code, 200)
                self.assertEqual(response.content, content)
                self.assertEqual(response["Content-Type"], content_type)
                self.assertEqual(response["Content-Disposition"], f'inline; filename="{name}"')
                self.assertEqual(response["X-Content-Type-Options"], "nosniff")
                self.assertEqual(response["Cache-Control"], "private, no-store")

    def test_the_stored_type_is_served_even_if_the_client_asks_for_another(self):
        body = upload(self.owner, self.w.base, PNG, "a.png").json()
        response = self.owner.get(
            f"{self.w.base}/attachments/{body['id']}/", HTTP_ACCEPT="text/html"
        )
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response["Content-Type"], "image/png")

    def test_cyrillic_and_turkmen_file_names_survive(self):
        for name in ("чек за аренду.jpg", "Şäher çeki.pdf"):
            with self.subTest(name=name):
                content = PDF if name.endswith("pdf") else JPEG
                body = upload(self.owner, self.w.base, content, name).json()
                self.assertEqual(body["name"], name)
                response = self.owner.get(f"{self.w.base}/attachments/{body['id']}/")
                self.assertIn("filename*=utf-8''", response["Content-Disposition"])
                self.assertEqual(response.content, content)

    def test_manager_may_upload_and_view_too(self):
        body = upload(self.w.api[Role.MANAGER], self.w.base, WEBP, "m.webp")
        self.assertEqual(body.status_code, 201)
        got = self.w.api[Role.MANAGER].get(f"{self.w.base}/attachments/{body.json()['id']}/")
        self.assertEqual(got.status_code, 200)


class AccessTests(AttachmentCase):
    def test_sales_and_warehouse_can_neither_upload_nor_view(self):
        mine = upload(self.owner, self.w.base).json()["id"]
        for role in (Role.SALES, Role.WAREHOUSE):
            with self.subTest(role=role):
                self.assertEqual(upload(self.w.api[role], self.w.base).status_code, 403)
                got = self.w.api[role].get(f"{self.w.base}/attachments/{mine}/")
                self.assertEqual(got.status_code, 403)
        self.assertEqual(Attachment.objects.count(), 1)

    def test_nothing_is_reachable_without_signing_in(self):
        mine = upload(self.owner, self.w.base).json()["id"]
        anonymous = APIClient()
        self.assertEqual(upload(anonymous, self.w.base).status_code, 401)
        self.assertEqual(anonymous.get(f"{self.w.base}/attachments/{mine}/").status_code, 401)
        self.assertEqual(Attachment.objects.count(), 1)

    def test_another_business_gets_a_404_and_cannot_upload_into_this_one(self):
        mine = upload(self.owner, self.w.base).json()["id"]
        # not a member of business A: 404 whatever the id
        self.assertEqual(self.w.b_api.get(f"{self.w.base}/attachments/{mine}/").status_code, 404)
        self.assertEqual(upload(self.w.b_api, self.w.base).status_code, 404)
        # a member of business B asking B's URL for A's attachment: not found there
        b_base = f"/api/v1/businesses/{self.w.b.pk}"
        self.assertEqual(self.w.b_api.get(f"{b_base}/attachments/{mine}/").status_code, 404)
        # and B's own file is not visible through A
        theirs = upload(self.w.b_api, b_base).json()["id"]
        self.assertEqual(self.owner.get(f"{self.w.base}/attachments/{theirs}/").status_code, 404)
        self.assertEqual(Attachment.objects.get(pk=theirs).business, self.w.b)
        unknown = self.owner.get(f"{self.w.base}/attachments/{uuid.uuid4()}/")
        self.assertEqual(unknown.status_code, 404)
