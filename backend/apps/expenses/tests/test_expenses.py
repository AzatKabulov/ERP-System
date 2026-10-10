import importlib
import os
import threading
import uuid
from concurrent.futures import ThreadPoolExecutor
from datetime import UTC, datetime, timedelta
from decimal import Decimal
from io import StringIO
from unittest import mock

from django.apps import apps as django_apps
from django.core.management import call_command
from django.db import connections

from apps.accounts.models import User
from apps.attachments.tests.support import JPEG, PDF, upload
from apps.audit.models import AuditEvent
from apps.businesses import services as business_services
from apps.businesses.models import Business, Membership, Role
from apps.common.testing import (
    PASSWORD,
    APITestCase,
    APITransactionTestCase,
    PrivateFilesMixin,
    client_for,
    make_business,
)
from apps.expenses import services
from apps.expenses.models import Expense, ExpenseCategory
from apps.inventory.tests.support import World

D = Decimal


class ExpenseCase(PrivateFilesMixin, APITestCase):
    def setUp(self):
        super().setUp()
        self.w = World()
        self.owner = self.w.api[Role.OWNER]
        self.manager = self.w.api[Role.MANAGER]
        self.rent = ExpenseCategory.objects.create(business=self.w.a, name="Аренда")
        self.transport = ExpenseCategory.objects.create(business=self.w.a, name="Транспорт")
        self.today = self.w.a.local_today()

    # -- helpers ------------------------------------------------------------------------
    def payload(self, **overrides):
        return {
            "category": str(self.rent.pk),
            "location": str(self.w.store.pk),
            "amount": "123.45",
            "spent_on": self.today.isoformat(),
            "description": "October rent",
            **overrides,
        }

    def add(self, client=None, **overrides):
        response = (client or self.owner).post(
            f"{self.w.base}/expenses/", self.payload(**overrides), format="json"
        )
        self.assertEqual(response.status_code, 201, response.content)
        return response.json()

    def void(self, expense, reason="Entered twice", client=None):
        return (client or self.owner).post(
            f"{self.w.base}/expenses/{expense['id']}/void/", {"reason": reason}, format="json"
        )

    def fields(self, response):
        return response.json()["error"]["fields"]


