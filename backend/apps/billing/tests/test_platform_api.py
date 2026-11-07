"""The platform owner's page in the app: who may open it, and that every button does what its
review says. A store's staff must get nothing from any of these routes."""

from datetime import timedelta

from django.test import override_settings
from django.utils import timezone
from django_otp.oath import TOTP
from django_otp.plugins.otp_totp.models import TOTPDevice
from rest_framework.test import APIClient

from apps.accounts.models import User
from apps.billing import services
from apps.billing.models import (
    Announcement,
    Client,
    ClientNote,
    Plan,
    SubscriptionEvent,
    SupportMessage,
    SupportRequest,
)
from apps.businesses.models import Role
from apps.common.testing import PASSWORD, APITestCase, client_for, make_business, make_member

LOGIN = "/api/v1/auth/login/"
ME = "/api/v1/me/"
P = "/api/v1/platform"


def make_operator(username="boss", authenticator=True):
    user = User.objects.create_superuser(username, "", PASSWORD)
    device = (
        TOTPDevice.objects.create(user=user, name="authenticator", confirmed=True)
        if authenticator
        else None
    )
    return user, device


def code_of(device):
    return str(TOTP(device.bin_key, device.step, device.t0, device.digits).token()).zfill(
        device.digits
    )


def sign_in(username, password=PASSWORD, **extra):
    return APIClient().post(
        LOGIN, {"username": username, "password": password, **extra}, format="json"
    )


class OperatorSignInTests(APITestCase):
    def test_a_stores_staff_sign_in_without_any_code_and_are_not_operators(self):
        make_member(make_business("Shop"), Role.OWNER, username="shop-owner")
        response = sign_in("shop-owner")
        self.assertEqual(response.status_code, 200)
        self.assertFalse(response.json()["user"]["is_platform_operator"])

    def test_an_operator_is_asked_for_the_code_after_the_password(self):
        make_operator()
        response = sign_in("boss")
        self.assertEqual(response.status_code, 401)
        self.assertEqual(response.json()["error"]["code"], "otp_required")
        self.assertNotIn("access", response.json())

    def test_a_wrong_code_is_refused(self):
        _, device = make_operator()
        wrong = "000000" if code_of(device) != "000000" else "111111"
        response = sign_in("boss", otp_token=wrong)
        self.assertEqual(response.status_code, 401)
        self.assertEqual(response.json()["error"]["code"], "invalid_otp")

    def test_a_wrong_password_never_reaches_the_code_step(self):
        make_operator()
        response = sign_in("boss", password="not-the-password-1")
        self.assertEqual(response.json()["error"]["code"], "invalid_credentials")

    def test_the_right_code_signs_in_and_the_profile_says_operator(self):
        _, device = make_operator()
        response = sign_in("boss", otp_token=code_of(device))
        self.assertEqual(response.status_code, 200, response.content)
        data = response.json()
        self.assertTrue(data["user"]["is_platform_operator"])
        me = client_for()
        me.credentials(HTTP_AUTHORIZATION=f"Bearer {data['access']}")
        body = me.get(ME).json()
        self.assertTrue(body["user"]["is_platform_operator"])
        self.assertEqual(body["memberships"], [])  # an operator works in no store

    def test_a_code_with_spaces_is_accepted(self):
        _, device = make_operator()
        token = code_of(device)
        response = sign_in("boss", otp_token=f"{token[:3]} {token[3:]}")
        self.assertEqual(response.status_code, 200)

    @override_settings(OTP_TOTP_THROTTLE_FACTOR=600)
    def test_guessing_codes_is_locked_out_even_for_the_right_one(self):
        _, device = make_operator()
        right = code_of(device)
        wrong = "000000" if right != "000000" else "111111"
        sign_in("boss", otp_token=wrong)
        response = sign_in("boss", otp_token=right)
        self.assertEqual(response.status_code, 429)
        self.assertEqual(response.json()["error"]["code"], "otp_locked")

    def test_an_operator_without_an_authenticator_cannot_sign_in_at_all(self):
        make_operator("keyless", authenticator=False)
        response = sign_in("keyless", otp_token="123456")
        self.assertEqual(response.status_code, 401)
        self.assertNotIn("access", response.json())


