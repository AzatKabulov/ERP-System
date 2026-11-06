"""What a store experiences: the gate in front of its API, the status in /me/, the support desk."""

from datetime import timedelta

from django.utils import timezone

from apps.billing.models import Announcement, Client, SupportRequest
from apps.businesses.models import Role
from apps.common.testing import APITestCase, client_for, make_business, make_member

ME = "/api/v1/me/"


def lapse(business, *, days_from_now, override=""):
    """Give the store a subscription that ends `days_from_now` days from now (negative: ended)."""
    Client.objects.update_or_create(
        business=business,
        defaults={
            "paid_until": timezone.now() + timedelta(days=days_from_now),
            "override": override,
        },
    )


class GateTests(APITestCase):
    def setUp(self):
        super().setUp()
        self.a = make_business("Shop A")
        self.b = make_business("Shop B")
        self.owner = client_for(make_member(self.a, Role.OWNER, username="owner-a"))
        self.owner_b = client_for(make_member(self.b, Role.OWNER, username="owner-b"))
        self.units = f"/api/v1/businesses/{self.a.pk}/units/"
        self.categories = f"/api/v1/businesses/{self.a.pk}/categories/"
        self.export = f"/api/v1/businesses/{self.a.pk}/catalog/export/"

    def write(self, name="Fasteners"):
        return self.owner.post(self.categories, {"name": name}, format="json")

    def test_a_paid_store_works_normally(self):
        lapse(self.a, days_from_now=30)
        self.assertEqual(self.owner.get(self.units).status_code, 200)
        self.assertEqual(self.write().status_code, 201)

    def test_a_week_left_still_works_fully(self):
        lapse(self.a, days_from_now=3)
        self.assertEqual(self.write().status_code, 201)

    def test_the_grace_days_keep_everything_working(self):
        lapse(self.a, days_from_now=-3)
        self.assertEqual(self.write().status_code, 201)

    def test_after_the_grace_days_the_store_can_look_and_export_but_not_change(self):
        lapse(self.a, days_from_now=-20)
        self.assertEqual(self.owner.get(self.units).status_code, 200)
        self.assertEqual(self.owner.get(self.export).status_code, 200)
        for method, url in (
            ("post", self.categories),
            ("patch", f"{self.categories}00000000-0000-0000-0000-000000000000/"),
            ("delete", f"{self.categories}00000000-0000-0000-0000-000000000000/"),
        ):
            with self.subTest(method=method):
                response = getattr(self.owner, method)(url, {"name": "x"}, format="json")
                self.assertEqual(response.status_code, 402, response.content)
                self.assertEqual(response.json()["error"]["code"], "subscription_expired")

    def test_a_suspended_store_cannot_even_look(self):
        lapse(self.a, days_from_now=30, override="suspended")
        for response in (self.owner.get(self.units), self.write()):
            self.assertEqual(response.status_code, 402)
            self.assertEqual(response.json()["error"]["code"], "subscription_suspended")

    def test_free_access_never_stops(self):
        lapse(self.a, days_from_now=-400, override="free")
        self.assertEqual(self.write().status_code, 201)

    def test_a_store_we_never_set_up_billing_for_keeps_working(self):
        self.assertFalse(Client.objects.filter(business=self.a).exists())
        self.assertEqual(self.write().status_code, 201)

    def test_one_stores_lapse_never_touches_another(self):
        lapse(self.a, days_from_now=-90, override="suspended")
        lapse(self.b, days_from_now=30)
        self.assertEqual(self.owner.get(self.units).status_code, 402)
        self.assertEqual(
            self.owner_b.get(f"/api/v1/businesses/{self.b.pk}/units/").status_code, 200
        )
        self.assertEqual(
            self.owner_b.post(
                f"/api/v1/businesses/{self.b.pk}/categories/", {"name": "Parts"}, format="json"
            ).status_code,
            201,
        )

    def test_a_stranger_gets_404_even_from_a_lapsed_store(self):
        lapse(self.a, days_from_now=-90, override="suspended")
        self.assertEqual(self.owner_b.get(self.units).status_code, 404)

    def test_renewing_restores_everything(self):
        lapse(self.a, days_from_now=-20)
        self.assertEqual(self.write().status_code, 402)
        lapse(self.a, days_from_now=30)
        self.assertEqual(self.write().status_code, 201)