class CategoryTests(ExpenseCase):
    def test_list_shape_and_filter(self):
        ExpenseCategory.objects.filter(pk=self.transport.pk).update(is_active=False)
        listed = self.owner.get(f"{self.w.base}/expense-categories/").json()
        self.assertEqual(listed["count"], 2)
        self.assertEqual(
            listed["results"],
            [
                {"id": str(self.rent.pk), "name": "Аренда", "is_active": True},
                {"id": str(self.transport.pk), "name": "Транспорт", "is_active": False},
            ],
        )
        active = self.owner.get(f"{self.w.base}/expense-categories/?active=1").json()
        self.assertEqual([c["name"] for c in active["results"]], ["Аренда"])
        inactive = self.owner.get(f"{self.w.base}/expense-categories/?active=0").json()
        self.assertEqual([c["name"] for c in inactive["results"]], ["Транспорт"])

    def test_create_and_rename_and_deactivate(self):
        created = self.owner.post(
            f"{self.w.base}/expense-categories/", {"name": "  Remont  "}, format="json"
        )
        self.assertEqual(created.status_code, 201)
        body = created.json()
        self.assertEqual((body["name"], body["is_active"]), ("Remont", True))
        url = f"{self.w.base}/expense-categories/{body['id']}/"
        renamed = self.owner.patch(url, {"name": "Remontlar"}, format="json")
        self.assertEqual(renamed.json()["name"], "Remontlar")
        off = self.owner.patch(url, {"is_active": False}, format="json")
        self.assertFalse(off.json()["is_active"])
        on = self.manager.patch(url, {"is_active": True}, format="json")
        self.assertTrue(on.json()["is_active"])
        self.assertEqual(
            list(
                AuditEvent.objects.filter(object_id=body["id"])
                .order_by("created_at")
                .values_list("action", flat=True)
            ),
            [
                "expense_category.created",
                "expense_category.updated",
                "expense_category.updated",
                "expense_category.updated",
            ],
        )

    def test_names_are_unique_per_business_ignoring_case(self):
        clash = self.owner.post(
            f"{self.w.base}/expense-categories/", {"name": " аренда "}, format="json"
        )
        self.assertEqual(clash.status_code, 400)
        self.assertEqual(self.fields(clash)["name"][0]["code"], "name_taken")
        rename = self.owner.patch(
            f"{self.w.base}/expense-categories/{self.transport.pk}/",
            {"name": "АРЕНДА"},
            format="json",
        )
        self.assertEqual(self.fields(rename)["name"][0]["code"], "name_taken")
        same = self.owner.patch(
            f"{self.w.base}/expense-categories/{self.rent.pk}/",
            {"name": "аренда"},  # its own name in another case is fine
            format="json",
        )
        self.assertEqual(same.status_code, 200)
        other_business = self.w.b_api.post(
            f"/api/v1/businesses/{self.w.b.pk}/expense-categories/",
            {"name": "Аренда"},
            format="json",
        )
        self.assertEqual(other_business.status_code, 201)
        blank = self.owner.post(f"{self.w.base}/expense-categories/", {"name": " "}, format="json")
        self.assertEqual(blank.status_code, 400)

    def test_a_deactivated_category_cannot_be_used_but_old_expenses_keep_it(self):
        expense = self.add()
        self.owner.patch(
            f"{self.w.base}/expense-categories/{self.rent.pk}/",
            {"is_active": False},
            format="json",
        )
        refused = self.owner.post(f"{self.w.base}/expenses/", self.payload(), format="json")
        self.assertEqual(refused.status_code, 400)
        self.assertEqual(self.fields(refused)["category"][0]["code"], "inactive_reference")
        shown = self.owner.get(f"{self.w.base}/expenses/{expense['id']}/").json()
        self.assertEqual(shown["category"]["name"], "Аренда")
        # an edit that keeps the (now inactive) category is still allowed
        kept = self.owner.patch(
            f"{self.w.base}/expenses/{expense['id']}/", {"description": "fixed"}, format="json"
        )
        self.assertEqual(kept.status_code, 200)

    def test_only_owner_and_manager(self):
        for role in (Role.SALES, Role.WAREHOUSE):
            with self.subTest(role=role):
                api = self.w.api[role]
                self.assertEqual(api.get(f"{self.w.base}/expense-categories/").status_code, 403)
                self.assertEqual(
                    api.post(
                        f"{self.w.base}/expense-categories/", {"name": "X"}, format="json"
                    ).status_code,
                    403,
                )
                self.assertEqual(
                    api.patch(
                        f"{self.w.base}/expense-categories/{self.rent.pk}/",
                        {"name": "X"},
                        format="json",
                    ).status_code,
                    403,
                )
        self.assertEqual(ExpenseCategory.objects.filter(business=self.w.a).count(), 2)

    def test_another_business_gets_404(self):
        url = f"{self.w.base}/expense-categories/{self.rent.pk}/"
        self.assertEqual(self.w.b_api.patch(url, {"name": "Z"}, format="json").status_code, 404)
        self.assertEqual(self.w.b_api.get(f"{self.w.base}/expense-categories/").status_code, 404)
        b_url = f"/api/v1/businesses/{self.w.b.pk}/expense-categories/{self.rent.pk}/"
        self.assertEqual(self.w.b_api.patch(b_url, {"name": "Z"}, format="json").status_code, 404)
        self.rent.refresh_from_db()
        self.assertEqual(self.rent.name, "Аренда")


class DefaultCategoryTests(APITestCase):
    NAMES = ["Аренда", "Зарплата", "Коммунальные услуги", "Транспорт", "Прочее"]

    def names(self, business):
        return sorted(
            ExpenseCategory.objects.filter(business=business).values_list("name", flat=True)
        )

    def test_a_new_business_gets_the_default_categories(self):
        owner = User.objects.create_user("boss", "boss@example.test", PASSWORD)
        business = business_services.create_business(name="Täze", owner=owner, location_name="A")
        self.assertEqual(self.names(business), sorted(self.NAMES))
        self.assertEqual(services.DEFAULT_CATEGORIES, self.NAMES)

    def test_the_operator_commands_seed_them_too(self):
        with mock.patch.dict(
            os.environ, {"ERP_OWNER_PASSWORD": PASSWORD, "ERP_SAMPLE_PASSWORD": PASSWORD}
        ):
            call_command(
                "create_business",
                name="Dükan",
                owner_username="boss",
                owner_email="boss@example.test",
                location="Esasy",
                stdout=StringIO(),
            )
            call_command("create_sample_business", stdout=StringIO())
        for business in Business.objects.all():
            self.assertEqual(self.names(business), sorted(self.NAMES), business.name)
        self.assertEqual(Business.objects.count(), 2)

    def test_the_migration_fills_in_businesses_that_existed_before(self):
        migration = importlib.import_module("apps.expenses.migrations.0002_default_categories")
        self.assertEqual(migration.DEFAULT_CATEGORIES, services.DEFAULT_CATEGORIES)
        old = make_business("Old shop")  # created without the service: no categories yet
        custom = make_business("Custom shop")
        ExpenseCategory.objects.create(business=custom, name="транспорт")  # own spelling
        self.assertEqual(self.names(old), [])
        migration.add_default_categories(django_apps, None)
        self.assertEqual(self.names(old), sorted(self.NAMES))
        self.assertEqual(
            self.names(custom), sorted([*self.NAMES[:3], *self.NAMES[4:], "транспорт"])
        )
        migration.add_default_categories(django_apps, None)  # running it twice changes nothing
        self.assertEqual(self.names(old), sorted(self.NAMES))
        self.assertEqual(ExpenseCategory.objects.filter(business=custom).count(), 5)

    def test_seeding_twice_does_not_duplicate(self):
        business = make_business("X")
        services.create_default_categories(business)
        services.create_default_categories(business)
        self.assertEqual(self.names(business), sorted(self.NAMES))


