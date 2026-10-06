from django.core import mail
from rest_framework.test import APIClient

from apps.audit.models import AuditEvent
from apps.businesses.models import Business, Location, Membership, Role
from apps.businesses.permissions import has_permission
from apps.common.testing import (
    PASSWORD,
    APITestCase,
    client_for,
    make_business,
    make_member,
    make_user,
)

ROLES = [Role.OWNER, Role.MANAGER, Role.SALES, Role.WAREHOUSE]


class World:
    """Two unrelated businesses, each with one user per role."""

    def __init__(self):
        self.a = make_business("Shop A", locations=("A Store", "A Warehouse"))
        self.b = make_business("Shop B", locations=("B Store",))
        self.a_store, self.a_wh = self.a.locations.order_by("name")
        self.b_store = self.b.locations.get()
        self.users = {}
        for tag, business in (("a", self.a), ("b", self.b)):
            for role in ROLES:
                restricted = role in (Role.SALES, Role.WAREHOUSE)
                first = business.locations.order_by("name").first()
                self.users[(tag, role)] = make_member(
                    business,
                    role,
                    username=f"{tag}-{role}",
                    locations=[first] if restricted else None,
                )

    def user(self, tag, role):
        return self.users[(tag, role)]

    def staff_id(self, business, role):
        return Membership.objects.get(business=business, role=role).pk


def endpoints(business, location, staff):
    base = f"/api/v1/businesses/{business.pk}"
    return [
        ("get", f"{base}/", "business.view"),
        ("patch", f"{base}/", "business.manage"),
        ("get", f"{base}/locations/", "location.view"),
        ("post", f"{base}/locations/", "location.manage"),
        ("get", f"{base}/locations/{location.pk}/", "location.view"),
        ("patch", f"{base}/locations/{location.pk}/", "location.manage"),
        ("get", f"{base}/staff/", "staff.view"),
        ("post", f"{base}/staff/", "staff.manage"),
        ("get", f"{base}/staff/{staff}/", "staff.view"),
        ("patch", f"{base}/staff/{staff}/", "staff.manage"),
        (
            "get",
            f"{base}/operations/anything/00000000-0000-4000-8000-000000000000/",
            "operations.view",
        ),
    ]


class IsolationTests(APITestCase):
    def setUp(self):
        super().setUp()
        self.w = World()

    def test_no_user_of_business_a_can_touch_business_b_in_any_role(self):
        b_staff = self.w.staff_id(self.w.b, Role.SALES)
        for role in ROLES:
            api = client_for(self.w.user("a", role))
            for method, url, _code in endpoints(self.w.b, self.w.b_store, b_staff):
                with self.subTest(role=role, method=method, url=url):
                    response = getattr(api, method)(url, {}, format="json")
                    # 404 (not 403): another business's existence is not revealed
                    self.assertEqual(response.status_code, 404, response.content)
                    self.assertEqual(response.json()["error"]["code"], "not_found")

    def test_unauthenticated_requests_are_rejected_everywhere(self):
        b_staff = self.w.staff_id(self.w.b, Role.SALES)
        for method, url, _code in endpoints(self.w.b, self.w.b_store, b_staff):
            with self.subTest(method=method, url=url):
                self.assertEqual(
                    getattr(APIClient(), method)(url, {}, format="json").status_code, 401
                )

    def test_ids_from_another_business_do_not_resolve_inside_my_business(self):
        owner = client_for(self.w.user("a", Role.OWNER))
        base = f"/api/v1/businesses/{self.w.a.pk}"
        self.assertEqual(owner.get(f"{base}/locations/{self.w.b_store.pk}/").status_code, 404)
        b_staff = self.w.staff_id(self.w.b, Role.OWNER)
        self.assertEqual(owner.get(f"{base}/staff/{b_staff}/").status_code, 404)
        self.assertEqual(
            owner.patch(f"{base}/staff/{b_staff}/", {"role": "sales"}, format="json").status_code,
            404,
        )

    def test_a_business_id_in_the_body_never_grants_access(self):
        owner = client_for(self.w.user("a", Role.OWNER))
        response = owner.patch(
            f"/api/v1/businesses/{self.w.a.pk}/",
            {"id": str(self.w.b.pk), "name": "Renamed"},
            format="json",
        )
        self.assertEqual(response.status_code, 200)
        self.w.a.refresh_from_db()
        self.w.b.refresh_from_db()
        self.assertEqual(self.w.a.name, "Renamed")
        self.assertEqual(self.w.b.name, "Shop B")

    def test_staff_cannot_be_given_locations_of_another_business(self):
        owner = client_for(self.w.user("a", Role.OWNER))
        response = owner.post(
            f"/api/v1/businesses/{self.w.a.pk}/staff/",
            {
                "username": "newbie",
                "email": "newbie@example.test",
                "role": "sales",
                "locations": [str(self.w.b_store.pk)],
                "password": PASSWORD,
            },
            format="json",
        )
        self.assertEqual(response.status_code, 400)
        self.assertFalse(Membership.objects.filter(user__username="newbie").exists())

    def test_inactive_membership_and_inactive_business_are_not_found(self):
        manager = self.w.user("a", Role.MANAGER)
        url = f"/api/v1/businesses/{self.w.a.pk}/"
        self.assertEqual(client_for(manager).get(url).status_code, 200)
        Membership.objects.filter(user=manager, business=self.w.a).update(is_active=False)
        self.assertEqual(client_for(manager).get(url).status_code, 404)
        Membership.objects.filter(user=manager).update(is_active=True)
        Business.objects.filter(pk=self.w.a.pk).update(is_active=False)
        self.assertEqual(client_for(manager).get(url).status_code, 404)


