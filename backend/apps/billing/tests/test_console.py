"""The owner console: who may open it, and that its buttons do what the review page says."""

import re
from datetime import timedelta
from io import StringIO
from unittest import mock

from django.core.cache import cache
from django.core.management import call_command
from django.core.management.base import CommandError
from django.test import TestCase, override_settings
from django.utils import timezone
from django_otp import DEVICE_ID_SESSION_KEY
from django_otp.oath import TOTP
from django_otp.plugins.otp_totp.models import TOTPDevice

from apps.accounts.models import User
from apps.billing import services
from apps.billing.models import (
    Client,
    ClientNote,
    Plan,
    SubscriptionEvent,
    SupportMessage,
    SupportRequest,
)
from apps.businesses.models import Business, Membership, Role
from apps.common.testing import make_business, make_member, make_user

HOME = "/console/"

# The pages use {% static %}; the production storage needs `collectstatic` to have run.
plain_static = override_settings(
    STORAGES={
        "default": {"BACKEND": "django.core.files.storage.FileSystemStorage"},
        "staticfiles": {"BACKEND": "django.contrib.staticfiles.storage.StaticFilesStorage"},
    }
)


def operator_client(test, username="operator"):
    """A browser signed in to the console: password step done and authenticator code verified."""
    user = User.objects.create_superuser(username, "", "operator-password-1")
    device = TOTPDevice.objects.create(user=user, name="authenticator", confirmed=True)
    test.client.force_login(user)
    session = test.client.session
    session[DEVICE_ID_SESSION_KEY] = device.persistent_id
    session.save()
    return user


@plain_static
class WhoMayEnterTests(TestCase):
    def setUp(self):
        cache.clear()

    def test_a_visitor_is_sent_to_the_sign_in_page(self):
        response = self.client.get(HOME)
        self.assertEqual(response.status_code, 302)
        self.assertIn("/console/login/", response["Location"])

    def test_a_store_account_cannot_open_it_even_signed_in(self):
        business = make_business("Shop")
        owner = make_member(business, Role.OWNER, username="store-owner")
        self.client.force_login(owner)
        self.assertEqual(self.client.get(HOME).status_code, 302)
        self.assertEqual(self.client.get("/console/billing/client/").status_code, 302)

    def test_an_operator_without_the_authenticator_code_is_not_let_in(self):
        user = User.objects.create_superuser("operator-b", "", "operator-password-1")
        TOTPDevice.objects.create(user=user, name="authenticator", confirmed=True)
        self.client.force_login(user)  # password done, code not given
        self.assertEqual(self.client.get(HOME).status_code, 302)

    def test_a_verified_operator_gets_in(self):
        operator_client(self)
        self.assertEqual(self.client.get(HOME).status_code, 200)

    def _code(self, device):
        return str(TOTP(device.bin_key, device.step, device.t0, device.digits).token()).zfill(
            device.digits
        )

    def _operator_with_authenticator(self):
        user = User.objects.create_superuser("operator-c", "", "operator-password-1")
        device = TOTPDevice.objects.create(user=user, name="authenticator", confirmed=True)
        return device

    def test_an_operator_signs_in_with_password_and_code_without_choosing_a_device(self):
        device = self._operator_with_authenticator()
        response = self.client.post(
            "/console/login/",
            {
                "username": "operator-c",
                "password": "operator-password-1",
                "otp_token": self._code(device),
                "next": HOME,
            },
        )
        self.assertEqual(response.status_code, 302, response.content[:300])
        self.assertEqual(self.client.get(HOME).status_code, 200)

    def test_a_right_password_with_a_wrong_or_missing_code_is_not_let_in(self):
        device = self._operator_with_authenticator()
        wrong = "000000" if self._code(device) != "000000" else "111111"
        for code in (wrong, ""):
            with self.subTest(code=code):
                response = self.client.post(
                    "/console/login/",
                    {
                        "username": "operator-c",
                        "password": "operator-password-1",
                        "otp_token": code,
                        "next": HOME,
                    },
                )
                self.assertEqual(response.status_code, 200)  # the form again, with a message
                self.assertEqual(self.client.get(HOME).status_code, 302)

    def test_a_code_from_someone_else_s_authenticator_is_not_enough(self):
        mine = self._operator_with_authenticator()
        other = User.objects.create_superuser("operator-d", "", "operator-password-2")
        theirs = TOTPDevice.objects.create(user=other, name="authenticator", confirmed=True)
        self.assertNotEqual(self._code(mine), self._code(theirs))
        response = self.client.post(
            "/console/login/",
            {
                "username": "operator-c",
                "password": "operator-password-1",
                "otp_token": self._code(theirs),
                "next": HOME,
            },
        )
        self.assertEqual(response.status_code, 200)
        self.assertEqual(self.client.get(HOME).status_code, 302)

    def test_a_store_s_data_cannot_be_browsed_from_here(self):
        operator_client(self)
        for url in (
            "/console/sales/sale/",
            "/console/catalog/product/",
            "/console/inventory/stockbalance/",
            "/console/businesses/membership/",
            "/console/accounts/user/",
        ):
            with self.subTest(url=url):
                self.assertEqual(self.client.get(url).status_code, 404)

    def test_the_stock_admin_is_not_the_console(self):
        # In production only the console is mounted; here (development) the stock admin exists
        # too, but the console must not expose what it shows.
        operator_client(self)
        self.assertNotIn(
            "sale", self.client.get(HOME).content.decode().lower().split("<body")[1][:100]
        )

    def test_guessing_the_sign_in_is_slowed_down(self):
        statuses = [
            self.client.post("/console/login/", {"username": "x", "password": "y"}).status_code
            for _ in range(12)
        ]
        self.assertEqual(statuses[0], 200)
        self.assertEqual(statuses[-1], 429)


