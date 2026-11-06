"""Temporary passwords: a password somebody else chose must be replaced by its owner before
anything in the business opens; staff may have no email; the owner can hand out a new
temporary password when there is no email to send a code to."""

from rest_framework.test import APIClient

from apps.accounts.models import User
from apps.audit.models import AuditEvent
from apps.businesses.models import Membership, Role
from apps.common.testing import PASSWORD, APITestCase, client_for, make_business, make_member

LOGIN = "/api/v1/auth/login/"
CHANGE = "/api/v1/auth/password/change/"
ME = "/api/v1/me/"


def sign_in(username, password):
    response = APIClient().post(LOGIN, {"username": username, "password": password}, format="json")
    client = APIClient()
    if response.status_code == 200:
        client.credentials(HTTP_AUTHORIZATION=f"Bearer {response.json()['access']}")
    return response, client


class TemporaryPasswordFlowTests(APITestCase):
    def setUp(self):
        super().setUp()
        self.business = make_business("Shop A")
        self.store = self.business.locations.get()
        self.owner = make_member(self.business, Role.OWNER, username="owner-a")
        self.owner_client = client_for(self.owner)
        self.base = f"/api/v1/businesses/{self.business.pk}/staff/"
        self.payload = {
            "username": "seller1",
            "full_name": "Seller One",
            "role": "sales",
            "locations": [str(self.store.pk)],
        }

    def _create(self, **extra):
        return self.owner_client.post(self.base, {**self.payload, **extra}, format="json")

    def test_staff_without_email_needs_a_temporary_password(self):
        response = self._create()
        self.assertEqual(response.status_code, 400)
        self.assertEqual(
            response.json()["error"]["fields"]["password"][0]["code"], "email_or_password_required"
        )

    def test_staff_without_email_can_be_created_with_a_temporary_password(self):
        response = self._create(password=PASSWORD)
        self.assertEqual(response.status_code, 201, response.content)
        user = User.objects.get(username="seller1")
        self.assertEqual(user.email, "")
        self.assertTrue(user.must_change_password)

    def test_many_staff_may_have_no_email_but_real_emails_stay_unique(self):
        self.assertEqual(self._create(password=PASSWORD).status_code, 201)
        self.assertEqual(self._create(username="seller2", password=PASSWORD).status_code, 201)
        self.assertEqual(
            self._create(username="seller3", email="x@example.test", password=PASSWORD).status_code,
            201,
        )
        again = self._create(username="seller4", email="X@example.test", password=PASSWORD)
        self.assertEqual(again.json()["error"]["fields"]["email"][0]["code"], "email_taken")

    def test_the_business_stays_closed_until_the_person_picks_their_own_password(self):
        self._create(password=PASSWORD)
        response, seller = sign_in("seller1", PASSWORD)
        self.assertEqual(response.status_code, 200)
        self.assertTrue(response.json()["user"]["must_change_password"])
        # who am I still works, so the app can show the "choose a password" screen
        me = seller.get(ME)
        self.assertEqual(me.status_code, 200)
        self.assertTrue(me.json()["user"]["must_change_password"])
        stock = seller.get(f"/api/v1/businesses/{self.business.pk}/products/")
        self.assertEqual(stock.status_code, 403)
        self.assertEqual(stock.json()["error"]["code"], "password_change_required")

        changed = seller.post(
            CHANGE,
            {"old_password": PASSWORD, "new_password": "my-own-secret-7"},
            format="json",
        )
        self.assertEqual(changed.status_code, 200, changed.content)
        seller.credentials(HTTP_AUTHORIZATION=f"Bearer {changed.json()['access']}")
        self.assertFalse(seller.get(ME).json()["user"]["must_change_password"])
        self.assertEqual(
            seller.get(f"/api/v1/businesses/{self.business.pk}/products/").status_code, 200
        )

    def test_a_stranger_still_gets_404_not_the_password_message(self):
        other = make_business("Shop B")
        self._create(password=PASSWORD)
        _, seller = sign_in("seller1", PASSWORD)
        response = seller.get(f"/api/v1/businesses/{other.pk}/products/")
        self.assertEqual(response.status_code, 404)

    def test_a_password_the_user_chose_never_needs_changing(self):
        user = make_member(self.business, Role.MANAGER, username="manager-a")
        self.assertFalse(user.must_change_password)
        _, client = sign_in("manager-a", PASSWORD)
        self.assertEqual(
            client.get(f"/api/v1/businesses/{self.business.pk}/products/").status_code, 200
        )


