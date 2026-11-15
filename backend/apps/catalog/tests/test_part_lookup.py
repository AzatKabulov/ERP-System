from unittest import mock

from django.core.cache import cache
from django.test import override_settings
from rest_framework.test import APIClient

from apps.businesses.models import Role
from apps.catalog import part_lookup
from apps.catalog.models import Barcode, Product
from apps.common.testing import APITestCase
from apps.inventory.tests.support import World, make_product


@override_settings(BARCODE_LOOKUP_ENABLED=True, PART_LOOKUP_OSK_ENABLED=True)
class PartLookupTests(APITestCase):
    def setUp(self):
        super().setUp()
        self.w = World()
        self.url = self.w.base + "/parts/info/"

    def ask(self, code, **extra):
        return self.w.api[Role.WAREHOUSE].get(self.url, {"code": code, **extra})

    def test_composite_and_brand_identifiers(self):
        self.assertEqual(part_lookup.identify("MH044089  0001"), ("MH044089", ""))
        self.assertEqual(part_lookup.identify("KYB 444083"), ("444083", "KYB"))
        for code in ("0007", "1950", "https://localhost/", "promo\nME996364", "a" * 100):
            self.assertEqual(part_lookup.identify(code), ("", ""))

    def test_seed_reference_is_a_reviewable_suggestion_and_has_no_money(self):
        count = Product.objects.count()
        for code in ("ME996364", "MH044089  0001", "JX1008A", "KYB 444083", "MS402-2648"):
            with mock.patch.object(part_lookup, "_osk") as external:
                response = self.ask(code)
            self.assertEqual(response.status_code, 200)
            self.assertTrue(response.json()["found"], code)
            external.assert_not_called()
            self.assertNotIn("price", response.json())
            self.assertNotIn("cost", response.json())
        self.assertEqual(Product.objects.count(), count)

    def test_wrong_brand_never_receives_a_reference_for_another_brand(self):
        with mock.patch.object(part_lookup, "_osk", return_value=None):
            self.assertFalse(self.ask("MH044089", brand="KYB").json()["found"])

    def test_public_osk_matches_own_article_not_cross_reference(self):
        page = (
            b"<title>OSK | Catalog</title><table><tr><td>A-9999</td>"
            b"<td>AIR FILTER</td><td>Element</td><td>Round</td></tr></table>"
        )
        opened = mock.MagicMock()
        opened.__enter__.return_value.read.return_value = page
        with mock.patch.object(part_lookup.urllib.request, "build_opener") as opener:
            opener.return_value.open.return_value = opened
            data = self.ask("A-9999").json()
        self.assertTrue(data["found"])
        self.assertEqual(data["brand"], "OSK")
        self.assertEqual(data["article"], "A-9999")

    def test_partial_failure_is_not_a_cached_miss_and_retry_recovers(self):
        with mock.patch.object(part_lookup, "_osk", side_effect=TimeoutError()):
            self.assertTrue(self.ask("A-9999").json()["unavailable"])
        answer = {"found": True, "name": "Air filter", "article": "A-9999"}
        with mock.patch.object(part_lookup, "_osk", return_value=answer) as source:
            self.assertTrue(self.ask("A-9999").json()["found"])
            self.assertTrue(self.ask("A-9999").json()["found"])
            self.assertEqual(source.call_count, 1)

    def test_internal_codes_and_urls_never_leave_server(self):
        with mock.patch.object(part_lookup, "_osk") as source:
            for code in ("0007", "1950", "https://example.test/a"):
                self.assertFalse(self.ask(code).json()["found"])
        source.assert_not_called()

    def test_authentication_and_business_isolation(self):
        self.assertEqual(APIClient().get(self.url, {"code": "ME996364"}).status_code, 401)
        self.assertEqual(self.w.b_api.get(self.url, {"code": "ME996364"}).status_code, 404)

    def test_compound_lookup_uses_own_catalog_and_respects_barcode_precedence(self):
        local = make_product(self.w.a, "MH044089")
        make_product(self.w.b, "ME996364")
        url = self.w.base + "/barcodes/lookup/"
        data = self.w.api[Role.OWNER].get(url, {"code": "MH044089  0001"}).json()
        self.assertEqual(data["id"], str(local.pk))
        self.assertEqual(self.w.api[Role.OWNER].get(url, {"code": "ME996364"}).status_code, 404)
        Barcode.objects.create(business=self.w.a, product=self.w.pad, code="MH044089  0001")
        data = self.w.api[Role.OWNER].get(url, {"code": "MH044089  0001"}).json()
        self.assertEqual(data["id"], str(self.w.pad.pk))

    def test_punctuation_normalization_refuses_ambiguous_products(self):
        make_product(self.w.a, "MB-025153")
        make_product(self.w.a, "MB025-153")
        response = self.w.api[Role.OWNER].get(
            self.w.base + "/barcodes/lookup/", {"code": "MB 025153"}
        )
        self.assertEqual(response.status_code, 404)

    def test_disabling_external_lookup_also_disables_reference_suggestions(self):
        with self.settings(BARCODE_LOOKUP_ENABLED=False):
            self.assertTrue(self.ask("ME996364").json()["unavailable"])

    def test_burst_limit_is_unavailable_not_missing(self):
        cache.add("parts:osk:admission", True, 1)
        with mock.patch.object(part_lookup.urllib.request, "build_opener") as network:
            self.assertTrue(self.ask("A-9999").json()["unavailable"])
        network.assert_not_called()