class AccessTests(APITestCase):
    def setUp(self):
        super().setUp()
        self.operator, _ = make_operator()
        self.shop = make_business("Shop")
        self.store_owner = make_member(self.shop, Role.OWNER, username="shop-owner")
        self.client_row, _pw = services.provision_client(
            store_name="Wonka", owner_username="wonka", actor=self.operator
        )
        ids = {
            "c": self.client_row.pk,
            "plan": Plan.objects.get(code="monthly").pk,
        }
        self.urls = [
            f"{P}/overview/",
            f"{P}/clients/",
            f"{P}/clients/{ids['c']}/",
            f"{P}/support/",
            f"{P}/announcements/",
            f"{P}/plans/",
        ]

    def test_a_visitor_gets_nothing(self):
        for url in self.urls:
            with self.subTest(url=url):
                self.assertEqual(APIClient().get(url).status_code, 401)

    def test_a_stores_staff_get_nothing_not_even_a_store_owner(self):
        api = client_for(self.store_owner)
        for url in self.urls:
            with self.subTest(url=url):
                self.assertEqual(api.get(url).status_code, 403)
        writes = (
            (f"{P}/clients/", {"store_name": "Mine"}),
            (
                f"{P}/clients/{self.client_row.pk}/actions/suspend/",
                {"note": "x", "step": "confirm"},
            ),
            (f"{P}/announcements/", {"message_ru": "x", "ends_at": "2999-01-01T00:00:00Z"}),
        )
        for url, body in writes:
            with self.subTest(url=url):
                self.assertEqual(api.post(url, body, format="json").status_code, 403)
        self.assertFalse(Client.objects.filter(business__name="Mine").exists())
        self.assertEqual(Client.objects.get(pk=self.client_row.pk).override, "")

    def test_a_staff_flag_without_an_authenticator_is_not_enough(self):
        keyless, _ = make_operator("keyless", authenticator=False)
        for url in self.urls:
            with self.subTest(url=url):
                self.assertEqual(client_for(keyless).get(url).status_code, 403)

    def test_an_operator_gets_in(self):
        api = client_for(self.operator)
        for url in self.urls:
            with self.subTest(url=url):
                self.assertEqual(api.get(url).status_code, 200)


