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
