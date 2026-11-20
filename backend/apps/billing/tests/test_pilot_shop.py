from datetime import timedelta
from io import StringIO
from unittest.mock import patch
from zoneinfo import ZoneInfo

from django.core.management import call_command
from django.core.management.base import CommandError
from django.utils import timezone
from rest_framework.test import APIClient

from apps.accounts.models import User
from apps.billing.models import Client, SubscriptionEvent
from apps.businesses.models import Business, Membership, Role
from apps.catalog.models import Product
from apps.common.testing import PASSWORD, APITestCase, make_business, make_member
from apps.inventory.models import StockMovement


class PilotShopTests(APITestCase):
    def provision(self, **extra):
        output = StringIO()
        with patch.dict("os.environ", {"ERP_PILOT_PASSWORD": PASSWORD}):
            call_command(
                "create_pilot_shop",
                username="pilot-owner",
                shop_name="Пилот ÄŇŞ",
                stdout=output,
                **extra,
            )
        return output.getvalue()

    def test_empty_week_pilot_signs_in_without_code_or_password_change_and_is_isolated(self):
        other = make_business("Existing shop")
        make_member(other, Role.OWNER)
        output = self.provision()
        user = User.objects.get(username="pilot-owner")
        member = Membership.objects.get(user=user)
        self.assertFalse(user.is_staff)
        self.assertFalse(user.is_superuser)
        self.assertFalse(user.must_change_password)
        self.assertEqual(member.role, Role.OWNER)
        self.assertEqual(member.business.locations.count(), 1)
        self.assertFalse(Product.objects.filter(business=member.business).exists())
        self.assertFalse(StockMovement.objects.filter(business=member.business).exists())
        subscription = Client.objects.get(business=member.business)
        self.assertTrue(subscription.is_trial)
        self.assertEqual(
            subscription.paid_until.date(),
            timezone.localdate(timezone.now(), ZoneInfo(member.business.timezone))
            + timedelta(days=7),
        )
        self.assertEqual(
            SubscriptionEvent.objects.filter(
                client=subscription, kind=SubscriptionEvent.Kind.TRIAL
            ).count(),
            1,
        )
        api = APIClient()
        response = api.post(
            "/api/v1/auth/login/", {"username": user.username, "password": PASSWORD}, format="json"
        )
        self.assertEqual(response.status_code, 200)
        api.credentials(HTTP_AUTHORIZATION="Bearer " + response.json()["access"])
        self.assertEqual(api.get(f"/api/v1/businesses/{other.pk}/products/").status_code, 404)
        self.assertEqual(api.get("/api/v1/platform/overview/").status_code, 403)
        self.assertEqual(
            api.get(f"/api/v1/businesses/{member.business_id}/products/").json()["count"], 0
        )
        self.assertNotIn(PASSWORD, output)

    def test_repeated_command_never_resets_or_replaces_an_account(self):
        self.provision()
        user = User.objects.get(username="pilot-owner")
        before = (user.password, Business.objects.count(), Client.objects.count())
        with self.assertRaises(CommandError):
            self.provision()
        user.refresh_from_db()
        self.assertEqual((user.password, Business.objects.count(), Client.objects.count()), before)

    def test_invalid_trial_duration_creates_nothing(self):
        for days in (0, 366):
            with self.assertRaises(CommandError):
                self.provision(days=days)
        self.assertFalse(User.objects.filter(username="pilot-owner").exists())