class ExpenseCrudTests(ExpenseCase):
    def test_create_returns_the_documented_shape(self):
        receipt = upload(self.owner, self.w.base, JPEG, "чек.jpg").json()
        body = self.add(attachment=receipt["id"])
        owner = self.w.owner
        self.assertEqual(
            set(body),
            {
                "id",
                "category",
                "location",
                "amount",
                "spent_on",
                "description",
                "attachment",
                "created_by",
                "created_at",
                "voided",
                "void_reason",
            },
        )
        self.assertEqual(body["category"], {"id": str(self.rent.pk), "name": "Аренда"})
        self.assertEqual(body["location"], {"id": str(self.w.store.pk), "name": "A Store"})
        self.assertEqual(body["amount"], "123.45")
        self.assertEqual(body["spent_on"], self.today.isoformat())
        self.assertEqual(body["description"], "October rent")
        self.assertEqual(
            body["attachment"],
            {
                "id": receipt["id"],
                "name": "чек.jpg",
                "content_type": "image/jpeg",
                "size": len(JPEG),
            },
        )
        self.assertEqual(
            body["created_by"], {"id": str(owner.pk), "name": owner.full_name or owner.username}
        )
        self.assertIs(body["voided"], False)
        self.assertEqual(body["void_reason"], "")
        event = AuditEvent.objects.get(action="expense.created")
        self.assertEqual(event.object_id, body["id"])
        self.assertEqual(event.metadata["amount"], "123.45")

    def test_the_receipt_is_optional_and_so_is_the_description(self):
        body = self.owner.post(
            f"{self.w.base}/expenses/",
            {
                "category": str(self.rent.pk),
                "location": str(self.w.warehouse.pk),
                "amount": "5",
                "spent_on": self.today.isoformat(),
            },
            format="json",
        )
        self.assertEqual(body.status_code, 201, body.content)
        self.assertIsNone(body.json()["attachment"])
        self.assertEqual(body.json()["description"], "")
        self.assertEqual(body.json()["amount"], "5.00")

    def test_a_manager_records_expenses_too(self):
        body = self.add(client=self.manager, amount="10.50")
        self.assertEqual(body["created_by"]["id"], str(self.w.users[Role.MANAGER].pk))

    def test_amount_must_be_a_positive_money_value(self):
        for bad in ("0", "0.00", "-5", "1.234", "abc", "", None, "1" + "0" * 13):
            with self.subTest(amount=bad):
                response = self.owner.post(
                    f"{self.w.base}/expenses/", self.payload(amount=bad), format="json"
                )
                self.assertEqual(response.status_code, 400, response.content)
                self.assertIn("amount", self.fields(response))
        self.assertEqual(self.add(amount="0.01")["amount"], "0.01")  # the smallest amount there is
        self.assertFalse(Expense.objects.filter(amount__lte=0).exists())

    def test_required_fields_and_lengths(self):
        response = self.owner.post(f"{self.w.base}/expenses/", {}, format="json")
        self.assertEqual(response.status_code, 400)
        self.assertEqual(set(self.fields(response)), {"category", "location", "amount", "spent_on"})
        long = self.owner.post(
            f"{self.w.base}/expenses/", self.payload(description="x" * 501), format="json"
        )
        self.assertIn("description", self.fields(long))
        self.assertEqual(len(self.add(description="x" * 500)["description"]), 500)
        bad_date = self.owner.post(
            f"{self.w.base}/expenses/", self.payload(spent_on="07.10.2026"), format="json"
        )
        self.assertIn("spent_on", self.fields(bad_date))

    def test_a_date_in_the_future_is_refused_in_the_business_time_zone(self):
        tomorrow = self.today + timedelta(days=1)
        refused = self.owner.post(
            f"{self.w.base}/expenses/", self.payload(spent_on=tomorrow.isoformat()), format="json"
        )
        self.assertEqual(refused.status_code, 400)
        self.assertEqual(self.fields(refused)["spent_on"][0]["code"], "future_date")
        self.add(spent_on=self.today.isoformat())  # today is fine
        self.add(spent_on="2020-01-31")  # so is the past
        # 22:30 UTC on 7 October is already 8 October in Ashgabat (UTC+5)
        moment = datetime(2026, 10, 7, 22, 30, tzinfo=UTC)
        with mock.patch("django.utils.timezone.now", return_value=moment):
            self.assertEqual(self.add(spent_on="2026-10-08")["spent_on"], "2026-10-08")
            late = self.owner.post(
                f"{self.w.base}/expenses/", self.payload(spent_on="2026-10-09"), format="json"
            )
            self.assertEqual(self.fields(late)["spent_on"][0]["code"], "future_date")
        Business.objects.filter(pk=self.w.a.pk).update(timezone="UTC")
        with mock.patch("django.utils.timezone.now", return_value=moment):
            early = self.owner.post(
                f"{self.w.base}/expenses/", self.payload(spent_on="2026-10-08"), format="json"
            )
            self.assertEqual(self.fields(early)["spent_on"][0]["code"], "future_date")
            self.add(spent_on="2026-10-07")

    def test_things_of_another_business_are_refused(self):
        b_category = ExpenseCategory.objects.create(business=self.w.b, name="Аренда")
        b_receipt = upload(self.w.b_api, f"/api/v1/businesses/{self.w.b.pk}").json()["id"]
        before = Expense.objects.count()
        for field, value in (
            ("category", str(b_category.pk)),
            ("location", str(self.w.b_store.pk)),
            ("attachment", b_receipt),
            ("category", str(uuid.uuid4())),
        ):
            with self.subTest(field=field):
                response = self.owner.post(
                    f"{self.w.base}/expenses/", self.payload(**{field: value}), format="json"
                )
                self.assertEqual(response.status_code, 400, response.content)
                self.assertEqual(self.fields(response)[field][0]["code"], "does_not_exist")
        self.assertEqual(Expense.objects.count(), before)
        mine = self.add()
        for field, value in (
            ("category", str(b_category.pk)),
            ("location", str(self.w.b_store.pk)),
            ("attachment", b_receipt),
        ):
            with self.subTest(patch=field):
                response = self.owner.patch(
                    f"{self.w.base}/expenses/{mine['id']}/", {field: value}, format="json"
                )
                self.assertEqual(response.status_code, 400)
        again = self.owner.get(f"{self.w.base}/expenses/{mine['id']}/").json()
        self.assertEqual(again["category"]["id"], str(self.rent.pk))
        self.assertIsNone(again["attachment"])

    def test_an_inactive_location_is_refused(self):
        self.w.warehouse.is_active = False
        self.w.warehouse.save()
        response = self.owner.post(
            f"{self.w.base}/expenses/",
            self.payload(location=str(self.w.warehouse.pk)),
            format="json",
        )
        self.assertEqual(response.status_code, 400)
        self.assertEqual(self.fields(response)["location"][0]["code"], "inactive_reference")

    def test_get_one(self):
        body = self.add()
        again = self.owner.get(f"{self.w.base}/expenses/{body['id']}/")
        self.assertEqual(again.status_code, 200)
        self.assertEqual(again.json(), body)
        missing = self.owner.get(f"{self.w.base}/expenses/{uuid.uuid4()}/")
        self.assertEqual(missing.status_code, 404)


