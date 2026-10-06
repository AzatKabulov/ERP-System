import os
from io import StringIO
from unittest import mock

from django.core.management import CommandError, call_command

from apps.accounts.models import User
from apps.businesses.models import Business, Membership, Role
from apps.common.testing import PASSWORD, APITestCase


class CreateBusinessCommandTests(APITestCase):
    def run_command(self, **extra):
        args = {
            "name": "Täze Dükan",
            "owner_username": "boss",
            "owner_email": "boss@example.test",
            "location": "Esasy dükan",
            **extra,
        }
        out = StringIO()
        with mock.patch.dict(os.environ, {"ERP_OWNER_PASSWORD": PASSWORD}):
            call_command("create_business", stdout=out, **args)
        return out.getvalue()

    def test_creates_business_owner_and_first_location(self):
        self.run_command()
        business = Business.objects.get(name="Täze Dükan")
        self.assertEqual(business.currency, "TMT")
        self.assertEqual(list(business.locations.values_list("name", flat=True)), ["Esasy dükan"])
        membership = Membership.objects.get(business=business)
        self.assertEqual((membership.role, membership.user.username), (Role.OWNER, "boss"))
        self.assertTrue(User.objects.get(username="boss").check_password(PASSWORD))

    def test_weak_password_is_refused_and_nothing_is_created(self):
        with mock.patch.dict(os.environ, {"ERP_OWNER_PASSWORD": "short"}):
            with self.assertRaises(CommandError):
                call_command(
                    "create_business",
                    name="X",
                    owner_username="boss",
                    owner_email="b@example.test",
                    stdout=StringIO(),
                )
        self.assertFalse(Business.objects.exists())


class CreateSampleBusinessCommandTests(APITestCase):
    def test_creates_one_user_per_role_with_the_given_password(self):
        with mock.patch.dict(os.environ, {"ERP_SAMPLE_PASSWORD": PASSWORD}):
            call_command("create_sample_business", stdout=StringIO())
        business = Business.objects.get(name="Sample Auto Parts (test data)")
        roles = {m.user.username: m.role for m in Membership.objects.filter(business=business)}
        self.assertEqual(
            roles,
            {"owner": "owner", "manager": "manager", "sales": "sales", "warehouse": "warehouse"},
        )
        self.assertTrue(User.objects.get(username="sales").check_password(PASSWORD))
        self.assertEqual(business.locations.count(), 2)
        with self.assertRaises(CommandError):  # second run
            call_command("create_sample_business", stdout=StringIO())

    def test_random_password_is_printed_once_when_none_is_given(self):
        out = StringIO()
        with mock.patch.dict(os.environ, {}, clear=False):
            os.environ.pop("ERP_SAMPLE_PASSWORD", None)
            call_command("create_sample_business", stdout=out)
        self.assertIn("shown once", out.getvalue())

    def test_refuses_to_run_in_production(self):
        with self.settings(DJANGO_ENV="production"):
            with self.assertRaises(CommandError):
                call_command("create_sample_business", stdout=StringIO())
        self.assertFalse(Business.objects.exists())
