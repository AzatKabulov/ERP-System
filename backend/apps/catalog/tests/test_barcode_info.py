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


@override_settings(
    BARCODE_LOOKUP_ENABLED=True,
    BARCODE_LOOKUP_TIMEOUT=1,
    BARCODE_LOOKUP_UPCITEMDB_ENABLED=False,
    BARCODE_LOOKUP_GTINHUB_ENABLED=False,
)
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

    def test_partial_failure_is_unavailable_and_never_cached_as_a_miss(self):
        with self.patched([TimeoutError(), None, None]):
            self.assertTrue(self.ask().json()["unavailable"])
        with self.patched([answer()]):
            self.assertTrue(self.ask().json()["found"])

    def test_non_object_json_is_unavailable_instead_of_crashing(self):
        with self.patched([["bad"], None, None]):
            response = self.ask()
        self.assertEqual(response.status_code, 200)
        self.assertTrue(response.json()["unavailable"])

    def test_a_legacy_negative_cache_does_not_hide_a_recovered_product(self):
        cache.set(f"gtin:v2:{CERAVE}", lookup.Info(found=False).__dict__, 86400)
        with self.patched([answer()]):
            self.assertTrue(self.ask().json()["found"])

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


@override_settings(BARCODE_LOOKUP_UPCITEMDB_ENABLED=True)
class ExtraSourceTests(BarcodeInfoCase):
    @staticmethod
    def extra(code=OTHER):
        return {
            "code": "OK",
            "items": [
                {
                    "ean": code,
                    "title": "Engine oil 5W-30",
                    "brand": "Example",
                    "size": "1 L",
                    "category": "Motor oil",
                    "lowest_recorded_price": 9,
                }
            ],
        }

    def test_extra_source_adds_exact_code_automotive_metadata_without_prices(self):
        with self.patched([None, None, None, self.extra()]) as fetch:
            data = self.ask(OTHER).json()
            again = self.ask(OTHER).json()
        self.assertTrue(data["found"])
        self.assertEqual(data["source"], "UPCitemdb")
        self.assertEqual(data["category"], "Motor oil")
        self.assertNotIn("lowest_recorded_price", data)
        self.assertEqual(data, again)
        self.assertEqual(fetch.call_count, 4)

    def test_extra_source_may_recover_after_other_sources_fail(self):
        with self.patched([TimeoutError(), None, None, self.extra()]):
            self.assertTrue(self.ask(OTHER).json()["found"])

    def test_mismatched_code_is_never_used(self):
        with self.patched([None, None, None, self.extra(CERAVE)]):
            self.assertFalse(self.ask(OTHER).json()["found"])

    def test_burst_gate_skips_the_extra_network_call_without_caching_a_miss(self):
        cache.set("barcode:upcitemdb:gate", True, 11)
        with self.patched([None, None, None]) as fetch:
            self.assertTrue(self.ask(OTHER).json()["unavailable"])
        self.assertEqual(fetch.call_count, 3)
        cache.delete("barcode:upcitemdb:gate")
        with self.patched([None, None, None, self.extra()]):
            self.assertTrue(self.ask(OTHER).json()["found"])

    def test_daily_quota_is_respected(self):
        from datetime import UTC, datetime

        day = datetime.now(UTC).date().isoformat()
        cache.set(f"barcode:upcitemdb:day:{day}", 100, 86400)
        with self.patched([None, None, None]) as fetch:
            self.assertTrue(self.ask(OTHER).json()["unavailable"])
        self.assertEqual(fetch.call_count, 3)

    def test_upstream_throttling_is_not_a_product_miss(self):
        error = urllib.error.HTTPError("https://api.upcitemdb.com/", 429, "limit", {}, None)
        with self.patched([None, None, None, error]):
            self.assertTrue(self.ask(OTHER).json()["unavailable"])

    def test_all_sources_can_return_a_genuine_miss(self):
        with self.patched([None, None, None, {"code": "OK", "items": []}]):
            data = self.ask(OTHER).json()
        self.assertEqual((data["found"], data["unavailable"]), (False, False))


@override_settings(BARCODE_LOOKUP_GTINHUB_ENABLED=True)
class GtinHubTests(BarcodeInfoCase):
    def test_the_fifth_source_can_find_a_part_and_never_exposes_prices(self):
        reply = {
            "found": True,
            "product": {
                "gtin": OTHER,
                "name": "Oil filter",
                "brand": "Parts maker",
                "category": "Filters",
                "price": 99,
            },
        }
        with self.patched([None, None, None, reply]) as fetch:
            data = self.ask(OTHER).json()
        self.assertTrue(data["found"])
        self.assertEqual(data["source"], "GTINHub")
        self.assertEqual(data["name"], "Oil filter")
        self.assertNotIn("price", data)
        self.assertEqual(fetch.call_count, 4)  # UPC disabled in this test

    def test_a_hub_miss_is_normal_but_a_bad_identifier_is_not(self):
        with self.patched([None, None, None, {"found": False}]):
            self.assertFalse(self.ask(OTHER).json()["unavailable"])
        cache.clear()
        with self.patched(
            [None, None, None, {"found": True, "product": {"gtin": CERAVE, "name": "Wrong part"}}]
        ):
            self.assertTrue(self.ask(OTHER).json()["unavailable"])

    def test_hub_daily_limit_does_not_call_the_api(self):
        from datetime import UTC, datetime

        day = datetime.now(UTC).date().isoformat()
        cache.set(f"barcode:gtinhub:day:{day}", 10, 86400)
        with self.patched([None, None, None]) as fetch:
            self.assertTrue(self.ask(OTHER).json()["unavailable"])
        self.assertEqual(fetch.call_count, 3)


class NormalizationAndBudgetTests(BarcodeInfoCase):
    def test_zero_padded_representations_share_a_success_cache(self):
        with self.patched([answer()]) as fetch:
            self.assertTrue(self.ask("036000291452").json()["found"])
            self.assertTrue(self.ask("0036000291452").json()["found"])
            self.assertTrue(self.ask("00036000291452").json()["found"])
        self.assertEqual(fetch.call_count, 1)

    def test_nonzero_carton_indicator_is_not_the_retail_code(self):
        self.assertNotEqual(lookup.canonical_gtin("14006381333938"), lookup.canonical_gtin(OTHER))

    def test_localized_names_are_used_when_the_generic_name_is_missing(self):
        reply = {"status": 1, "product": {"product_name_ru": "Масляный фильтр", "brands": "X"}}
        with self.patched([reply]):
            self.assertEqual(self.ask().json()["name"], "Масляный фильтр")

    def test_mismatched_facts_code_never_becomes_a_suggestion(self):
        reply = answer()
        reply["product"]["code"] = OTHER
        with self.patched([reply, None, None]):
            self.assertTrue(self.ask().json()["unavailable"])

    def test_expired_budget_never_starts_another_network_request(self):
        with mock.patch.object(lookup, "monotonic", return_value=11), self.patched([]) as fetch:
            with self.assertRaises(TimeoutError):
                lookup._fetch_before("https://example.test/", 10)
        fetch.assert_not_called()
