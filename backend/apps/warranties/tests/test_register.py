"""The register of goods sold with a warranty: what the owner opens when a customer comes back
and says "I bought this here". Computed from sales, returns and claims; nothing is stored."""

import uuid
from datetime import date
from unittest import mock

from apps.businesses.models import Role
from apps.catalog.models import Barcode
from apps.warranties.entitlement import add_months

from .test_warranties import WarrantyCase


class RegisterCase(WarrantyCase):
    def register(self, client=None, **params):
        response = (client or self.owner).get(f"{self.w.base}/warranty-register/", params)
        self.assertEqual(response.status_code, 200, response.content)
        return response.json()

    def sold_on_day(self, day):
        return mock.patch("apps.warranties.register.sale_day", return_value=day)


class RegisterContentTests(RegisterCase):
    def test_a_sale_with_a_warranty_is_listed_with_its_dates(self):
        sale = self.sell(2)
        body = self.register()
        self.assertEqual(len(body["results"]), 1)
        item = body["results"][0]
        self.assertEqual(
            (item["sale_number"], item["sku"], item["quantity"], item["warranty_months"]),
            (sale["number"], "BP-1", "2.000", 6),
        )
        self.assertEqual(item["until"], str(add_months(date.fromisoformat(item["starts"]), 6)))
        self.assertEqual((item["status"], item["open_claims"]), ("active", 0))
        self.assertGreater(item["days_left"], 150)

    def test_goods_without_a_warranty_are_not_listed(self):
        self.sell(1, product=self.product_with(0, "NOWAR"))
        self.assertEqual(self.register()["results"], [])

    def test_the_counts_for_the_tabs(self):
        self.sell(1)
        counts = self.register()["counts"]
        self.assertEqual(counts, {"active": 1, "soon": 0, "expired": 0, "returned": 0})


class RegisterStatusTests(RegisterCase):
    def test_a_warranty_that_ends_within_thirty_days_is_ending_soon(self):
        self.sell(1)
        with self.sold_on_day(date(2026, 5, 1)), self.on(date(2026, 10, 20)):
            body = self.register()
            item = body["results"][0]
            self.assertEqual(
                (item["until"], item["days_left"], item["status"]), ("2026-11-01", 12, "soon")
            )
            self.assertEqual(body["counts"], {"active": 1, "soon": 1, "expired": 0, "returned": 0})
            self.assertEqual(len(self.register(status="active")["results"]), 1)
            self.assertEqual(len(self.register(status="soon")["results"]), 1)

    def test_the_last_day_still_counts_and_the_next_day_does_not(self):
        self.sell(1)
        with self.sold_on_day(date(2026, 5, 1)):
            with self.on(date(2026, 11, 1)):
                self.assertEqual(self.register()["results"][0]["status"], "soon")
            with self.on(date(2026, 11, 2)):
                item = self.register()["results"][0]
                self.assertEqual((item["status"], item["days_left"]), ("expired", -1))
                self.assertEqual(self.register(status="active")["results"], [])
                self.assertEqual(len(self.register(status="expired")["results"]), 1)

    def test_a_line_returned_in_full_is_returned_and_a_partial_return_is_not(self):
        sale = self.sell(3)
        line = sale["lines"][0]["id"]

        def give_back(quantity):
            response = self.owner.post(
                f"{self.w.base}/sales/{sale['id']}/returns/",
                {
                    "reason": "Changed my mind",
                    "lines": [
                        {"sale_line": line, "quantity": str(quantity), "condition": "sellable"}
                    ],
                },
                format="json",
                HTTP_IDEMPOTENCY_KEY=str(uuid.uuid4()),
            )
            self.assertEqual(response.status_code, 201, response.content)

        give_back(1)
        item = self.register()["results"][0]
        self.assertEqual((item["status"], item["returned"]), ("active", "1.000"))
        give_back(2)
        item = self.register()["results"][0]
        self.assertEqual((item["status"], item["returned"]), ("returned", "3.000"))
        self.assertEqual(self.register(status="returned")["counts"]["returned"], 1)
        self.assertEqual(self.register(status="active")["results"], [])

    def test_an_open_claim_is_shown_beside_the_status(self):
        sale = self.sell(2)
        self.opened(sale)
        item = self.register()["results"][0]
        self.assertEqual((item["status"], item["open_claims"]), ("active", 1))


class RegisterSearchTests(RegisterCase):
    def test_search_by_sale_number_customer_product_and_barcode(self):
        customer = self.owner.post(
            f"{self.w.base}/customers/",
            {"name": "Aman Berdiyev", "phone": "+99365111222"},
            format="json",
        ).json()
        first = self.sell(1, customer=customer["id"])
        other = self.product_with(12, "KB-9", name="Shock absorber")
        Barcode.objects.create(business=self.w.a, product=other, code="4006381333931")
        second = self.sell(1, product=other)
        for query, number in [
            (f"S-{first['number']:06d}", first["number"]),
            (f"S-{second['number']:06d}", second["number"]),
            ("aman", first["number"]),
            ("+99365111222", first["number"]),
            ("shock", second["number"]),
            ("kb-9", second["number"]),
            ("4006381333931", second["number"]),
        ]:
            with self.subTest(query):
                found = [r["sale_number"] for r in self.register(q=query)["results"]]
                self.assertEqual(found, [number])

    def test_paging_gives_every_line_once_newest_first(self):
        numbers = [self.sell(1)["number"] for _ in range(5)]
        pages, offset = [], 0
        while True:
            body = self.register(limit=2, offset=offset)
            pages += [r["sale_number"] for r in body["results"]]
            if not body["has_more"]:
                break
            offset += 2
        self.assertEqual(pages, sorted(numbers, reverse=True))


class RegisterAccessTests(RegisterCase):
    def test_roles_places_and_other_businesses(self):
        self.sell(1)
        self.assertEqual(len(self.register(client=self.sales)["results"]), 1)
        # a keeper has no warranty rights
        self.assertEqual(
            self.w.api[Role.WAREHOUSE].get(f"{self.w.base}/warranty-register/").status_code, 403
        )
        # another business sees nothing and does not even know this one exists
        self.assertEqual(self.w.b_api.get(f"{self.w.base}/warranty-register/").status_code, 404)

    def test_bad_parameters_are_refused(self):
        for params in ({"status": "nonsense"}, {"limit": "x"}, {"location": "not-a-uuid"}):
            with self.subTest(params):
                response = self.owner.get(f"{self.w.base}/warranty-register/", params)
                self.assertEqual(response.status_code, 400)