class RoleMatrixTests(APITestCase):
    def setUp(self):
        super().setUp()
        self.w = World()

    def test_each_endpoint_allows_exactly_the_roles_in_the_matrix(self):
        staff = self.w.staff_id(self.w.a, Role.SALES)
        for role in ROLES:
            api = client_for(self.w.user("a", role))
            for method, url, code in endpoints(self.w.a, self.w.a_store, staff):
                with self.subTest(role=role, method=method, url=url):
                    response = getattr(api, method)(url, {}, format="json")
                    if has_permission(role, code):
                        self.assertNotIn(response.status_code, (401, 403), response.content)
                    else:
                        self.assertEqual(response.status_code, 403, response.content)
                        self.assertEqual(response.json()["error"]["code"], "permission_denied")


class LocationScopeTests(APITestCase):
    def setUp(self):
        super().setUp()
        self.w = World()
        self.base = f"/api/v1/businesses/{self.w.a.pk}"

    def names(self, user):
        data = client_for(user).get(f"{self.base}/locations/").json()["results"]
        return sorted(item["name"] for item in data)

    def test_owner_and_manager_see_every_location(self):
        for role in (Role.OWNER, Role.MANAGER):
            self.assertEqual(self.names(self.w.user("a", role)), ["A Store", "A Warehouse"])

    def test_restricted_roles_see_only_their_assigned_locations(self):
        for role in (Role.SALES, Role.WAREHOUSE):
            user = self.w.user("a", role)
            self.assertEqual(self.names(user), ["A Store"])
            api = client_for(user)
            self.assertEqual(
                api.get(f"{self.base}/locations/{self.w.a_store.pk}/").status_code, 200
            )
            self.assertEqual(api.get(f"{self.base}/locations/{self.w.a_wh.pk}/").status_code, 404)

    def test_all_locations_flag_widens_access(self):
        user = self.w.user("a", Role.SALES)
        Membership.objects.filter(user=user).update(all_locations=True)
        self.assertEqual(self.names(user), ["A Store", "A Warehouse"])

    def test_inactive_locations_are_hidden_unless_requested_by_a_manager_of_locations(self):
        Location.objects.filter(pk=self.w.a_wh.pk).update(is_active=False)
        owner = client_for(self.w.user("a", Role.OWNER))
        self.assertEqual(len(owner.get(f"{self.base}/locations/").json()["results"]), 1)
        self.assertEqual(
            len(owner.get(f"{self.base}/locations/?include_inactive=1").json()["results"]), 2
        )
        manager = client_for(self.w.user("a", Role.MANAGER))
        self.assertEqual(
            len(manager.get(f"{self.base}/locations/?include_inactive=1").json()["results"]), 1
        )

    def test_location_names_are_unique_per_business_ignoring_case(self):
        owner = client_for(self.w.user("a", Role.OWNER))
        taken = owner.post(
            f"{self.base}/locations/", {"name": "a store", "kind": "store"}, format="json"
        )
        self.assertEqual(taken.status_code, 400)
        self.assertEqual(taken.json()["error"]["fields"]["name"][0]["code"], "name_taken")
        # the same name in another business is fine
        other = client_for(self.w.user("b", Role.OWNER))
        ok = other.post(
            f"/api/v1/businesses/{self.w.b.pk}/locations/",
            {"name": "A Store", "kind": "store"},
            format="json",
        )
        self.assertEqual(ok.status_code, 201)