@plain_static
class ConsoleTestCase(TestCase):
    def setUp(self):
        cache.clear()
        self.operator = operator_client(self)
        self.client_row, _ = (
            services.provision_client(
                store_name="Willy Wonka",
                owner_username="willy-wonka",
                owner_name="Willy",
                phone="+993 65 000000",
                actor=self.operator,
            ),
            None,
        )
        self.client_row = self.client_row[0]
        self.monthly = Plan.objects.get(code="monthly")
        self.detail = f"/console/billing/client/{self.client_row.pk}/change/"

    def action(self, name, data, confirm=True):
        url = f"/console/billing/client/{self.client_row.pk}/do/{name}/"
        review = self.client.post(url, {**data, "step": "review"})
        if not confirm:
            return review
        self.assertEqual(review.status_code, 200, review.content[:300])
        return self.client.post(url, {**data, "step": "confirm"})


class DashboardTests(ConsoleTestCase):
    def test_front_page_counts_and_the_call_list(self):
        late = Client.objects.get(pk=self.client_row.pk)
        late.paid_until = timezone.now() - timedelta(days=3)  # grace days
        late.is_trial = False
        late.save()
        page = self.client.get(HOME).content.decode()
        self.assertIn("Who to call", page)
        self.assertIn("Willy Wonka", page)
        self.assertIn("+993 65 000000", page)

    def test_client_list_and_detail_open(self):
        self.assertIn("Willy Wonka", self.client.get("/console/billing/client/").content.decode())
        response = self.client.get(self.detail)
        self.assertEqual(response.status_code, 200)
        body = response.content.decode()
        self.assertIn("Add a package", body)
        self.assertIn("Reset the owner", body)

    def test_the_state_filter_uses_the_same_rules_as_the_badge(self):
        row = Client.objects.get(pk=self.client_row.pk)
        row.paid_until = timezone.now() - timedelta(days=30)
        row.save()

        def listed(state):
            return self.client.get(f"/console/billing/client/?state={state}").content.decode()

        self.assertIn("Willy Wonka", listed("read_only"))
        self.assertNotIn("Willy Wonka</b>", listed("active"))


