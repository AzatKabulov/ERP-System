"""The dashboard: each role gets only its own sections, for its own locations."""

from decimal import Decimal
from unittest import mock

from apps.audit.models import AuditEvent
from apps.businesses.models import Membership, Role
from apps.businesses.permissions import MATRIX
from apps.common.testing import client_for, make_business, make_member
from apps.reports.tests.support import ReportsCase, at
from apps.warranties import services as warranty_services

D = Decimal
NOW = ("2026-10-03", "20:00")  # 15:00 UTC


class DashboardCase(ReportsCase):
    def dash(self, client=None, when=NOW, **params):
        with at(*when):
            response = (client or self.owner).get(f"{self.w.base}/dashboard/", params)
        self.assertEqual(response.status_code, 200, response.content)
        return response.json()


class OwnerDashboardTests(DashboardCase):
    def test_every_section_with_its_figures(self):
        body = self.dash()
        activity = body.pop("recent_activity")
        self.assertEqual(
            body,
            {
                "generated_at": "2026-10-03T15:00:00Z",
                "sales_today": {"count": 1, "total": "110.00"},  # S4, at the warehouse
                "sales_month": {"count": 4, "total": "1317.50"},
                "gross_profit_month": "429.00",  # net of the three returns
                "expenses_month": "245.50",  # not September's rent, not the void expense
                "inventory_value": "1594.00",
                "low_stock_count": 3,
                "reorder_count": 2,  # the oil at the warehouse is covered by an open order
                "open_orders_count": 2,
                "open_claims_count": 0,
            },
        )
        self.assertEqual(len(activity), 10)

    def test_the_ten_newest_events_of_this_business_only(self):
        activity = self.dash()["recent_activity"]
        newest = AuditEvent.objects.filter(business=self.w.a).order_by("-created_at", "-id")[:10]
        self.assertEqual([e["id"] for e in activity], [str(e.pk) for e in newest])
        self.assertEqual(
            set(activity[0]),
            {"id", "action", "object_type", "object_id", "actor", "created_at", "metadata"},
        )
        newest_event = newest[0]
        self.assertEqual(activity[0]["action"], newest_event.action)
        self.assertEqual(
            activity[0]["actor"],
            {"id": str(newest_event.actor_id), "name": newest_event.actor.username},
        )
        text = str(activity)
        self.assertNotIn("B-SECRET", text)  # business B's event
        self.assertNotIn("auth.login", text)  # an event without a business
        self.assertNotIn("request_id", text)

    def test_a_manager_sees_what_the_owner_sees(self):
        self.assertEqual(self.dash(self.manager), self.dash(self.owner))

    def test_a_location_in_the_query_string_changes_nothing(self):
        self.assertEqual(self.dash(location=self.w.warehouse.pk), self.dash())

    def test_today_and_the_month_are_days_in_the_business_zone(self):
        # 19:30 UTC on 1 October is already 00:30 on 2 October in Ashgabat
        body = self.dash(when=("2026-10-02", "00:30"))
        self.assertEqual(body["generated_at"], "2026-10-01T19:30:00Z")
        self.assertEqual(body["sales_today"], {"count": 1, "total": "665.00"})  # S3 only
        self.assertEqual(body["sales_month"], {"count": 3, "total": "1207.50"})  # not S4 (3 Oct)

    def test_a_new_month_starts_from_zero(self):
        november = self.dash(when=("2026-11-01", "10:00"))
        self.assertEqual(november["sales_today"], {"count": 0, "total": "0.00"})
        self.assertEqual(november["sales_month"], {"count": 0, "total": "0.00"})
        self.assertEqual(november["gross_profit_month"], "0.00")
        self.assertEqual(november["expenses_month"], "0.00")
        self.assertEqual(november["inventory_value"], "1594.00")  # a snapshot of now
        september = self.dash(when=("2026-09-30", "12:00"))
        self.assertEqual(september["sales_month"], {"count": 0, "total": "0.00"})
        self.assertEqual(september["expenses_month"], "1000.00")  # the September rent

    def test_sections_the_role_may_not_see_are_left_out(self):
        cases = {
            "sales.view": {"sales_today", "sales_month"},
            "sales.cost.view": {"gross_profit_month"},
            "expense.view": {"expenses_month"},
            "stock.cost.view": {"inventory_value"},
            "stock.view": {"low_stock_count"},
            "reorder.view": {"reorder_count"},
            "purchasing.view": {"open_orders_count"},
            "warranty.view": {"open_claims_count"},
            "audit.view": {"recent_activity"},
        }
        full = self.dash(self.manager)
        for code, missing in cases.items():
            with self.subTest(code=code):
                with mock.patch.dict(MATRIX, {code: frozenset({Role.OWNER})}):
                    body = self.dash(self.manager)
                self.assertEqual(set(full) - set(body), missing)

    def test_another_business_gets_nothing(self):
        with at(*NOW):
            self.assertEqual(self.w.b_api.get(f"{self.w.base}/dashboard/").status_code, 404)


