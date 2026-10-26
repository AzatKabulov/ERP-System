"""Product names for scanned barcodes from the open databases (the network is always replaced)."""

import urllib.error
from unittest import mock

from django.core.cache import cache
from django.test import override_settings

from apps.businesses.models import Role
from apps.catalog import lookup
from apps.common.testing import APITestCase
from apps.inventory.tests.support import World

CERAVE = "3337875597470"  # a real EAN-13 (valid check digit)
OTHER = "4006381333931"  # another valid EAN-13


def answer(name="Cerave Moisturising Cream", brands="Cerave,L'Oreal", quantity="454 g"):
    return {
        "status": 1,
        "product": {"product_name": name, "brands": brands, "quantity": quantity},
    }


@override_settings(BARCODE_LOOKUP_ENABLED=True, BARCODE_LOOKUP_TIMEOUT=1)
class BarcodeInfoCase(APITestCase):
    def setUp(self):
        super().setUp()
        cache.clear()
        self.w = World()
        self.url = f"{self.w.base}/barcodes/info/"

    def ask(self, code=CERAVE, client=None):
        return (client or self.w.api[Role.WAREHOUSE]).get(self.url, {"code": code})

    def patched(self, side_effect):
        return mock.patch.object(lookup, "_fetch", side_effect=side_effect)


class ValidCodeTests(APITestCase):
    def test_check_digits(self):
        for good in (CERAVE, OTHER, "40058153", "036000291452"):
            self.assertTrue(lookup.valid_gtin(good), good)
        for bad in ("3337875597471", "1234", "abc", "", "33378755974701234", "3337 8755 97470"):
            self.assertFalse(lookup.valid_gtin(bad), bad)


class FindingTests(BarcodeInfoCase):
    def test_a_found_product_gives_name_brand_size_and_where_it_came_from(self):
        with self.patched([answer()]) as fetch:
            data = self.ask().json()
        self.assertEqual(
            data,
            {
                "code": CERAVE,
                "found": True,
                "name": "Cerave Moisturising Cream",
                "brand": "Cerave",
                "category": "",
                "quantity": "454 g",
                "source": "Open Beauty Facts",
                "unavailable": False,
            },
        )
        (url,) = [c.args[0] for c in fetch.call_args_list]
        self.assertTrue(url.startswith("https://world.openbeautyfacts.org/"), url)
        self.assertIn(CERAVE, url)

    def test_category_is_suggested_but_prices_and_costs_never_leave_the_lookup(self):
        data = answer()
        data["product"].update(categories="Care, Creams", price="999", cost="1")
        with self.patched([data]):
            result = self.ask().json()
        self.assertEqual(result["category"], "Creams")
        for field in ("price", "cost", "price_amount", "default_purchase_cost"):
            self.assertNotIn(field, result)

    def test_malformed_optional_metadata_is_ignored(self):
        data = answer()
        data["product"].update(brands={"wrong": "shape"}, categories=["wrong"], quantity=None)
        with self.patched([data]):
            result = self.ask().json()
        self.assertTrue(result["found"])
        self.assertEqual((result["brand"], result["category"], result["quantity"]), ("", "", ""))

    def test_only_the_digits_leave_the_server(self):
        with self.patched([answer()]) as fetch:
            self.ask()
        sent = " ".join(c.args[0] for c in fetch.call_args_list)
        for private in (str(self.w.a.pk), "Shop A", "a-warehouse", "Bearer"):
            self.assertNotIn(private, sent)

    def test_the_next_database_is_asked_when_the_first_has_nothing(self):
        with self.patched([None, answer("Plain soap", brands="")]) as fetch:
            data = self.ask(OTHER).json()
        self.assertEqual((data["found"], data["source"]), (True, "Open Products Facts"))
        self.assertEqual(fetch.call_count, 2)

    def test_a_product_without_any_name_counts_as_not_found(self):
        empty = {"status": 1, "product": {"product_name": "", "generic_name": "  "}}
        with self.patched([empty, None, None]):
            data = self.ask().json()
        self.assertEqual((data["found"], data["name"], data["unavailable"]), (False, "", False))

    def test_a_status_of_zero_counts_as_not_found(self):
        with self.patched([{"status": 0}, {"status": 0}, {"status": 0}]):
            self.assertFalse(self.ask().json()["found"])

    def test_text_is_tidied_and_cut_to_the_name_limit(self):
        with self.patched([answer("  Long   name\n" + "x" * 400, quantity=" 1  l ")]):
            data = self.ask().json()
        self.assertTrue(data["name"].startswith("Long name xxxx"))
        self.assertEqual((len(data["name"]), data["quantity"]), (255, "1 l"))


class NotFoundAndNetworkTests(BarcodeInfoCase):
    def test_nothing_known_is_a_normal_answer(self):
        with self.patched([None, None, None]):
            data = self.ask().json()
        self.assertEqual((data["found"], data["unavailable"]), (False, False))

    def test_no_connection_is_reported_and_not_remembered(self):
        down = urllib.error.URLError("no route")
        with self.patched([down, down, down]):
            data = self.ask().json()
        self.assertEqual((data["found"], data["unavailable"]), (False, True))
        with self.patched([answer()]):  # the next try may succeed
            self.assertTrue(self.ask().json()["found"])

    def test_one_database_down_does_not_stop_the_others(self):
        with self.patched([TimeoutError(), answer("Deodorant", brands="Old Spice")]):
            data = self.ask(OTHER).json()
        self.assertEqual((data["found"], data["brand"]), (True, "Old Spice"))

    def test_garbage_from_a_database_is_survived(self):
        with self.patched([ValueError("not json"), None, None]):
            self.assertFalse(self.ask().json()["found"])

    def test_switched_off_asks_nobody(self):
        with override_settings(BARCODE_LOOKUP_ENABLED=False), self.patched([]) as fetch:
            data = self.ask().json()
        self.assertEqual((data["found"], data["unavailable"]), (False, True))
        fetch.assert_not_called()


class CacheTests(BarcodeInfoCase):
    def test_a_code_is_asked_about_once(self):
        with self.patched([answer()]) as fetch:
            first = self.ask().json()
            second = self.ask().json()
            third = self.ask(client=self.w.api[Role.OWNER]).json()
        self.assertEqual(first, second)
        self.assertEqual(second, third)
        self.assertEqual(fetch.call_count, 1)

    def test_a_miss_is_remembered_too(self):
        with self.patched([None, None, None]) as fetch:
            self.ask()
            self.ask()
        self.assertEqual(fetch.call_count, 3)  # three databases, once


class AccessTests(BarcodeInfoCase):
    def test_every_member_may_ask_and_a_stranger_may_not(self):
        with self.patched([answer()]):
            for role in (Role.OWNER, Role.MANAGER, Role.SALES, Role.WAREHOUSE):
                self.assertEqual(self.ask(client=self.w.api[role]).status_code, 200, role)
            self.assertEqual(self.ask(client=self.w.b_api).status_code, 404)

    def test_an_invalid_code_is_refused_before_anything_is_asked(self):
        with self.patched([]) as fetch:
            for bad in ("3337875597471", "12", "see the label", ""):
                response = self.ask(bad)
                self.assertEqual(response.status_code, 400, bad)
                self.assertEqual(response.json()["error"]["code"], "validation_error")
        fetch.assert_not_called()

    def test_it_needs_a_signed_in_user(self):
        from rest_framework.test import APIClient

        self.assertEqual(APIClient().get(self.url, {"code": CERAVE}).status_code, 401)