class ExpenseEditAndVoidTests(ExpenseCase):
    def test_edit_changes_only_what_is_sent_and_audits_old_and_new(self):
        receipt = upload(self.owner, self.w.base, PDF, "bill.pdf").json()
        body = self.add()
        response = self.manager.patch(
            f"{self.w.base}/expenses/{body['id']}/",
            {
                "amount": "150",
                "category": str(self.transport.pk),
                "attachment": receipt["id"],
                "description": body["description"],  # unchanged: not a change
            },
            format="json",
        )
        self.assertEqual(response.status_code, 200, response.content)
        edited = response.json()
        self.assertEqual(edited["amount"], "150.00")
        self.assertEqual(edited["category"]["name"], "Транспорт")
        self.assertEqual(edited["attachment"]["id"], receipt["id"])
        self.assertEqual(edited["location"], body["location"])
        self.assertEqual(edited["spent_on"], body["spent_on"])
        event = AuditEvent.objects.get(action="expense.updated")
        self.assertEqual(event.actor, self.w.users[Role.MANAGER])
        self.assertEqual(
            event.metadata["changes"],
            {
                "amount": {"old": "123.45", "new": "150.00"},
                "category": {"old": str(self.rent.pk), "new": str(self.transport.pk)},
                "attachment": {"old": None, "new": receipt["id"]},
            },
        )
        self.owner.patch(
            f"{self.w.base}/expenses/{body['id']}/",
            {"attachment": None, "spent_on": "2026-01-15", "location": str(self.w.warehouse.pk)},
            format="json",
        )
        last = AuditEvent.objects.filter(action="expense.updated").order_by("-created_at")[0]
        self.assertEqual(
            last.metadata["changes"],
            {
                "attachment": {"old": receipt["id"], "new": None},
                "spent_on": {"old": self.today.isoformat(), "new": "2026-01-15"},
                "location": {"old": str(self.w.store.pk), "new": str(self.w.warehouse.pk)},
            },
        )
        shown = self.owner.get(f"{self.w.base}/expenses/{body['id']}/").json()
        self.assertIsNone(shown["attachment"])
        self.assertEqual(shown["location"]["name"], "A Warehouse")

    def test_a_correction_that_changes_nothing_is_not_audited(self):
        body = self.add()
        same = self.owner.patch(
            f"{self.w.base}/expenses/{body['id']}/",
            {"amount": "123.45", "description": "October rent"},
            format="json",
        )
        self.assertEqual(same.status_code, 200)
        empty = self.owner.patch(f"{self.w.base}/expenses/{body['id']}/", {}, format="json")
        self.assertEqual(empty.status_code, 200)
        self.assertFalse(AuditEvent.objects.filter(action="expense.updated").exists())

    def test_an_edit_is_validated_like_a_new_expense(self):
        body = self.add()
        url = f"{self.w.base}/expenses/{body['id']}/"
        for patch in (
            {"amount": "0"},
            {"amount": "-1"},
            {"spent_on": (self.today + timedelta(days=1)).isoformat()},
            {"description": "x" * 501},
            {"category": None},
        ):
            with self.subTest(patch=patch):
                self.assertEqual(self.owner.patch(url, patch, format="json").status_code, 400)
        again = self.owner.get(url).json()
        self.assertEqual(again, body)
        self.assertFalse(AuditEvent.objects.filter(action="expense.updated").exists())

    def test_voiding_needs_a_reason_and_keeps_the_record(self):
        body = self.add()
        for reason in (None, "", "   "):
            with self.subTest(reason=reason):
                response = self.owner.post(
                    f"{self.w.base}/expenses/{body['id']}/void/", {"reason": reason}, format="json"
                )
                self.assertEqual(response.status_code, 400)
                self.assertIn("reason", self.fields(response))
        missing = self.owner.post(f"{self.w.base}/expenses/{body['id']}/void/", {}, format="json")
        self.assertEqual(missing.status_code, 400)
        response = self.void(body, "Entered twice", client=self.manager)
        self.assertEqual(response.status_code, 200, response.content)
        voided = response.json()
        self.assertIs(voided["voided"], True)
        self.assertEqual(voided["void_reason"], "Entered twice")
        self.assertEqual(voided["amount"], "123.45")  # the record is kept as it was
        row = Expense.objects.get(pk=body["id"])
        self.assertEqual((row.voided_by, row.is_voided), (self.w.users[Role.MANAGER], True))
        event = AuditEvent.objects.get(action="expense.voided")
        self.assertEqual(event.metadata["reason"], "Entered twice")
        self.assertEqual(event.actor, self.w.users[Role.MANAGER])
        shown = self.owner.get(f"{self.w.base}/expenses/{body['id']}/").json()
        self.assertIs(shown["voided"], True)

    def test_a_voided_expense_cannot_be_voided_again_or_edited(self):
        body = self.add()
        self.assertEqual(self.void(body).status_code, 200)
        again = self.void(body, "Another reason")
        self.assertEqual(again.status_code, 409)
        self.assertEqual(again.json()["error"]["code"], "already_void")
        edit = self.owner.patch(
            f"{self.w.base}/expenses/{body['id']}/", {"amount": "1"}, format="json"
        )
        self.assertEqual(edit.status_code, 409)
        self.assertEqual(edit.json()["error"]["code"], "expense_void")
        row = Expense.objects.get(pk=body["id"])
        self.assertEqual((row.amount, row.void_reason), (D("123.45"), "Entered twice"))
        self.assertEqual(AuditEvent.objects.filter(action="expense.voided").count(), 1)
        self.assertFalse(AuditEvent.objects.filter(action="expense.updated").exists())

    def test_an_expense_can_never_be_deleted_through_the_api(self):
        body = self.add()
        response = self.owner.delete(f"{self.w.base}/expenses/{body['id']}/")
        self.assertIn(response.status_code, (403, 405))
        self.assertTrue(Expense.objects.filter(pk=body["id"]).exists())

    def test_only_owner_and_manager_change_or_void(self):
        body = self.add()
        for role in (Role.SALES, Role.WAREHOUSE):
            with self.subTest(role=role):
                api = self.w.api[role]
                self.assertEqual(
                    api.patch(
                        f"{self.w.base}/expenses/{body['id']}/", {"amount": "1"}, format="json"
                    ).status_code,
                    403,
                )
                self.assertEqual(self.void(body, client=api).status_code, 403)
        self.assertEqual(Expense.objects.get(pk=body["id"]).amount, D("123.45"))

    def test_another_business_cannot_touch_it(self):
        body = self.add()
        b_base = f"/api/v1/businesses/{self.w.b.pk}"
        for base in (self.w.base, b_base):
            with self.subTest(base=base):
                url = f"{base}/expenses/{body['id']}/"
                self.assertEqual(self.w.b_api.get(url).status_code, 404)
                self.assertEqual(
                    self.w.b_api.patch(url, {"amount": "1"}, format="json").status_code, 404
                )
                self.assertEqual(
                    self.w.b_api.post(f"{url}void/", {"reason": "x"}, format="json").status_code,
                    404,
                )
        row = Expense.objects.get(pk=body["id"])
        self.assertEqual((row.amount, row.is_voided), (D("123.45"), False))