class ClientsTests(APITestCase):
    def setUp(self):
        super().setUp()
        self.operator, _ = make_operator()
        self.api = client_for(self.operator)
        self.month = Plan.objects.get(code="monthly")
        today = timezone.localdate()
        self.trial, _ = services.provision_client(
            store_name="Trial Shop", owner_username="trial-shop", actor=self.operator
        )
        self.paid, _ = services.provision_client(
            store_name="Paid Shop",
            owner_username="paid-shop",
            plan=self.month,
            amount="150",
            currency="TMT",
            method="cash",
            actor=self.operator,
        )
        self.soon, _ = services.provision_client(
            store_name="Soon Shop", owner_username="soon-shop", plan=self.month, actor=self.operator
        )
        services.correct_end(self.soon, today + timedelta(days=3), self.operator, note="test")
        self.late, _ = services.provision_client(
            store_name="Late Shop", owner_username="late-shop", plan=self.month, actor=self.operator
        )
        services.correct_end(self.late, today - timedelta(days=2), self.operator, note="test")

    def names(self, response):
        return [r["store_name"] for r in response.json()["results"]]

    def test_the_list_shows_every_client_soonest_ending_first(self):
        response = self.api.get(f"{P}/clients/")
        self.assertEqual(response.status_code, 200)
        names = self.names(response)
        self.assertEqual(names[0], "Late Shop")
        self.assertEqual(names[1], "Soon Shop")
        self.assertEqual(set(names), {"Late Shop", "Soon Shop", "Trial Shop", "Paid Shop"})

    def test_a_row_carries_what_the_list_needs(self):
        rows = {r["store_name"]: r for r in self.api.get(f"{P}/clients/").json()["results"]}
        late, paid, trial = rows["Late Shop"], rows["Paid Shop"], rows["Trial Shop"]
        self.assertEqual(late["state"], "grace")
        self.assertEqual(rows["Soon Shop"]["state"], "expiring")
        self.assertEqual(paid["state"], "active")
        self.assertEqual(paid["owner_login"], "paid-shop")
        self.assertEqual(paid["plan"], self.month.name)
        self.assertIsNotNone(paid["last_payment_at"])
        self.assertTrue(trial["is_trial"])

    def test_filter_by_state_and_search(self):
        self.assertEqual(self.names(self.api.get(f"{P}/clients/?state=grace")), ["Late Shop"])
        attention = self.names(self.api.get(f"{P}/clients/?state=attention"))
        self.assertEqual(set(attention), {"Late Shop", "Soon Shop"})
        self.assertEqual(self.names(self.api.get(f"{P}/clients/?state=trial")), ["Trial Shop"])
        self.assertEqual(self.names(self.api.get(f"{P}/clients/?q=paid")), ["Paid Shop"])
        self.assertEqual(self.names(self.api.get(f"{P}/clients/?q=nothing-like-this")), [])

    def test_the_overview_counts_and_lists_what_needs_attention(self):
        body = self.api.get(f"{P}/overview/").json()
        self.assertEqual(body["total"], 4)
        self.assertEqual(body["counts"]["grace"], 1)
        self.assertEqual(body["counts"]["expiring"], 1)
        self.assertEqual(body["counts"]["trial"], 1)
        self.assertEqual([r["store_name"] for r in body["attention"]], ["Late Shop", "Soon Shop"])
        self.assertEqual(body["income_this_month"], {"TMT": "150.00"})
        self.assertEqual(body["recent_payments"][0]["store_name"], "Paid Shop")

    def test_the_detail_has_history_people_and_flags(self):
        body = self.api.get(f"{P}/clients/{self.paid.pk}/").json()
        self.assertEqual(body["store_name"], "Paid Shop")
        kinds = [e["kind"] for e in body["events"]]
        self.assertIn("created", kinds)
        self.assertIn("renew", kinds)
        self.assertEqual([p["username"] for p in body["people"]], ["paid-shop"])
        self.assertFalse(body["suspended"])
        self.assertFalse(body["free"])

    def test_a_new_client_gets_a_store_an_owner_and_a_password_shown_once(self):
        response = self.api.post(
            f"{P}/clients/",
            {
                "store_name": "Willy Wonka",
                "owner_name": "Willy",
                "phone": "+993 65 000000",
                "language": "ru",
                "start": str(self.month.pk),
                "amount": "150",
                "currency": "TMT",
                "method": "cash",
            },
            format="json",
        )
        self.assertEqual(response.status_code, 201, response.content)
        body = response.json()
        self.assertEqual(body["login"], "willy-wonka")
        self.assertEqual(body["client"]["store_name"], "Willy Wonka")
        signed = sign_in(body["login"], body["password"])
        self.assertEqual(signed.status_code, 200)
        self.assertTrue(signed.json()["user"]["must_change_password"])
        # the password is not kept anywhere the next read could show it
        again = self.api.get(f"{P}/clients/{body['client']['id']}/").content.decode()
        self.assertNotIn(body["password"], again)

    def test_a_taken_login_is_explained_not_crashed(self):
        response = self.api.post(
            f"{P}/clients/",
            {"store_name": "Another", "owner_login": "paid-shop"},
            format="json",
        )
        self.assertEqual(response.status_code, 400)
        self.assertIn("owner_login", response.json()["error"]["fields"])

    def test_contact_details_can_be_corrected_and_a_note_added(self):
        url = f"{P}/clients/{self.paid.pk}/"
        body = self.api.patch(url, {"phone": "+993 61 111111", "name": "Mergen"}, format="json")
        self.assertEqual(body.status_code, 200)
        self.assertEqual(body.json()["contact"]["phone"], "+993 61 111111")
        note = self.api.post(f"{url}notes/", {"text": "called, pays Friday"}, format="json")
        self.assertEqual(note.status_code, 201)
        self.assertEqual(note.json()["notes"][0]["text"], "called, pays Friday")
        self.assertEqual(ClientNote.objects.filter(client=self.paid).count(), 1)