class SellerAndKeeperTests(DashboardCase):
    def test_a_seller_sees_sales_at_the_own_location_and_no_costs(self):
        self.assertEqual(
            self.dash(self.sales),
            {
                "generated_at": "2026-10-03T15:00:00Z",
                "sales_today": {"count": 0, "total": "0.00"},  # S4 was sold at the warehouse
                "sales_month": {"count": 3, "total": "1207.50"},
                "low_stock_count": 2,
                "open_claims_count": 0,
            },
        )

    def test_a_warehouse_keeper_gets_no_sales_cost_expense_or_audit_sections(self):
        self.assertEqual(
            self.dash(self.warehouse),
            {"generated_at": "2026-10-03T15:00:00Z", "low_stock_count": 1, "open_orders_count": 2},
        )

    def test_nothing_about_money_leaks_to_either(self):
        for client in (self.sales, self.warehouse):
            text = str(self.dash(client))
            for word in ("gross_profit", "expenses", "inventory_value", "recent_activity"):
                self.assertNotIn(word, text)

    def test_a_seller_of_the_warehouse_sees_the_warehouse_sale(self):
        other = make_member(
            self.w.a, Role.SALES, username="a-sales-warehouse", locations=[self.w.warehouse]
        )
        body = self.dash(client_for(other))
        self.assertEqual(body["sales_today"], {"count": 1, "total": "110.00"})
        self.assertEqual(body["sales_month"], {"count": 1, "total": "110.00"})
        self.assertEqual(body["low_stock_count"], 1)

    def test_open_claims_are_counted_where_the_sale_was_made(self):
        owner = Membership.objects.get(user=self.s.owner, business=self.w.a)
        with at("2026-10-03", "18:00"):
            for sale, quantity in ((self.s.s1, "1"), (self.s.s4, "1")):
                warranty_services.open_claim(
                    self.w.a,
                    self.s.owner,
                    owner,
                    {
                        "sale_line": sale.lines.get(product=self.w.pad).pk,
                        "quantity": D(quantity),
                        "problem": "Noisy",
                        "override": True,
                        "override_note": "Customer is a regular",
                    },
                )
        self.assertEqual(self.dash()["open_claims_count"], 2)
        self.assertEqual(self.dash(self.sales)["open_claims_count"], 1)  # the store's sale
        other = make_member(
            self.w.a, Role.SALES, username="a-sales-warehouse", locations=[self.w.warehouse]
        )
        self.assertEqual(self.dash(client_for(other))["open_claims_count"], 1)
        self.assertNotIn("open_claims_count", self.dash(self.warehouse))  # no warranty.view


class EmptyBusinessTests(DashboardCase):
    def test_a_new_business_shows_zeros_and_an_empty_list(self):
        shop = make_business("Fresh Shop", locations=("Main",))
        owner = client_for(make_member(shop, Role.OWNER, username="fresh-owner"))
        with at(*NOW):
            response = owner.get(f"/api/v1/businesses/{shop.pk}/dashboard/")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(
            response.json(),
            {
                "generated_at": "2026-10-03T15:00:00Z",
                "sales_today": {"count": 0, "total": "0.00"},
                "sales_month": {"count": 0, "total": "0.00"},
                "gross_profit_month": "0.00",
                "expenses_month": "0.00",
                "inventory_value": "0.00",
                "low_stock_count": 0,
                "reorder_count": 0,
                "open_orders_count": 0,
                "open_claims_count": 0,
                "recent_activity": [],
            },
        )