class StaffTests(APITestCase):
    def setUp(self):
        super().setUp()
        self.w = World()
        self.owner = client_for(self.w.user("a", Role.OWNER))
        self.base = f"/api/v1/businesses/{self.w.a.pk}/staff/"
        self.payload = {
            "username": "Newbie",
            "email": "newbie@example.test",
            "full_name": "Täze Işgär",
            "preferred_language": "tk",
            "role": "sales",
            "locations": [str(self.w.a_store.pk)],
        }

    def test_owner_creates_staff_with_an_initial_password(self):
        response = self.owner.post(self.base, {**self.payload, "password": PASSWORD}, format="json")
        self.assertEqual(response.status_code, 201, response.content)
        data = response.json()
        self.assertEqual(data["user"]["username"], "newbie")  # normalised
        self.assertEqual(data["role"], "sales")
        self.assertNotIn("password", str(data))
        login = APIClient().post(
            "/api/v1/auth/login/", {"username": "newbie", "password": PASSWORD}, format="json"
        )
        self.assertEqual(login.status_code, 200)

    def test_without_a_password_the_person_gets_an_emailed_code_to_choose_one(self):
        with self.captureOnCommitCallbacks(execute=True):
            response = self.owner.post(self.base, self.payload, format="json")
        self.assertEqual(response.status_code, 201)
        self.assertEqual(len(mail.outbox), 1)
        self.assertEqual(mail.outbox[0].to, ["newbie@example.test"])
        self.assertIn(
            "Hasabyňyz döredildi", mail.outbox[0].subject
        )  # Turkmen, per preferred_language
        self.assertIn("newbie", mail.outbox[0].body)
        # cannot sign in until a password is chosen
        self.assertEqual(
            APIClient()
            .post(
                "/api/v1/auth/login/", {"username": "newbie", "password": PASSWORD}, format="json"
            )
            .status_code,
            401,
        )

    def test_duplicates_report_field_codes(self):
        self.owner.post(self.base, {**self.payload, "password": PASSWORD}, format="json")
        again = self.owner.post(
            self.base,
            {**self.payload, "username": "NEWBIE", "email": "x@example.test", "password": PASSWORD},
            format="json",
        )
        self.assertEqual(again.json()["error"]["fields"]["username"][0]["code"], "username_taken")
        same_email = self.owner.post(
            self.base,
            {
                **self.payload,
                "username": "second",
                "email": "NEWBIE@example.test",
                "password": PASSWORD,
            },
            format="json",
        )
        self.assertEqual(same_email.json()["error"]["fields"]["email"][0]["code"], "email_taken")

    def test_restricted_roles_need_a_location(self):
        response = self.owner.post(
            self.base, {**self.payload, "locations": [], "password": PASSWORD}, format="json"
        )
        self.assertEqual(response.status_code, 400)
        self.assertEqual(
            response.json()["error"]["fields"]["locations"][0]["code"], "locations_required"
        )
        ok = self.owner.post(
            self.base,
            {**self.payload, "locations": [], "all_locations": True, "password": PASSWORD},
            format="json",
        )
        self.assertEqual(ok.status_code, 201)

    def test_weak_initial_password_is_refused_and_nothing_is_created(self):
        response = self.owner.post(self.base, {**self.payload, "password": "short"}, format="json")
        self.assertEqual(response.status_code, 400)
        self.assertFalse(Membership.objects.filter(user__username="newbie").exists())

    def test_manager_can_list_staff_but_not_create_or_change(self):
        manager = client_for(self.w.user("a", Role.MANAGER))
        listing = manager.get(self.base)
        self.assertEqual(listing.status_code, 200)
        self.assertEqual(listing.json()["count"], 4)
        self.assertEqual(manager.post(self.base, self.payload, format="json").status_code, 403)

    def test_the_last_active_owner_cannot_be_demoted_or_deactivated(self):
        owner_id = self.w.staff_id(self.w.a, Role.OWNER)
        url = f"{self.base}{owner_id}/"
        demote = self.owner.patch(url, {"role": "manager"}, format="json")
        self.assertEqual(demote.status_code, 409)
        self.assertEqual(demote.json()["error"]["code"], "last_owner")
        self.assertEqual(
            self.owner.patch(url, {"is_active": False}, format="json").status_code, 409
        )
        # with a second owner it is allowed
        second = make_member(self.w.a, Role.OWNER, username="second-owner")
        self.assertEqual(self.owner.patch(url, {"role": "manager"}, format="json").status_code, 200)
        self.assertEqual(Membership.objects.get(user=second).role, Role.OWNER)

    def test_changing_role_and_locations(self):
        sales_id = self.w.staff_id(self.w.a, Role.SALES)
        response = self.owner.patch(
            f"{self.base}{sales_id}/",
            {"role": "warehouse", "locations": [str(self.w.a_wh.pk)]},
            format="json",
        )
        self.assertEqual(response.status_code, 200, response.content)
        self.assertEqual(response.json()["role"], "warehouse")
        self.assertEqual(response.json()["locations"], [str(self.w.a_wh.pk)])
        cleared = self.owner.patch(f"{self.base}{sales_id}/", {"locations": []}, format="json")
        self.assertEqual(cleared.status_code, 400)  # a restricted role must keep a location

    def test_staff_changes_are_audited_without_credentials(self):
        self.owner.post(self.base, {**self.payload, "password": PASSWORD}, format="json")
        event = AuditEvent.objects.get(action="staff.created")
        self.assertEqual(event.business, self.w.a)
        self.assertEqual(event.actor.username, "a-owner")
        self.assertNotIn(PASSWORD, str(event.metadata))
        self.assertTrue(event.request_id)


