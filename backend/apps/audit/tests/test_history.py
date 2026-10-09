"""The activity history: who may read it, what it shows, and that it never shows another
business's events."""

from datetime import datetime
from urllib.parse import parse_qs, urlparse
from zoneinfo import ZoneInfo

from rest_framework.test import APIClient

from apps.audit.models import AuditEvent
from apps.businesses.models import Role
from apps.common.testing import APITestCase
from apps.inventory.tests.support import World

ZONE = ZoneInfo("Asia/Ashgabat")  # UTC+5, the business time zone in these tests


class HistoryCase(APITestCase):
    def setUp(self):
        super().setUp()
        self.w = World()
        self.owner = self.w.api[Role.OWNER]
        self.url = f"{self.w.base}/audit/"

    def event(
        self,
        action,
        *,
        business=None,
        actor=None,
        when="2026-10-02T12:00",
        object_type="",
        object_id="",
        metadata=None,
        **extra,
    ):
        """An event at a LOCAL time (Ashgabat); `business` defaults to business A."""
        return AuditEvent.objects.create(
            action=action,
            business=self.w.a if business is None else business,
            actor=actor,
            object_type=object_type,
            object_id=object_id,
            metadata=metadata or {},
            created_at=datetime.fromisoformat(when).replace(tzinfo=ZONE),
            **extra,
        )

    def listing(self, client=None, **params):
        response = (client or self.owner).get(self.url, params)
        self.assertEqual(response.status_code, 200, response.content)
        return response.json()

    def actions(self, **params):
        return [e["action"] for e in self.listing(**params)["results"]]


class ShapeTests(HistoryCase):
    def test_an_event_has_exactly_the_documented_fields(self):
        seller = self.w.users[Role.SALES]
        made = self.event(
            "sale.completed",
            actor=seller,
            object_type="Sale",
            object_id="abc-123",
            metadata={"number": 7, "total": "362.50"},
            request_id="internal-trace-id",
        )
        body = self.listing()
        self.assertEqual(body["count"], 1)
        self.assertEqual((body["next"], body["previous"]), (None, None))
        self.assertEqual(
            body["results"],
            [
                {
                    "id": str(made.pk),
                    "action": "sale.completed",
                    "object_type": "Sale",
                    "object_id": "abc-123",
                    "actor": {"id": str(seller.pk), "name": "a-sales"},
                    "created_at": "2026-10-02T07:00:00Z",
                    "metadata": {"number": 7, "total": "362.50"},
                }
            ],
        )
        self.assertNotIn("request_id", str(body))
        self.assertNotIn("internal-trace-id", str(body))

    def test_the_name_is_the_full_name_when_there_is_one_and_a_system_event_has_no_actor(self):
        seller = self.w.users[Role.SALES]
        seller.full_name = "Aýna Gurbanowa"
        seller.save()
        self.event("a.done", actor=seller)
        self.event("b.done", actor=None)
        by_action = {e["action"]: e for e in self.listing()["results"]}
        self.assertEqual(by_action["a.done"]["actor"]["name"], "Aýna Gurbanowa")
        self.assertIsNone(by_action["b.done"]["actor"])

    def test_newest_first(self):
        self.event("first", when="2026-10-01T09:00")
        self.event("third", when="2026-10-03T09:00")
        self.event("second", when="2026-10-02T09:00")
        self.assertEqual(self.actions(), ["third", "second", "first"])

    def test_an_empty_history_is_an_empty_page(self):
        body = self.listing()
        self.assertEqual(body, {"count": 0, "next": None, "previous": None, "results": []})