class ExpenseListTests(ExpenseCase):
    def setUp(self):
        super().setUp()
        self.e1 = self.add(spent_on="2026-09-30", amount="100", description="Rent September")
        self.e2 = self.add(
            spent_on="2026-10-01",
            amount="40.50",
            category=str(self.transport.pk),
            location=str(self.w.warehouse.pk),
            description="Такси до склада",
        )
        self.e3 = self.add(spent_on="2026-10-05", amount="9.99", description="Şäher ýoly")
        self.e4 = self.add(spent_on="2026-10-05", amount="500", description="Entered by mistake")
        self.void(self.e4, "Wrong shop")

    def ids(self, query=""):
        response = self.owner.get(f"{self.w.base}/expenses/{query}")
        self.assertEqual(response.status_code, 200, response.content)
        return [e["id"] for e in response.json()["results"]]

    def test_newest_first_without_voided_by_default(self):
        listed = self.owner.get(f"{self.w.base}/expenses/").json()
        self.assertEqual(listed["count"], 3)
        self.assertEqual(
            [e["id"] for e in listed["results"]], [self.e3["id"], self.e2["id"], self.e1["id"]]
        )
        self.assertEqual(set(listed), {"count", "next", "previous", "results"})

    def test_include_void(self):
        self.assertEqual(len(self.ids("?include_void=1")), 4)
        self.assertEqual(len(self.ids("?include_void=true")), 4)
        self.assertEqual(len(self.ids("?include_void=0")), 3)
        voided = [
            e for e in self.owner.get(f"{self.w.base}/expenses/?include_void=1").json()["results"]
        ]
        self.assertEqual([e["voided"] for e in voided].count(True), 1)

    def test_dates_are_inclusive(self):
        self.assertEqual(
            self.ids("?date_from=2026-10-01&date_to=2026-10-05"), [self.e3["id"], self.e2["id"]]
        )
        self.assertEqual(self.ids("?date_to=2026-09-30"), [self.e1["id"]])
        self.assertEqual(self.ids("?date_from=2026-10-05"), [self.e3["id"]])
        self.assertEqual(self.ids("?date_from=2026-10-06&date_to=2026-10-31"), [])

    def test_category_location_and_text(self):
        self.assertEqual(self.ids(f"?category={self.transport.pk}"), [self.e2["id"]])
        self.assertEqual(self.ids(f"?location={self.w.warehouse.pk}"), [self.e2["id"]])
        self.assertEqual(self.ids("?q=rent"), [self.e1["id"]])  # case-insensitive
        self.assertEqual(self.ids("?q=RENT%20sept"), [self.e1["id"]])
        self.assertEqual(self.ids("?q=%D0%A2%D0%90%D0%9A%D0%A1%D0%98"), [self.e2["id"]])  # ТАКСИ
        self.assertEqual(self.ids("?q=%C5%9E%C3%84HER"), [self.e3["id"]])  # ŞÄHER
        self.assertEqual(self.ids("?q=mistake"), [])  # that one is void
        self.assertEqual(self.ids("?q=mistake&include_void=1"), [self.e4["id"]])
        self.assertEqual(self.ids(f"?category={self.rent.pk}&q=rent"), [self.e1["id"]])

    def test_bad_filter_values_are_a_400(self):
        for query in (
            "?date_from=yesterday",
            "?date_to=2026-13-01",
            "?category=nope",
            "?location=1",
        ):
            with self.subTest(query=query):
                self.assertEqual(self.owner.get(f"{self.w.base}/expenses/{query}").status_code, 400)

    def test_paging(self):
        page = self.owner.get(f"{self.w.base}/expenses/?limit=2").json()
        self.assertEqual((page["count"], len(page["results"])), (3, 2))
        self.assertIsNotNone(page["next"])
        second = self.owner.get(f"{self.w.base}/expenses/?limit=2&offset=2").json()
        self.assertEqual([e["id"] for e in second["results"]], [self.e1["id"]])

    def test_only_this_business_and_only_owner_or_manager(self):
        b_base = f"/api/v1/businesses/{self.w.b.pk}"
        b_category = ExpenseCategory.objects.create(business=self.w.b, name="Аренда")
        theirs = self.w.b_api.post(
            f"{b_base}/expenses/",
            {
                "category": str(b_category.pk),
                "location": str(self.w.b_store.pk),
                "amount": "1",
                "spent_on": "2026-10-01",
            },
            format="json",
        )
        self.assertEqual(theirs.status_code, 201)
        self.assertNotIn(theirs.json()["id"], self.ids("?include_void=1"))
        self.assertEqual(self.w.b_api.get(f"{self.w.base}/expenses/").status_code, 404)
        for role in (Role.SALES, Role.WAREHOUSE):
            self.assertEqual(self.w.api[role].get(f"{self.w.base}/expenses/").status_code, 403)
            self.assertEqual(
                self.w.api[role].get(f"{self.w.base}/expenses/summary/").status_code, 403
            )
            self.assertEqual(
                self.w.api[role]
                .post(f"{self.w.base}/expenses/", self.payload(), format="json")
                .status_code,
                403,
            )

    def test_location_rules_apply_to_writes_and_reads(self):
        """Owner and manager see every location today; the checks are still made, so a member
        restricted to some locations could never read or write outside them."""
        restricted = {self.w.store.pk}
        with mock.patch.object(Membership, "location_ids", return_value=restricted):
            listed = self.manager.get(f"{self.w.base}/expenses/").json()
            self.assertEqual(
                sorted(e["id"] for e in listed["results"]), sorted([self.e1["id"], self.e3["id"]])
            )
            denied = self.manager.post(
                f"{self.w.base}/expenses/",
                self.payload(location=str(self.w.warehouse.pk)),
                format="json",
            )
            self.assertEqual(denied.status_code, 403)
            self.assertEqual(denied.json()["error"]["code"], "location_not_permitted")
            move = self.manager.patch(
                f"{self.w.base}/expenses/{self.e1['id']}/",
                {"location": str(self.w.warehouse.pk)},
                format="json",
            )
            self.assertEqual(move.status_code, 403)
            other = self.manager.get(f"{self.w.base}/expenses/{self.e2['id']}/")
            self.assertEqual(other.status_code, 404)
            self.assertEqual(
                self.manager.post(
                    f"{self.w.base}/expenses/{self.e2['id']}/void/", {"reason": "x"}, format="json"
                ).status_code,
                404,
            )
            ok = self.manager.post(
                f"{self.w.base}/expenses/", self.payload(amount="3"), format="json"
            )
            self.assertEqual(ok.status_code, 201)
            summary = self.manager.get(f"{self.w.base}/expenses/summary/").json()
            self.assertEqual(
                summary["total"], "112.99"
            )  # 100 + 9.99 + 3, nothing from the warehouse
        self.assertEqual(Expense.objects.get(pk=self.e1["id"]).location, self.w.store)


