"""The first-sign-in questionnaire: the shop's fixed costs, and the team with what they are paid."""

from apps.accounts.models import User
from apps.billing import services as billing
from apps.businesses.models import Business, Role
from apps.common.testing import APITestCase, client_for, make_business, make_member


class ShopSetupTests(APITestCase):
    def setUp(self):
        super().setUp()
        self.shop = make_business("Shop")
        self.other = make_business("Other")
        self.owner = client_for(make_member(self.shop, Role.OWNER, username="owner-a"))
        self.manager = client_for(make_member(self.shop, Role.MANAGER, username="manager-a"))
        self.owner_b = client_for(make_member(self.other, Role.OWNER, username="owner-b"))
        self.team = f"/api/v1/businesses/{self.shop.pk}/team/"
        self.business = f"/api/v1/businesses/{self.shop.pk}/"

    def test_the_owner_keeps_a_team_list_with_pay(self):
        made = self.owner.post(
            self.team,
            {
                "name": "Aman",
                "phone": "+993 65 111111",
                "job_title": "Seller",
                "monthly_pay": "2500",
            },
            format="json",
        )
        self.assertEqual(made.status_code, 201, made.content)
        listed = self.owner.get(self.team).json()
        rows = listed["results"] if isinstance(listed, dict) else listed
        self.assertEqual([r["name"] for r in rows], ["Aman"])
        self.assertEqual(rows[0]["monthly_pay"], "2500.00")

    def test_pay_is_for_the_owner_only_and_never_crosses_shops(self):
        self.owner.post(self.team, {"name": "Aman", "monthly_pay": "2500"}, format="json")
        self.assertEqual(self.manager.get(self.team).status_code, 403)
        self.assertEqual(
            self.manager.post(self.team, {"name": "X"}, format="json").status_code, 403
        )
        self.assertEqual(self.owner_b.get(self.team).status_code, 404)

    def test_a_member_can_be_changed_and_removed(self):
        member = self.owner.post(self.team, {"name": "Aman"}, format="json").json()
        url = f"{self.team}{member['id']}/"
        self.assertEqual(
            self.owner.patch(url, {"monthly_pay": "3000"}, format="json").status_code, 200
        )
        self.assertEqual(self.owner.delete(url).status_code, 204)
        listed = self.owner.get(self.team).json()
        rows = listed["results"] if isinstance(listed, dict) else listed
        self.assertEqual(rows, [])
        self.assertEqual(self.owner.get(url).status_code, 404)

    def test_negative_pay_is_refused(self):
        response = self.owner.post(self.team, {"name": "Aman", "monthly_pay": "-1"}, format="json")
        self.assertEqual(response.status_code, 400)

    def test_costs_and_the_questionnaire_state_are_saved_on_the_shop(self):
        response = self.owner.patch(
            self.business,
            {"monthly_rent": "8000", "monthly_costs": "1500", "setup_status": "done"},
            format="json",
        )
        self.assertEqual(response.status_code, 200, response.content)
        self.shop.refresh_from_db()
        self.assertEqual(str(self.shop.monthly_rent), "8000.00")
        self.assertEqual(self.shop.setup_status, "done")
        self.assertEqual(
            self.owner.patch(self.business, {"setup_status": "skipped"}, format="json").status_code,
            200,
        )

    def test_the_app_cannot_put_a_shop_back_to_pending(self):
        response = self.owner.patch(self.business, {"setup_status": "pending"}, format="json")
        self.assertEqual(response.status_code, 400)

    def test_only_the_owner_changes_the_shop(self):
        self.assertEqual(
            self.manager.patch(self.business, {"monthly_rent": "1"}, format="json").status_code, 403
        )

    def test_a_shop_we_set_up_starts_pending_and_an_older_one_is_done(self):
        operator = User.objects.create_superuser("boss", "", "operator-password-1")
        client, _ = billing.provision_client(
            store_name="Brand New", owner_username="brand-new", actor=operator
        )
        self.assertEqual(client.business.setup_status, Business.Setup.PENDING)
        self.assertEqual(Business.objects.get(pk=self.shop.pk).setup_status, "done")
        me = client_for(User.objects.get(username="brand-new")).get("/api/v1/me/").json()
        self.assertEqual(me["memberships"][0]["business"]["setup_status"], "pending")