class ActionsTests(APITestCase):
    def setUp(self):
        super().setUp()
        self.operator, _ = make_operator()
        self.api = client_for(self.operator)
        self.month = Plan.objects.get(code="monthly")
        self.client_row, self.password = services.provision_client(
            store_name="Willy Wonka",
            owner_username="willy",
            plan=self.month,
            actor=self.operator,
        )
        owner = User.objects.get(username="willy")
        owner.must_change_password = False  # the store's own gate; not what these tests are about
        owner.save()
        self.owner = client_for(owner)
        self.units = f"/api/v1/businesses/{self.client_row.business_id}/units/"
        self.base = f"{P}/clients/{self.client_row.pk}/actions"

    def act(self, name, body, step="confirm"):
        return self.api.post(f"{self.base}/{name}/", {**body, "step": step}, format="json")

    def fresh(self):
        return Client.objects.get(pk=self.client_row.pk)

    def test_review_changes_nothing_and_says_what_will_happen(self):
        before = self.fresh().paid_until
        events = SubscriptionEvent.objects.count()
        response = self.act("renew", {"plan": str(self.month.pk)}, step="review")
        self.assertEqual(response.status_code, 200, response.content)
        body = response.json()
        self.assertEqual(body["step"], "review")
        self.assertGreater(len(body["lines"]), 1)
        self.assertGreater(body["preview"]["new_end"], before.date().isoformat())
        self.assertEqual(self.fresh().paid_until, before)
        self.assertEqual(SubscriptionEvent.objects.count(), events)

    def test_adding_a_package_moves_the_end_and_records_the_payment(self):
        before = self.fresh().paid_until
        response = self.act(
            "renew",
            {"plan": str(self.month.pk), "amount": "150", "currency": "TMT", "method": "cash"},
        )
        self.assertEqual(response.status_code, 200, response.content)
        self.assertGreater(self.fresh().paid_until, before)
        event = SubscriptionEvent.objects.filter(client=self.client_row, kind="renew").latest(
            "created_at"
        )
        self.assertEqual(str(event.amount), "150.00")
        self.assertEqual(event.actor, self.operator)
        self.assertEqual(response.json()["client"]["store_name"], "Willy Wonka")

    def test_custom_days_need_a_reason(self):
        missing = self.act("extend", {"days": 10})
        self.assertEqual(missing.status_code, 400)
        self.assertIn("note", missing.json()["error"]["fields"])
        before = self.fresh().paid_until
        done = self.act("extend", {"days": 10, "note": "will pay next week"})
        self.assertEqual(done.status_code, 200)
        self.assertEqual(self.fresh().paid_until - before, timedelta(days=10))

    def test_correcting_the_end_date(self):
        target = (timezone.localdate() + timedelta(days=2)).isoformat()
        self.assertEqual(self.act("correct", {"new_end": target}).status_code, 400)  # no reason
        done = self.act("correct", {"new_end": target, "note": "typo"})
        self.assertEqual(done.status_code, 200)
        self.assertEqual(done.json()["client"]["state"], "expiring")

    def test_suspending_cuts_the_store_off_and_resuming_restores_it(self):
        self.assertEqual(self.owner.get(self.units).status_code, 200)
        self.assertEqual(self.act("suspend", {}).status_code, 400)  # a reason is required
        done = self.act("suspend", {"note": "no payment"})
        self.assertEqual(done.status_code, 200)
        self.assertTrue(done.json()["client"]["suspended"])
        self.assertEqual(self.owner.get(self.units).status_code, 402)
        self.assertEqual(self.act("resume", {}).status_code, 200)
        self.assertEqual(self.owner.get(self.units).status_code, 200)

    def test_free_access_on_and_off(self):
        self.act("free-on", {"note": "partner shop"})
        self.assertTrue(self.fresh().override == "free")
        self.act("free-off", {"note": "partnership ended"})
        self.assertEqual(self.fresh().override, "")

    def test_resetting_the_owners_password_shows_the_new_one_once(self):
        response = self.act("reset-password", {})
        self.assertEqual(response.status_code, 200, response.content)
        secret = response.json()["secret"]
        self.assertTrue(secret)
        self.assertEqual(sign_in("willy", self.password).status_code, 401)
        signed = sign_in("willy", secret)
        self.assertEqual(signed.status_code, 200)
        self.assertTrue(signed.json()["user"]["must_change_password"])
        detail = self.api.get(f"{P}/clients/{self.client_row.pk}/").content.decode()
        self.assertNotIn(secret, detail)

    def test_an_unknown_action_is_not_found(self):
        self.assertEqual(self.act("delete-everything", {}).status_code, 404)

    def test_an_inactive_package_cannot_be_added(self):
        self.month.is_active = False
        self.month.save()
        self.assertEqual(self.act("renew", {"plan": str(self.month.pk)}).status_code, 400)


