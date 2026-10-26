import uuid
from datetime import date, timedelta
from decimal import Decimal
from unittest.mock import patch

from apps.businesses.models import Role
from apps.common.testing import APITestCase
from apps.inventory.models import CostLayer
from apps.inventory.tests.support import World, ledger_differences


class ExpiryTests(APITestCase):
    def setUp(self):
        super().setUp()
        self.w = World()
        self.client = self.w.api[Role.OWNER]
        self.today = date(2026, 10, 26)
        clock = patch("apps.businesses.models.Business.local_today", return_value=self.today)
        clock.start()
        self.addCleanup(clock.stop)

    def tearDown(self):
        self.assertEqual(ledger_differences(), [])
        super().tearDown()

    def post(self, path, data, key=None):
        response = self.client.post(
            self.w.base + path, data, format="json", HTTP_IDEMPOTENCY_KEY=str(key or uuid.uuid4())
        )
        self.assertIn(response.status_code, (200, 201), response.content)
        return response.json()

    def receive(self, day=None, quantity=5, location=None, key=None):
        return self.post(
            "/intakes/",
            {
                "location": str((location or self.w.store).pk),
                "lines": [
                    {
                        "product": str(self.w.pad.pk),
                        "quantity": str(quantity),
                        "expiry_date": day.isoformat() if day else None,
                    }
                ],
            },
            key,
        )

    def product(self, client=None, **query):
        response = (client or self.client).get(self.w.base + "/products/", query)
        self.assertEqual(response.status_code, 200, response.content)
        return response.json()

    def test_optional_date_and_separate_batches_and_exact_quantities(self):
        self.receive()
        early = self.today + timedelta(days=3)
        late = self.today + timedelta(days=60)
        data = self.receive(early, 2)
        self.receive(late, 7)
        self.assertEqual(data["lines"][0]["expiry_date"], early.isoformat())
        self.assertEqual(
            set(CostLayer.objects.values_list("expiry_date", flat=True)), {None, early, late}
        )
        product = next(p for p in self.product()["results"] if p["id"] == str(self.w.pad.pk))
        self.assertEqual(product["stock"]["on_hand"], "14.000")
        self.assertEqual(
            product["expiry"], {"date": early.isoformat(), "quantity": "2.000", "status": "soon"}
        )

    def test_duplicate_request_keeps_one_batch(self):
        key = uuid.uuid4()
        first = self.receive(self.today, 8, key=key)
        self.assertEqual(self.receive(self.today, 8, key=key), first)
        self.assertEqual(CostLayer.objects.count(), 1)

    def test_bad_calendar_date_has_no_stock_or_document_side_effect(self):
        response = self.client.post(
            self.w.base + "/intakes/",
            {
                "location": str(self.w.store.pk),
                "lines": [
                    {"product": str(self.w.pad.pk), "quantity": "2", "expiry_date": "2026-02-31"}
                ],
            },
            format="json",
            HTTP_IDEMPOTENCY_KEY=str(uuid.uuid4()),
        )
        self.assertEqual(response.status_code, 400)
        self.assertEqual(CostLayer.objects.count(), 0)

    def test_expiry_filters_have_inclusive_today_and_thirty_day_boundaries(self):
        self.receive(self.today - timedelta(days=1), 1)
        self.receive(self.today, 2)
        self.receive(self.today + timedelta(days=30), 3)
        self.receive(self.today + timedelta(days=31), 4)
        self.assertEqual(
            self.product(expiry="expired")["results"][0]["expiry"]["quantity"], "1.000"
        )
        # This product also has an expired batch: the soon filter displays the matching date.
        soon = self.product(expiry="soon")["results"][0]
        self.assertEqual(soon["expiry"]["date"], self.today.isoformat())
        self.assertEqual(soon["expiry"]["quantity"], "2.000")
        self.assertEqual(self.product(expiry="soon", q="does-not-exist")["count"], 0)
        self.assertEqual(
            self.client.get(self.w.base + "/products/", {"expiry": "anything"}).status_code, 400
        )

    def test_unknown_dates_and_consumed_batches_do_not_trigger_warnings(self):
        self.receive(None, 2)
        self.assertEqual(self.product(expiry="soon")["count"], 0)
        self.receive(self.today, 3)
        self.w.remove(self.w.pad, self.w.store, 5)
        self.assertEqual(self.product(expiry="soon")["count"], 0)

    def test_fifo_consumption_moves_warning_to_next_remaining_batch(self):
        self.receive(self.today, 2)
        later = self.today + timedelta(days=5)
        self.receive(later, 3)
        self.w.remove(self.w.pad, self.w.store, 2)
        self.assertEqual(
            self.product(expiry="soon")["results"][0]["expiry"]["date"], later.isoformat()
        )

    def test_location_and_business_isolation_for_list_lookup_and_detail(self):
        self.receive(self.today, 2, self.w.store)
        self.receive(self.today + timedelta(days=90), 3, self.w.warehouse)
        seller = self.w.api[Role.SALES]
        keeper = self.w.api[Role.WAREHOUSE]
        self.assertEqual(self.product(keeper, expiry="soon")["count"], 0)
        self.assertEqual(self.product(seller, expiry="soon")["count"], 1)
        for path in (f"/products/{self.w.pad.pk}/", "/barcodes/lookup/?code=BP-1"):
            response = seller.get(self.w.base + path)
            self.assertEqual(response.status_code, 200)
            self.assertEqual(response.json()["stock"]["on_hand"], "2.000")
            self.assertEqual(response.json()["expiry"]["quantity"], "2.000")
            self.assertEqual(self.w.b_api.get(self.w.base + path).status_code, 404)

    def test_transfer_receipt_and_cancellation_preserve_dates(self):
        self.receive(self.today, 6, self.w.warehouse)

        def send():
            return self.post(
                "/transfers/",
                {
                    "from_location": str(self.w.warehouse.pk),
                    "to_location": str(self.w.store.pk),
                    "lines": [{"product": str(self.w.pad.pk), "quantity": "2"}],
                },
            )

        transfer = send()
        self.post(
            f"/transfers/{transfer['id']}/receive/",
            {
                "lines": [{"line": transfer["lines"][0]["id"], "quantity": "2"}],
            },
        )
        transfer = send()
        self.post(f"/transfers/{transfer['id']}/cancel/", {"reason": "Test"})
        self.assertEqual(set(CostLayer.objects.values_list("expiry_date", flat=True)), {self.today})

    def test_sale_returns_preserve_each_original_fifo_date(self):
        self.receive(self.today, 2)
        later = self.today + timedelta(days=8)
        self.receive(later, 4)
        sale = self.post(
            "/sales/",
            {
                "location": str(self.w.store.pk),
                "lines": [{"product": str(self.w.pad.pk), "quantity": "4", "unit_price": "10.00"}],
            },
        )
        self.post(
            f"/sales/{sale['id']}/returns/",
            {
                "reason": "Test",
                "lines": [
                    {"sale_line": sale["lines"][0]["id"], "quantity": "3", "condition": "sellable"}
                ],
            },
        )
        self.assertEqual(self.product(expiry="soon")["results"][0]["expiry"]["quantity"], "2.000")
        self.assertEqual(CostLayer.objects.filter(expiry_date=later).count(), 2)
        self.assertEqual(
            sum(CostLayer.objects.values_list("quantity_remaining", flat=True)), Decimal(5)
        )
