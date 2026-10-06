from django.db import DatabaseError, connection, transaction

from apps.audit import services
from apps.audit.models import AuditEvent
from apps.common.testing import APITestCase, make_business, make_user


class AuditTests(APITestCase):
    def setUp(self):
        super().setUp()
        self.user = make_user("auditor")
        self.business = make_business()

    def test_events_record_actor_business_object_and_request_id(self):
        event = services.record(
            "thing.done", actor=self.user, business=self.business, obj=self.business
        )
        stored = AuditEvent.objects.get(pk=event.pk)
        self.assertEqual((stored.actor, stored.business), (self.user, self.business))
        self.assertEqual(
            (stored.object_type, stored.object_id), ("Business", str(self.business.pk))
        )

    def test_credentials_never_reach_the_trail(self):
        event = services.record(
            "thing.done",
            metadata={
                "password": "x",
                "nested": {"new_password": "y", "ok": 1},
                "list": [{"code": "z", "keep": 2}],
                "refresh": "t",
            },
        )
        self.assertEqual(event.metadata, {"nested": {"ok": 1}, "list": [{"keep": 2}]})

    def test_orm_refuses_to_change_or_delete_events(self):
        event = services.record("thing.done")
        event.action = "tampered"
        with self.assertRaises(RuntimeError):
            event.save()
        with self.assertRaises(RuntimeError):
            event.delete()

    def test_database_refuses_raw_updates_and_deletes_too(self):
        event = services.record("thing.done")
        for sql in (
            "UPDATE audit_auditevent SET action = 'tampered'",
            "DELETE FROM audit_auditevent",
        ):
            with self.subTest(sql=sql), self.assertRaises(DatabaseError), transaction.atomic():
                with connection.cursor() as cursor:
                    cursor.execute(sql)
        self.assertEqual(AuditEvent.objects.get(pk=event.pk).action, "thing.done")

    def test_queryset_update_and_delete_are_blocked_by_the_trigger(self):
        services.record("thing.done")
        with self.assertRaises(DatabaseError), transaction.atomic():
            AuditEvent.objects.all().update(action="tampered")
        with self.assertRaises(DatabaseError), transaction.atomic():
            AuditEvent.objects.all().delete()