class NewClientTests(ConsoleTestCase):
    def test_creating_a_client_shows_the_login_and_password_once(self):
        response = self.client.post(
            "/console/billing/client/add/",
            {
                "store_name": "Cash Shop",
                "language": "ru",
                "owner_name": "Aman",
                "currency": "TMT",
                "method": "cash",
            },
        )
        self.assertEqual(response.status_code, 200, response.content[:400])
        body = response.content.decode()
        login = re.search(r'Login: <span class="secret">([^<]+)</span>', body).group(1)
        password = re.search(
            r'Temporary password: <span class="secret">([^<]+)</span>', body
        ).group(1)
        self.assertEqual(login, "cash-shop")
        owner = User.objects.get(username="cash-shop")
        self.assertTrue(owner.check_password(password))
        self.assertTrue(owner.must_change_password)
        # not stored anywhere readable
        self.assertNotIn(
            password, str(list(SubscriptionEvent.objects.values_list("note", flat=True)))
        )

    def test_a_taken_login_is_explained_not_crashed(self):
        response = self.client.post(
            "/console/billing/client/add/",
            {
                "store_name": "Another",
                "owner_login": "willy-wonka",
                "language": "ru",
                "currency": "TMT",
            },
        )
        self.assertEqual(response.status_code, 200)
        self.assertIn("This login is taken", response.content.decode())
        self.assertFalse(Business.objects.filter(name="Another").exists())

    def test_starting_with_a_paid_package(self):
        self.client.post(
            "/console/billing/client/add/",
            {
                "store_name": "Prepaid",
                "language": "tk",
                "start": str(self.monthly.pk),
                "amount": "150",
                "currency": "TMT",
                "method": "cash",
            },
        )
        row = Client.objects.get(business__name="Prepaid")
        self.assertFalse(row.is_trial)
        self.assertEqual(row.events.get(kind="renew").amount, 150)


class ActionTests(ConsoleTestCase):
    def test_a_package_is_reviewed_before_it_is_applied(self):
        before = Client.objects.get(pk=self.client_row.pk).paid_until
        review = self.action(
            "renew",
            {"plan": str(self.monthly.pk), "amount": "100", "currency": "TMT", "method": "cash"},
            confirm=False,
        )
        self.assertIn("will end", review.content.decode())
        self.assertEqual(
            Client.objects.get(pk=self.client_row.pk).paid_until, before
        )  # nothing yet
        done = self.action(
            "renew",
            {"plan": str(self.monthly.pk), "amount": "100", "currency": "TMT", "method": "cash"},
        )
        self.assertEqual(done.status_code, 302)
        row = Client.objects.get(pk=self.client_row.pk)
        self.assertGreater(row.paid_until, before)
        self.assertFalse(row.is_trial)
        event = row.events.get(kind="renew")
        self.assertEqual((event.amount, event.method, event.actor), (100, "cash", self.operator))

    def test_custom_days_demand_a_reason(self):
        response = self.client.post(
            f"/console/billing/client/{self.client_row.pk}/do/extend/",
            {"days": "7", "note": "", "step": "review"},
        )
        self.assertEqual(response.status_code, 200)
        self.assertIn("This field is required", response.content.decode())
        self.assertFalse(
            Client.objects.get(pk=self.client_row.pk).events.filter(kind="extend").exists()
        )

    def test_custom_days(self):
        before = Client.objects.get(pk=self.client_row.pk).paid_until
        self.action("extend", {"days": "7", "note": "will pay next week", "currency": "TMT"})
        self.assertEqual(
            Client.objects.get(pk=self.client_row.pk).paid_until - before, timedelta(days=7)
        )

    def test_suspend_and_resume(self):
        self.action("suspend", {"note": "dispute"})
        self.assertEqual(Client.objects.get(pk=self.client_row.pk).override, "suspended")
        self.action("resume", {"note": ""})
        self.assertEqual(Client.objects.get(pk=self.client_row.pk).override, "")

    def test_reset_password_shows_it_once_and_forces_a_change(self):
        owner = Membership.objects.get(business=self.client_row.business, role=Role.OWNER).user
        response = self.action("reset-password", {})
        self.assertEqual(response.status_code, 200)
        password = re.search(r'class="secret">([^<]+)<', response.content.decode()).group(1)
        owner.refresh_from_db()
        self.assertTrue(owner.check_password(password))
        self.assertTrue(owner.must_change_password)
        # it is not in the history or the page that follows
        self.assertNotIn(password, self.client.get(self.detail).content.decode())

    def test_unknown_actions_go_back_to_the_list(self):
        response = self.client.get(f"/console/billing/client/{self.client_row.pk}/do/explode/")
        self.assertEqual(response.status_code, 302)

    def test_notes_and_contact_details(self):
        self.client.post(self.detail, {"which": "note", "note-text": "Called, pays Friday"})
        self.assertEqual(ClientNote.objects.get().author, self.operator)
        self.client.post(
            self.detail,
            {
                "which": "contact",
                "contact-contact_name": "Willy W.",
                "contact-contact_phone": "+993 1",
                "contact-contact_email": "",
            },
        )
        self.assertEqual(Client.objects.get(pk=self.client_row.pk).contact_name, "Willy W.")
        self.assertIn("Called, pays Friday", self.client.get(self.detail).content.decode())

    def test_history_cannot_be_changed_from_the_console(self):
        event = SubscriptionEvent.objects.first()
        url = f"/console/billing/subscriptionevent/{event.pk}/change/"
        self.assertEqual(self.client.post(url, {"note": "edited"}).status_code, 403)
        self.assertEqual(
            self.client.post(f"/console/billing/subscriptionevent/{event.pk}/delete/").status_code,
            403,
        )