class SummaryTests(ExpenseCase):
    def summary(self, query=""):
        response = self.owner.get(f"{self.w.base}/expenses/summary/{query}")
        self.assertEqual(response.status_code, 200, response.content)
        return response.json()

    def test_empty(self):
        self.assertEqual(self.summary(), {"total": "0.00", "count": 0, "by_category": []})

    def test_totals_and_by_category_without_voided(self):
        self.add(spent_on="2026-09-30", amount="100.10")
        self.add(spent_on="2026-10-02", amount="0.20")
        gone = self.add(spent_on="2026-10-03", amount="1000")
        self.add(spent_on="2026-10-04", amount="55", category=str(self.transport.pk))
        self.add(
            spent_on="2026-10-04",
            amount="5",
            category=str(self.transport.pk),
            location=str(self.w.warehouse.pk),
        )
        self.void(gone)
        body = self.summary()
        self.assertEqual(body["total"], "160.30")
        self.assertEqual(body["count"], 4)
        self.assertEqual(
            body["by_category"],
            [
                {
                    "category": {"id": str(self.rent.pk), "name": "Аренда"},
                    "total": "100.30",
                    "count": 2,
                },
                {
                    "category": {"id": str(self.transport.pk), "name": "Транспорт"},
                    "total": "60.00",
                    "count": 2,
                },
            ],
        )

    def test_the_same_date_and_location_filters(self):
        self.add(spent_on="2026-09-30", amount="100")
        self.add(spent_on="2026-10-02", amount="20", category=str(self.transport.pk))
        self.add(
            spent_on="2026-10-02",
            amount="7",
            category=str(self.transport.pk),
            location=str(self.w.warehouse.pk),
        )
        self.assertEqual(self.summary("?date_from=2026-10-01")["total"], "27.00")
        self.assertEqual(self.summary("?date_to=2026-09-30")["total"], "100.00")
        self.assertEqual(self.summary("?date_from=2026-10-02&date_to=2026-10-02")["count"], 2)
        by_place = self.summary(f"?location={self.w.warehouse.pk}")
        self.assertEqual((by_place["total"], by_place["count"]), ("7.00", 1))
        self.assertEqual([c["category"]["name"] for c in by_place["by_category"]], ["Транспорт"])
        self.assertEqual(
            self.owner.get(f"{self.w.base}/expenses/summary/?date_from=x").status_code, 400
        )

    def test_a_category_used_only_by_voided_expenses_is_not_listed(self):
        gone = self.add(amount="9", category=str(self.transport.pk))
        self.add(amount="1")
        self.void(gone)
        self.assertEqual([c["category"]["name"] for c in self.summary()["by_category"]], ["Аренда"])

    def test_another_business_gets_a_404(self):
        self.assertEqual(self.w.b_api.get(f"{self.w.base}/expenses/summary/").status_code, 404)