class IsolationTests(HistoryCase):
    def test_only_this_business_appears(self):
        self.event("mine.done", metadata={"note": "visible"})
        self.event("theirs.done", business=self.w.b, metadata={"marker": "B-SECRET"})
        AuditEvent.objects.create(
            action="auth.login", business=None, actor=self.w.users[Role.OWNER]
        )  # belongs to no business
        body = self.listing()
        self.assertEqual([e["action"] for e in body["results"]], ["mine.done"])
        self.assertEqual(body["count"], 1)
        self.assertNotIn("B-SECRET", str(body))
        self.assertNotIn("auth.login", str(body))

    def test_every_filter_stays_inside_the_business(self):
        theirs_actor = self.w.b_owner
        self.event("sale.completed", business=self.w.b, actor=theirs_actor)
        self.assertEqual(self.actions(actor=theirs_actor.pk), [])
        self.assertEqual(self.actions(action="sale"), [])
        self.assertEqual(self.actions(q="sale"), [])
        self.assertEqual(self.listing()["count"], 0)

    def test_the_action_list_is_this_businesss_only(self):
        self.event("zeta.done")
        self.event("alpha.done")
        self.event("alpha.done", when="2026-10-03T12:00")
        self.event("secret.b_only", business=self.w.b)
        AuditEvent.objects.create(action="auth.login", business=None)
        response = self.owner.get(f"{self.url}actions/")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json(), {"actions": ["alpha.done", "zeta.done"]})

    def test_a_member_of_another_business_gets_a_404(self):
        self.event("mine.done")
        for url in (self.url, f"{self.url}actions/"):
            response = self.w.b_api.get(url)
            self.assertEqual(response.status_code, 404)
            self.assertEqual(response.json()["error"]["code"], "not_found")
        theirs = self.owner.get(f"/api/v1/businesses/{self.w.b.pk}/audit/")
        self.assertEqual(theirs.status_code, 404)


class FilterTests(HistoryCase):
    def test_the_days_are_days_in_the_business_zone(self):
        # 19:30 UTC on 1 October is 00:30 on 2 October in Ashgabat
        self.event("late.night", when="2026-10-02T00:30")
        self.event("end.of.day", when="2026-10-02T23:59")
        self.event("next.day", when="2026-10-03T00:00")
        self.event("day.before", when="2026-10-01T23:59")
        self.assertEqual(
            self.actions(date_from="2026-10-02", date_to="2026-10-02"),
            ["end.of.day", "late.night"],
        )
        self.assertEqual(self.actions(date_to="2026-10-01"), ["day.before"])
        self.assertEqual(self.actions(date_from="2026-10-03"), ["next.day"])
        self.assertEqual(
            self.actions(date_from="2026-10-02"), ["next.day", "end.of.day", "late.night"]
        )

    def test_a_bad_date_names_the_field(self):
        for name in ("date_from", "date_to"):
            for value in ("yesterday", "2026-13-01", "02.10.2026"):
                with self.subTest(name=name, value=value):
                    response = self.owner.get(self.url, {name: value})
                    self.assertEqual(response.status_code, 400)
                    error = response.json()["error"]
                    self.assertEqual(error["code"], "validation_error")
                    self.assertEqual(error["fields"][name][0]["code"], "invalid")

    def test_by_actor(self):
        seller, keeper = self.w.users[Role.SALES], self.w.users[Role.WAREHOUSE]
        self.event("a.done", actor=seller)
        self.event("b.done", actor=keeper)
        self.event("c.done", actor=seller, when="2026-10-03T12:00")
        self.assertEqual(self.actions(actor=seller.pk), ["c.done", "a.done"])
        self.assertEqual(self.actions(actor=keeper.pk), ["b.done"])
        bad = self.owner.get(self.url, {"actor": "not-an-id"})
        self.assertEqual(bad.status_code, 400)
        self.assertIn("actor", bad.json()["error"]["fields"])

    def test_an_action_matches_exactly_or_as_a_prefix_up_to_a_dot(self):
        for action in (
            "sale.completed",
            "sale.returned",
            "sale",
            "salesperson.hired",
            "purchase_order.sale.note",
            "sale_x.done",
        ):
            self.event(action, when=f"2026-10-02T{10 + len(action) % 10}:00")
        self.assertEqual(
            set(self.actions(action="sale")), {"sale", "sale.completed", "sale.returned"}
        )
        self.assertEqual(self.actions(action="sale.completed"), ["sale.completed"])
        self.assertEqual(self.actions(action="sal"), [])  # not a prefix at a dot
        self.assertEqual(self.actions(action="sale."), [])
        # LIKE wildcards in the value are plain characters
        self.assertEqual(self.actions(action="sale%"), [])
        self.assertEqual(self.actions(action="s_le"), [])

    def test_text_search_covers_action_type_and_id_without_regard_to_case(self):
        at = "2026-10-02T{}:00".format
        self.event("expense.created", object_type="Expense", object_id="11-aaaa", when=at(10))
        self.event("sale.completed", object_type="Sale", object_id="22222222-BBBB", when=at(11))
        self.event("note", metadata={"text": "sale in the metadata"}, when=at(12))
        self.assertEqual(self.actions(q="EXPENSE"), ["expense.created"])
        self.assertEqual(self.actions(q="sale"), ["sale.completed"])  # action and type
        self.assertEqual(self.actions(q="bbbb"), ["sale.completed"])  # the object id
        self.assertEqual(self.actions(q="22222222-bb"), ["sale.completed"])
        self.assertEqual(self.actions(q=""), ["note", "sale.completed", "expense.created"])
        self.assertEqual(self.actions(q="nothing like it"), [])

    def test_filters_combine(self):
        seller = self.w.users[Role.SALES]
        self.event("sale.completed", actor=seller, when="2026-10-01T10:00")
        self.event("sale.completed", actor=seller, when="2026-10-02T10:00")
        self.event("sale.returned", actor=seller, when="2026-10-02T11:00")
        self.event("sale.completed", actor=self.w.users[Role.OWNER], when="2026-10-02T12:00")
        self.assertEqual(
            self.actions(
                actor=seller.pk, action="sale.completed", date_from="2026-10-02", q="sale"
            ),
            ["sale.completed"],
        )