class SupportDeskTests(ConsoleTestCase):
    def test_answering_a_request(self):
        owner = Membership.objects.get(business=self.client_row.business, role=Role.OWNER).user
        ticket = SupportRequest.objects.create(
            business=self.client_row.business, raised_by=owner, subject="Printer"
        )
        SupportMessage.objects.create(
            request=ticket, from_store=True, author=owner, text="It does not print"
        )
        page = self.client.get(f"/console/billing/supportrequest/{ticket.pk}/change/")
        self.assertIn("It does not print", page.content.decode())
        self.client.post(
            f"/console/billing/supportrequest/{ticket.pk}/change/", {"text": "Try the other cable"}
        )
        ticket.refresh_from_db()
        self.assertEqual(ticket.status, "answered")
        reply = ticket.messages.get(from_store=False)
        self.assertEqual((reply.author, reply.text), (self.operator, "Try the other cable"))


class CreateOperatorCommandTests(TestCase):
    def run_command(self, *args, password="operator-password-1"):
        out = StringIO()
        with mock.patch.dict("os.environ", {"ERP_OPERATOR_PASSWORD": password}):
            call_command("create_operator", *args, stdout=out)
        return out.getvalue()

    def test_creates_an_operator_with_an_authenticator_key(self):
        output = self.run_command("boss")
        user = User.objects.get(username="boss")
        self.assertTrue(user.is_staff and user.is_superuser)
        device = TOTPDevice.objects.get(user=user)
        self.assertTrue(device.confirmed)
        self.assertRegex(output, r"key:\s+[A-Z2-7]{20,}")

    def test_weak_passwords_are_refused(self):
        with self.assertRaises(CommandError):
            self.run_command("boss", password="short")
        self.assertFalse(User.objects.filter(username="boss").exists())

    def test_a_store_account_can_never_become_an_operator(self):
        make_user("store-person", email="s@example.test")
        with self.assertRaises(CommandError):
            self.run_command("store-person")
        self.assertFalse(User.objects.get(username="store-person").is_staff)

    def test_a_second_run_needs_new_key_and_replaces_the_old_one(self):
        self.run_command("boss")
        first = TOTPDevice.objects.get(user__username="boss").key
        with self.assertRaises(CommandError):
            self.run_command("boss")
        self.run_command("boss", "--new-key")
        self.assertNotEqual(TOTPDevice.objects.get(user__username="boss").key, first)
        self.assertEqual(TOTPDevice.objects.filter(user__username="boss").count(), 1)

    def test_an_operator_has_no_access_to_any_store(self):
        self.run_command("boss")
        business = make_business("Shop")
        make_member(business, Role.OWNER, username="owner-x")
        from rest_framework.test import APIClient

        client = APIClient()
        client.force_authenticate(User.objects.get(username="boss"))
        self.assertEqual(client.get(f"/api/v1/businesses/{business.pk}/").status_code, 404)
