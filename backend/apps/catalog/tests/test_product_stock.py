"""The product list carries the sellable quantity and the minimum, for roles that may see stock."""

from decimal import Decimal

from apps.businesses.models import Role
from apps.catalog.models import ReorderSetting
from apps.common.testing import APITestCase
from apps.inventory.models import Condition
from apps.inventory.tests.support import World


class ProductStockCase(APITestCase):
    def setUp(self):
        super().setUp()
        self.w = World()

    def row(self, role, sku="BP-1"):
        response = self.w.api[role].get(f"{self.w.base}/products/")
        self.assertEqual(response.status_code, 200)
        return next(r for r in response.data["results"] if r["sku"] == sku)

    def test_sums_the_sellable_goods_in_the_callers_places(self):
        self.w.stock(self.w.pad, self.w.store, 6, "10.00")
        self.w.stock(self.w.pad, self.w.warehouse, 4, "10.00")
        self.w.stock(self.w.pad, self.w.store, 3, "10.00", condition=Condition.DAMAGED)
        owner = self.row(Role.OWNER)
        self.assertEqual(Decimal(owner["stock"]["on_hand"]), Decimal("10"))
        # the seller sees only the store, and damaged goods never count
        sales = self.row(Role.SALES)
        self.assertEqual(Decimal(sales["stock"]["on_hand"]), Decimal("6"))

    def test_a_product_without_goods_says_zero(self):
        self.assertEqual(Decimal(self.row(Role.OWNER)["stock"]["on_hand"]), Decimal("0"))

    def test_the_minimum_adds_up_over_the_callers_places(self):
        ReorderSetting.objects.create(
            business=self.w.a, product=self.w.pad, location=self.w.store, minimum=2, target=5
        )
        ReorderSetting.objects.create(
            business=self.w.a, product=self.w.pad, location=self.w.warehouse, minimum=3, target=8
        )
        self.assertEqual(Decimal(self.row(Role.OWNER)["stock"]["minimum"]), Decimal("5"))
        self.assertEqual(Decimal(self.row(Role.SALES)["stock"]["minimum"]), Decimal("2"))

    def test_a_location_narrows_the_summary_to_that_place(self):
        self.w.stock(self.w.pad, self.w.store, 6, "10.00")
        self.w.stock(self.w.pad, self.w.warehouse, 4, "10.00")
        ReorderSetting.objects.create(
            business=self.w.a, product=self.w.pad, location=self.w.warehouse, minimum=3, target=8
        )
        response = self.w.api[Role.OWNER].get(
            f"{self.w.base}/products/", {"location": str(self.w.store.pk)}
        )
        self.assertEqual(response.status_code, 200)
        row = next(r for r in response.data["results"] if r["sku"] == "BP-1")
        self.assertEqual(Decimal(row["stock"]["on_hand"]), Decimal("6"))
        self.assertEqual(Decimal(row["stock"]["minimum"]), Decimal("0"))

    def test_a_place_the_caller_may_not_see_gives_zeros_and_junk_is_ignored(self):
        self.w.stock(self.w.pad, self.w.warehouse, 4, "10.00")
        # the seller works in the store only: the warehouse stays invisible even when asked for
        response = self.w.api[Role.SALES].get(
            f"{self.w.base}/products/", {"location": str(self.w.warehouse.pk)}
        )
        row = next(r for r in response.data["results"] if r["sku"] == "BP-1")
        self.assertEqual(Decimal(row["stock"]["on_hand"]), Decimal("0"))
        response = self.w.api[Role.OWNER].get(f"{self.w.base}/products/", {"location": "nonsense"})
        self.assertEqual(response.status_code, 200)
        row = next(r for r in response.data["results"] if r["sku"] == "BP-1")
        self.assertEqual(Decimal(row["stock"]["on_hand"]), Decimal("4"))

    def test_goods_of_another_business_never_show(self):
        self.w.stock(self.w.pad, self.w.store, 1, "10.00")
        response = self.w.b_api.get(f"/api/v1/businesses/{self.w.b.pk}/products/")
        self.assertEqual(response.status_code, 200)
        for row in response.data["results"]:
            self.assertEqual(Decimal(row["stock"]["on_hand"]), Decimal("0"))

    def test_query_count_does_not_grow_with_the_list(self):
        from django.db import connection
        from django.test.utils import CaptureQueriesContext

        for _ in range(5):
            self.w.stock(self.w.pad, self.w.store, 1, "10.00")
        with CaptureQueriesContext(connection) as few:
            self.w.api[Role.OWNER].get(f"{self.w.base}/products/")
        from apps.inventory.tests.support import make_product

        for i in range(20):
            make_product(self.w.a, f"X-{i}", f"Extra {i}", self.w.unit)
        with CaptureQueriesContext(connection) as many:
            self.w.api[Role.OWNER].get(f"{self.w.base}/products/")
        self.assertEqual(len(few), len(many))