class PaginationTests(HistoryCase):
    def setUp(self):
        super().setUp()
        AuditEvent.objects.bulk_create(
            [
                AuditEvent(
                    action=f"bulk.{n:03d}",
                    business=self.w.a,
                    created_at=datetime(2026, 10, 2, 0, 0, tzinfo=ZONE).replace(
                        minute=n % 60, hour=n // 60
                    ),
                )
                for n in range(120)
            ]
        )

    def test_fifty_by_default_with_links_and_a_total(self):
        body = self.listing()
        self.assertEqual((body["count"], len(body["results"])), (120, 50))
        self.assertEqual(body["results"][0]["action"], "bulk.119")
        self.assertIsNone(body["previous"])
        self.assertEqual(parse_qs(urlparse(body["next"]).query)["offset"], ["50"])

    def test_limit_and_offset(self):
        page = self.listing(limit=10, offset=30)
        self.assertEqual(
            [e["action"] for e in page["results"]], [f"bulk.{n:03d}" for n in range(89, 79, -1)]
        )
        self.assertIsNotNone(page["previous"])
        last = self.listing(limit=100, offset=100)
        self.assertEqual(len(last["results"]), 20)
        self.assertIsNone(last["next"])

    def test_a_limit_above_one_hundred_is_a_limit_of_one_hundred(self):
        self.assertEqual(len(self.listing(limit=100)["results"]), 100)
        self.assertEqual(len(self.listing(limit=1000)["results"]), 100)

    def test_walking_the_pages_gives_every_event_once(self):
        seen = []
        url = f"{self.url}?limit=40"
        while url:
            response = self.owner.get(url)
            body = response.json()
            seen += [e["id"] for e in body["results"]]
            url = body["next"]
        self.assertEqual(len(seen), 120)
        self.assertEqual(len(set(seen)), 120)


class RoleTests(HistoryCase):
    def test_owner_and_manager_read_it_seller_and_keeper_do_not(self):
        self.event("sale.completed")
        for role, status in (
            (Role.OWNER, 200),
            (Role.MANAGER, 200),
            (Role.SALES, 403),
            (Role.WAREHOUSE, 403),
        ):
            for url in (self.url, f"{self.url}actions/"):
                with self.subTest(role=role, url=url):
                    response = self.w.api[role].get(url)
                    self.assertEqual(response.status_code, status)
                    if status == 403:
                        self.assertEqual(response.json()["error"]["code"], "permission_denied")

    def test_anonymous_and_writes(self):
        self.assertEqual(APIClient().get(self.url).status_code, 401)
        for method in ("post", "put", "patch", "delete"):
            with self.subTest(method=method):
                self.assertEqual(getattr(self.owner, method)(self.url, {}).status_code, 405)