class OwnerTemporaryPasswordTests(APITestCase):
    def setUp(self):
        super().setUp()
        self.business = make_business("Shop A")
        self.store = self.business.locations.get()
        self.owner = make_member(self.business, Role.OWNER, username="owner-a")
        self.seller = make_member(
            self.business, Role.SALES, username="seller-a", locations=[self.store], email=""
        )
        self.owner_client = client_for(self.owner)
        self.membership = Membership.objects.get(user=self.seller)
        self.url = (
            f"/api/v1/businesses/{self.business.pk}/staff/{self.membership.pk}/temporary-password/"
        )

    def test_a_generated_password_is_shown_once_and_forces_a_change(self):
        response = self.owner_client.post(self.url)
        self.assertEqual(response.status_code, 200, response.content)
        password = response.json()["password"]
        self.assertGreaterEqual(len(password), 15)
        signed_in, _ = sign_in("seller-a", password)
        self.assertEqual(signed_in.status_code, 200)
        self.assertTrue(signed_in.json()["user"]["must_change_password"])
        self.assertEqual(sign_in("seller-a", PASSWORD)[0].status_code, 401)  # the old one is gone
        self.assertTrue(
            AuditEvent.objects.filter(
                action="staff.temporary_password", business=self.business
            ).exists()
        )
        self.assertNotIn(password, str(list(AuditEvent.objects.values_list("metadata", flat=True))))

    def test_the_owner_can_type_the_password_and_a_weak_one_is_refused(self):
        weak = self.owner_client.post(self.url, {"password": "short"}, format="json")
        self.assertEqual(weak.status_code, 400)
        self.assertIn("password", weak.json()["error"]["fields"])
        good = self.owner_client.post(self.url, {"password": "typed-by-owner-42"}, format="json")
        self.assertEqual(good.status_code, 200)
        self.assertEqual(sign_in("seller-a", "typed-by-owner-42")[0].status_code, 200)

    def test_only_an_owner_may_do_it(self):
        manager = make_member(self.business, Role.MANAGER, username="manager-a")
        self.assertEqual(client_for(manager).post(self.url).status_code, 403)
        self.assertEqual(client_for(self.seller).post(self.url).status_code, 403)

    def test_another_businesss_owner_cannot_reach_the_staff_member(self):
        other = make_business("Shop B")
        other_owner = make_member(other, Role.OWNER, username="owner-b")
        self.assertEqual(client_for(other_owner).post(self.url).status_code, 404)
        # and cannot use their own business with this staff id either
        url = f"/api/v1/businesses/{other.pk}/staff/{self.membership.pk}/temporary-password/"
        self.assertEqual(client_for(other_owner).post(url).status_code, 404)

    def test_an_owner_cannot_do_it_to_themselves(self):
        own = Membership.objects.get(user=self.owner)
        url = f"/api/v1/businesses/{self.business.pk}/staff/{own.pk}/temporary-password/"
        response = self.owner_client.post(url)
        self.assertEqual(response.status_code, 409)
        self.assertEqual(response.json()["error"]["code"], "use_password_change")

    def test_an_account_that_belongs_elsewhere_keeps_its_own_password(self):
        other = make_business("Shop B")
        Membership.objects.create(user=self.seller, business=other, role=Role.OWNER)
        response = self.owner_client.post(self.url)
        self.assertEqual(response.status_code, 409)
        self.assertEqual(response.json()["error"]["code"], "account_shared")
        self.assertEqual(sign_in("seller-a", PASSWORD)[0].status_code, 200)

    def test_platform_operators_cannot_be_taken_over_by_an_owner(self):
        self.seller.is_staff = True
        self.seller.save()
        self.assertEqual(self.owner_client.post(self.url).status_code, 409)

    def test_staff_without_email_get_no_code_and_no_error(self):
        send = f"/api/v1/businesses/{self.business.pk}/staff/{self.membership.pk}/send-code/"
        self.assertEqual(self.owner_client.post(send).status_code, 202)
