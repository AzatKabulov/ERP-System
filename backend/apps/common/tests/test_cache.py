from django.conf import settings
from django.core.cache import cache

from apps.common.testing import APITestCase


class SharedCacheTests(APITestCase):
    """Throttle counters live in the database cache. With Django's default limit (300 entries)
    a busy shop's looked-up barcode names would make it delete counters at random."""

    def test_counters_survive_a_few_thousand_other_entries(self):
        # Django's culling deletes the keys that sort first, so the counter is named to sort
        # before everything else: with the default limit of 300 it is the first to go.
        cache.set("0-throttle-counter", 4, 3600)
        for index in range(1500):
            cache.set(f"gtin:v2:{index:013d}", {"name": "x"}, 3600)
        self.assertEqual(cache.get("0-throttle-counter"), 4)

    def test_the_limit_is_far_above_the_django_default(self):
        self.assertGreaterEqual(settings.CACHES["default"]["OPTIONS"]["MAX_ENTRIES"], 100_000)