class MeTests(APITestCase):
    def setUp(self):
        super().setUp()
        self.business = make_business("Shop")
        store = self.business.locations.get()
        self.owner = client_for(make_member(self.business, Role.OWNER, username="own"))
        self.manager = client_for(make_member(self.business, Role.MANAGER, username="mgr"))
        self.sales = client_for(
            make_member(self.business, Role.SALES, username="sel", locations=[store])
        )

    def subscription(self, who):
        return who.get(ME).json()["memberships"][0]["subscription"]

    def test_owner_and_manager_see_the_dates_and_days_left(self):
        lapse(self.business, days_from_now=30)
        for who in (self.owner, self.manager):
            data = self.subscription(who)
            self.assertEqual(data["state"], "active")
            self.assertIn(data["days_left"], (29, 30))
            self.assertIsNotNone(data["ends_at"])

    def test_the_banner_states(self):
        for days, state in ((3, "expiring"), (-2, "grace"), (-30, "read_only")):
            with self.subTest(state=state):
                lapse(self.business, days_from_now=days)
                self.assertEqual(self.subscription(self.owner)["state"], state)

    def test_sellers_learn_nothing_until_work_is_blocked(self):
        lapse(self.business, days_from_now=3)
        self.assertIsNone(self.subscription(self.sales))
        lapse(self.business, days_from_now=-2)
        self.assertIsNone(self.subscription(self.sales))
        lapse(self.business, days_from_now=-30)
        self.assertEqual(self.subscription(self.sales), {"state": "read_only"})

    def test_a_suspended_user_can_still_ask_who_they_are(self):
        lapse(self.business, days_from_now=30, override="suspended")
        self.assertEqual(self.owner.get(ME).status_code, 200)
        self.assertEqual(self.subscription(self.owner)["state"], "suspended")

    def test_announcements_in_the_users_language(self):
        now = timezone.now()
        Announcement.objects.create(
            message_ru="Работы сегодня в 23:00",
            message_tk="Işler şu gün 23:00",
            starts_at=now - timedelta(hours=1),
            ends_at=now + timedelta(hours=5),
        )
        Announcement.objects.create(
            message_ru="old", starts_at=now - timedelta(days=3), ends_at=now - timedelta(days=2)
        )
        Announcement.objects.create(
            message_ru="off",
            starts_at=now - timedelta(hours=1),
            ends_at=now + timedelta(hours=5),
            is_active=False,
        )
        data = self.owner.get(ME).json()
        self.assertEqual([a["message"] for a in data["announcements"]], ["Работы сегодня в 23:00"])


class SupportTests(APITestCase):
    def setUp(self):
        super().setUp()
        self.a = make_business("Shop A")
        self.b = make_business("Shop B")
        store = self.a.locations.get()
        self.owner = client_for(make_member(self.a, Role.OWNER, username="owner-a"))
        self.manager = client_for(make_member(self.a, Role.MANAGER, username="manager-a"))
        self.sales = client_for(
            make_member(self.a, Role.SALES, username="sales-a", locations=[store])
        )
        self.owner_b = client_for(make_member(self.b, Role.OWNER, username="owner-b"))
        self.url = f"/api/v1/businesses/{self.a.pk}/support/"

    def ask(self, who=None, subject="Printer", body="It does not print"):
        return (who or self.owner).post(
            self.url,
            {"subject": subject, "body": body, "screen": "sales", "app_version": "1.0"},
            format="json",
        )

    def test_the_owner_writes_to_us_and_sees_the_conversation(self):
        response = self.ask()
        self.assertEqual(response.status_code, 201, response.content)
        data = response.json()
        self.assertEqual((data["subject"], data["status"]), ("Printer", "open"))
        self.assertEqual([m["from_store"] for m in data["messages"]], [True])
        listed = self.owner.get(self.url).json()["results"]
        self.assertEqual([r["subject"] for r in listed], ["Printer"])

    def test_a_manager_may_but_a_seller_may_not(self):
        self.assertEqual(self.ask(self.manager).status_code, 201)
        self.assertEqual(self.ask(self.sales).status_code, 403)
        self.assertEqual(self.sales.get(self.url).status_code, 403)

    def test_it_works_even_when_the_subscription_has_ended(self):
        for override, days in (("", -40), ("suspended", 30)):
            with self.subTest(override=override):
                lapse(self.a, days_from_now=days, override=override)
                self.assertEqual(self.ask().status_code, 201)
                self.assertEqual(self.owner.get(self.url).status_code, 200)

    def test_follow_ups_reopen_the_request_and_closed_ones_stay_closed(self):
        ticket = SupportRequest.objects.get(pk=self.ask().json()["id"])
        ticket.status = "answered"
        ticket.save()
        reply = f"{self.url}{ticket.pk}/messages/"
        self.assertEqual(
            self.owner.post(reply, {"body": "Still broken"}, format="json").status_code, 201
        )
        ticket.refresh_from_db()
        self.assertEqual(ticket.status, "open")
        self.assertEqual(ticket.messages.count(), 2)
        ticket.status = "closed"
        ticket.save()
        closed = self.owner.post(reply, {"body": "Hello?"}, format="json")
        self.assertEqual(
            (closed.status_code, closed.json()["error"]["code"]), (409, "support_closed")
        )

    def test_another_store_cannot_read_or_answer_it(self):
        ticket = SupportRequest.objects.get(pk=self.ask().json()["id"])
        self.assertEqual(self.owner_b.get(self.url).status_code, 404)
        other_url = f"/api/v1/businesses/{self.b.pk}/support/"
        self.assertEqual(self.owner_b.get(other_url).json()["results"], [])
        self.assertEqual(
            self.owner_b.post(
                f"{other_url}{ticket.pk}/messages/", {"body": "mine now"}, format="json"
            ).status_code,
            404,
        )

    def test_empty_and_oversized_messages_are_refused(self):
        self.assertEqual(self.ask(subject="", body="x").status_code, 400)
        self.assertEqual(self.ask(body="").status_code, 400)
        self.assertEqual(self.ask(body="x" * 4001).status_code, 400)