class ExpenseConcurrencyTests(PrivateFilesMixin, APITransactionTestCase):
    def test_two_simultaneous_voids_make_exactly_one_void(self):
        w = World()
        category = ExpenseCategory.objects.create(business=w.a, name="Аренда")
        body = (
            w.api[Role.OWNER]
            .post(
                f"{w.base}/expenses/",
                {
                    "category": str(category.pk),
                    "location": str(w.store.pk),
                    "amount": "10",
                    "spent_on": w.a.local_today().isoformat(),
                },
                format="json",
            )
            .json()
        )
        barrier = threading.Barrier(2)

        def attempt(reason):
            try:
                barrier.wait(timeout=10)
                return client_for(w.owner).post(
                    f"{w.base}/expenses/{body['id']}/void/", {"reason": reason}, format="json"
                )
            finally:
                connections.close_all()

        with ThreadPoolExecutor(max_workers=2) as pool:
            responses = list(pool.map(attempt, ["first", "second"]))
        self.assertEqual(sorted(r.status_code for r in responses), [200, 409])
        self.assertEqual(AuditEvent.objects.filter(action="expense.voided").count(), 1)
        winner = "first" if responses[0].status_code == 200 else "second"
        self.assertEqual(Expense.objects.get(pk=body["id"]).void_reason, winner)