class SupportTests(APITestCase):
    def setUp(self):
        super().setUp()
        self.operator, _ = make_operator()
        self.api = client_for(self.operator)
        self.shop = make_business("Shop")
        self.staff = make_member(self.shop, Role.OWNER, username="shop-owner", full_name="Aman")
        self.ticket = SupportRequest.objects.create(
            business=self.shop, raised_by=self.staff, subject="Printer?", screen="sales"
        )
        SupportMessage.objects.create(
            request=self.ticket, from_store=True, author=self.staff, text="It does not print"
        )

    def test_the_list_puts_waiting_requests_first(self):
        closed = SupportRequest.objects.create(
            business=self.shop,
            raised_by=self.staff,
            subject="Old",
            status=SupportRequest.Status.CLOSED,
        )
        rows = self.api.get(f"{P}/support/").json()["results"]
        self.assertEqual([r["id"] for r in rows], [str(self.ticket.pk), str(closed.pk)])
        only_closed = self.api.get(f"{P}/support/?status=closed").json()["results"]
        self.assertEqual([r["id"] for r in only_closed], [str(closed.pk)])

    def test_replying_marks_it_answered_and_the_store_sees_the_answer(self):
        detail = self.api.get(f"{P}/support/{self.ticket.pk}/").json()
        self.assertEqual(detail["messages"][0]["text"], "It does not print")
        response = self.api.post(
            f"{P}/support/{self.ticket.pk}/reply/", {"text": "Try the other cable"}, format="json"
        )
        self.assertEqual(response.status_code, 201)
        self.assertEqual(response.json()["status"], "answered")
        store = client_for(self.staff).get(f"/api/v1/businesses/{self.shop.pk}/support/").json()
        texts = [m["text"] for m in store["results"][0]["messages"]]
        self.assertEqual(texts, ["It does not print", "Try the other cable"])

    def test_replying_and_closing_in_one_go_and_closing_alone(self):
        self.api.post(
            f"{P}/support/{self.ticket.pk}/reply/", {"text": "Done", "close": True}, format="json"
        )
        self.ticket.refresh_from_db()
        self.assertEqual(self.ticket.status, "closed")
        other = SupportRequest.objects.create(business=self.shop, raised_by=self.staff, subject="x")
        self.assertEqual(self.api.post(f"{P}/support/{other.pk}/close/").status_code, 200)
        other.refresh_from_db()
        self.assertEqual(other.status, "closed")


class NoticesAndPackagesTests(APITestCase):
    def setUp(self):
        super().setUp()
        self.operator, _ = make_operator()
        self.api = client_for(self.operator)
        self.shop = make_business("Shop")
        self.staff = client_for(make_member(self.shop, Role.OWNER, username="shop-owner"))

    def test_a_notice_reaches_every_store_until_it_is_switched_off(self):
        ends = (timezone.now() + timedelta(days=2)).isoformat()
        made = self.api.post(
            f"{P}/announcements/",
            {"message_ru": "Работы сегодня ночью", "message_tk": "Şu gije işler", "ends_at": ends},
            format="json",
        )
        self.assertEqual(made.status_code, 201, made.content)
        notices = self.staff.get(ME).json()["announcements"]
        self.assertEqual([n["message"] for n in notices], ["Работы сегодня ночью"])
        off = self.api.patch(
            f"{P}/announcements/{made.json()['id']}/", {"is_active": False}, format="json"
        )
        self.assertEqual(off.status_code, 200)
        self.assertEqual(self.staff.get(ME).json()["announcements"], [])
        self.assertEqual(len(self.api.get(f"{P}/announcements/").json()["results"]), 1)

    def test_a_notice_cannot_end_before_it_starts(self):
        start = timezone.now()
        response = self.api.post(
            f"{P}/announcements/",
            {
                "message_ru": "x",
                "starts_at": start.isoformat(),
                "ends_at": (start - timedelta(hours=1)).isoformat(),
            },
            format="json",
        )
        self.assertEqual(response.status_code, 400)
        self.assertEqual(Announcement.objects.count(), 0)

    def test_a_package_price_can_be_changed_and_a_package_switched_off(self):
        plan = Plan.objects.get(code="monthly")
        listed = self.api.get(f"{P}/plans/").json()["results"]
        self.assertIn("monthly", [p["code"] for p in listed])
        response = self.api.patch(f"{P}/plans/{plan.pk}/", {"price": "200"}, format="json")
        self.assertEqual(response.status_code, 200)
        plan.refresh_from_db()
        self.assertEqual(str(plan.price), "200.00")
        self.api.patch(f"{P}/plans/{plan.pk}/", {"is_active": False}, format="json")
        plan.refresh_from_db()
        self.assertFalse(plan.is_active)
        self.assertEqual(
            self.api.patch(f"{P}/plans/{plan.pk}/", {"price": "-5"}, format="json").status_code, 400
        )