class MeTests(APITestCase):
    def test_me_lists_only_my_memberships_with_permissions_and_locations(self):
        w = World()
        user = w.user("a", Role.SALES)
        other_business = make_business("Shop C", locations=("C Store",))
        c_store = other_business.locations.get()
        Membership.objects.create(
            user=user, business=other_business, role=Role.WAREHOUSE
        ).locations.set([c_store])
        data = client_for(user).get("/api/v1/me/").json()
        self.assertEqual({m["business"]["name"] for m in data["memberships"]}, {"Shop A", "Shop C"})
        by_name = {m["business"]["name"]: m for m in data["memberships"]}
        self.assertEqual(by_name["Shop A"]["role"], "sales")
        self.assertIn("stock.view", by_name["Shop A"]["permissions"])
        self.assertNotIn("stock.adjust", by_name["Shop A"]["permissions"])
        self.assertEqual([loc["name"] for loc in by_name["Shop A"]["locations"]], ["A Store"])
        self.assertEqual([loc["name"] for loc in by_name["Shop C"]["locations"]], ["C Store"])
        self.assertNotIn("Shop B", str(data))

    def test_owner_sees_all_locations(self):
        w = World()
        data = client_for(w.user("a", Role.OWNER)).get("/api/v1/me/").json()
        self.assertEqual(
            [loc["name"] for loc in data["memberships"][0]["locations"]], ["A Store", "A Warehouse"]
        )

    def test_language_can_be_changed_but_username_and_email_cannot(self):
        user = make_user("lang-user")
        api = client_for(user)
        response = api.patch(
            "/api/v1/me/",
            {
                "preferred_language": "tk",
                "full_name": "Täze at",
                "username": "hacker",
                "email": "x@evil.test",
            },
            format="json",
        )
        self.assertEqual(response.status_code, 200)
        user.refresh_from_db()
        self.assertEqual((user.preferred_language, user.full_name), ("tk", "Täze at"))
        self.assertEqual((user.username, user.email), ("lang-user", "lang-user@example.test"))

    def test_unsupported_language_is_rejected(self):
        api = client_for(make_user("lang-user"))
        self.assertEqual(
            api.patch("/api/v1/me/", {"preferred_language": "en"}, format="json").status_code, 400
        )
