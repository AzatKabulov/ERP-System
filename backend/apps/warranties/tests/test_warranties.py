import threading
import uuid
from concurrent.futures import ThreadPoolExecutor
from datetime import date, datetime, timedelta
from decimal import Decimal
from io import StringIO
from unittest import mock
from zoneinfo import ZoneInfo

from django.core.management import CommandError, call_command
from django.db import DatabaseError, IntegrityError, connections, transaction
from django.test import SimpleTestCase
from rest_framework.test import APIClient

from apps.audit.models import AuditEvent
from apps.businesses.models import Business, Role
from apps.catalog.models import Product
from apps.common.testing import APITestCase, APITransactionTestCase, client_for
from apps.inventory.models import StockBalance, StockMovement
from apps.inventory.tests.support import World, ledger_differences, make_product
from apps.sales.models import Customer, SaleReturn
from apps.warranties import services
from apps.warranties.entitlement import add_months
from apps.warranties.models import WarrantyClaim, WarrantyEvent

D = Decimal


def local_day(business, sale) -> date:
    """The day a sale (as the API shows it) was made, in the business's time zone."""
    moment = datetime.fromisoformat(sale["created_at"].replace("Z", "+00:00"))
    return moment.astimezone(ZoneInfo(business.timezone)).date()


class WarrantyCase(APITestCase):
    def setUp(self):
        super().setUp()
        self.w = World()
        self.owner = self.w.api[Role.OWNER]
        self.manager = self.w.api[Role.MANAGER]
        self.sales = self.w.api[Role.SALES]
        self.store = self.w.store
        Product.objects.filter(pk=self.w.pad.pk).update(
            warranty_months=6, warranty_terms="Six months, receipt needed"
        )
        self.w.pad.refresh_from_db()
        # two batches: 5 at 50.00, then 5 at 60.00
        self.w.stock(self.w.pad, self.store, 5, "50.00")
        self.w.stock(self.w.pad, self.store, 5, "60.00")

    def tearDown(self):
        self.assertEqual(ledger_differences(), [])
        super().tearDown()

    # -- helpers ------------------------------------------------------------------------
    def product_with(self, months, sku=None, unit=None, name=None, stock=20, **fields):
        sku = sku or f"W-{months}-{Product.objects.count()}"
        product = make_product(self.w.a, sku, name or f"Item {sku}", unit or self.w.unit, "10.00")
        Product.objects.filter(pk=product.pk).update(warranty_months=months, **fields)
        product.refresh_from_db()
        if stock:
            self.w.stock(product, self.store, stock, "5.00")
        return product

    def sell(self, quantity=7, price="100.00", product=None, client=None, location=None, **extra):
        product = product or self.w.pad
        response = (client or self.owner).post(
            f"{self.w.base}/sales/",
            {
                "location": str((location or self.store).pk),
                "lines": [
                    {"product": str(product.pk), "quantity": str(quantity), "unit_price": price}
                ],
                **extra,
            },
            format="json",
            HTTP_IDEMPOTENCY_KEY=str(uuid.uuid4()),
        )
        self.assertEqual(response.status_code, 201, response.content)
        return response.json()

    def open(self, sale, quantity=1, client=None, problem="It squeaks", **extra):
        return (client or self.sales).post(
            f"{self.w.base}/warranty-claims/",
            {
                "sale_line": sale["lines"][0]["id"],
                "quantity": str(quantity),
                "problem": problem,
                **extra,
            },
            format="json",
        )

    def opened(self, sale, quantity=1, **kwargs):
        response = self.open(sale, quantity, **kwargs)
        self.assertEqual(response.status_code, 201, response.content)
        return response.json()

    def close(self, claim, outcome, note="", *, client=None, key=None, **extra):
        return (client or self.owner).post(
            f"{self.w.base}/warranty-claims/{claim['id']}/close/",
            {"outcome": outcome, "note": note, **extra},
            format="json",
            HTTP_IDEMPOTENCY_KEY=str(key or uuid.uuid4()),
        )

    def closed(self, claim, outcome, note="", **kwargs):
        response = self.close(claim, outcome, note, **kwargs)
        self.assertEqual(response.status_code, 200, response.content)
        return response.json()

    def on(self, day):
        """Pretend today is `day` in the business's time zone."""
        return mock.patch.object(Business, "local_today", return_value=day)

    def sold_on(self, day):
        """Pretend sales were made on `day` (for the warranty arithmetic only)."""
        return mock.patch("apps.warranties.entitlement.sale_day", return_value=day)

    def on_hand(self, condition="sellable", product=None):
        row = StockBalance.objects.filter(
            product=product or self.w.pad, location=self.store, condition=condition
        ).first()
        return row.quantity if row else D(0)

    def error(self, response):
        return response.json()["error"]


class AddMonthsTests(SimpleTestCase):
    def test_months_are_added_and_clamped_to_the_end_of_the_month(self):
        cases = [
            (date(2026, 10, 7), 6, date(2027, 4, 7)),
            (date(2026, 1, 31), 1, date(2026, 2, 28)),
            (date(2028, 1, 31), 1, date(2028, 2, 29)),  # a leap year
            (date(2026, 3, 31), 1, date(2026, 4, 30)),
            (date(2026, 8, 31), 6, date(2027, 2, 28)),
            (date(2026, 11, 30), 3, date(2027, 2, 28)),
            (date(2026, 12, 31), 12, date(2027, 12, 31)),
            (date(2026, 12, 15), 1, date(2027, 1, 15)),  # across the new year
            (date(2026, 1, 15), 120, date(2036, 1, 15)),
            (date(2024, 2, 29), 12, date(2025, 2, 28)),
            (date(2024, 2, 29), 48, date(2028, 2, 29)),
            (date(2026, 5, 10), 0, date(2026, 5, 10)),
        ]
        for start, months, expected in cases:
            with self.subTest(start=start, months=months):
                self.assertEqual(add_months(start, months), expected)


class EntitlementTests(WarrantyCase):
    def test_the_last_day_of_the_warranty_is_included(self):
        sale = self.sell(2)
        until = add_months(local_day(self.w.a, sale), 6)
        self.assertEqual(sale["lines"][0]["warranty_until"], until.isoformat())
        with self.on(until):
            claim = self.opened(sale)
        self.assertFalse(claim["out_of_warranty"])
        self.assertEqual(claim["sale_line"]["warranty_until"], until.isoformat())
        with self.on(date.fromordinal(until.toordinal() + 1)):
            response = self.open(sale)
        self.assertEqual(response.status_code, 409)
        error = self.error(response)
        self.assertEqual(error["code"], "warranty_expired")
        self.assertEqual(error["params"], {"until": until.isoformat()})
        self.assertEqual(WarrantyClaim.objects.count(), 1)

    def test_a_sale_at_the_end_of_a_month_is_clamped(self):
        product = self.product_with(1)
        sale = self.sell(2, product=product)
        with self.sold_on(date(2026, 1, 31)):
            with self.on(date(2026, 2, 28)):
                self.assertEqual(self.opened(sale)["sale_line"]["warranty_until"], "2026-02-28")
            with self.on(date(2026, 3, 1)):
                response = self.open(sale)
            self.assertEqual(self.error(response)["code"], "warranty_expired")
            self.assertEqual(self.error(response)["params"], {"until": "2026-02-28"})
        with self.sold_on(date(2028, 1, 31)), self.on(date(2028, 2, 29)):
            self.assertEqual(self.opened(sale)["sale_line"]["warranty_until"], "2028-02-29")

    def test_a_product_without_warranty_is_refused_with_its_own_code(self):
        sale = self.sell(2, product=self.product_with(0))
        self.assertIsNone(sale["lines"][0]["warranty_until"])
        response = self.open(sale)
        self.assertEqual(response.status_code, 409)
        self.assertEqual(self.error(response)["code"], "no_warranty")
        self.assertEqual(self.open(sale, client=self.manager).status_code, 409)  # not for a manager
        self.assertFalse(WarrantyClaim.objects.exists())

    def test_the_sale_line_shows_when_its_warranty_ends(self):
        covered = self.sell(1)
        bare = self.sell(1, product=self.product_with(0))
        until = add_months(local_day(self.w.a, covered), 6).isoformat()
        for sale in (covered, self.owner.get(f"{self.w.base}/sales/{covered['id']}/").json()):
            self.assertEqual(sale["lines"][0]["warranty_until"], until)
            self.assertEqual(sale["lines"][0]["warranty_months"], 6)
        self.assertIsNone(bare["lines"][0]["warranty_until"])
        # a later catalog edit never moves a sale's warranty
        Product.objects.filter(pk=self.w.pad.pk).update(warranty_months=24)
        again = self.owner.get(f"{self.w.base}/sales/{covered['id']}/").json()
        self.assertEqual(again["lines"][0]["warranty_until"], until)

    def test_the_catalog_edit_after_the_sale_does_not_change_the_claim(self):
        sale = self.sell(1)
        Product.objects.filter(pk=self.w.pad.pk).update(warranty_months=0)
        self.assertEqual(self.open(sale).status_code, 201)


class OverrideTests(WarrantyCase):
    def expired(self, sale):
        """Pretend it is the day after the warranty of `sale` ran out."""
        return self.on(add_months(local_day(self.w.a, sale), 6) + timedelta(days=1))

    def test_a_seller_cannot_override(self):
        sale = self.sell(2)
        with self.expired(sale):
            plain = self.open(sale)
            self.assertEqual(plain.status_code, 409)
            forced = self.open(sale, override=True, override_note="Regular customer")
        self.assertEqual(forced.status_code, 403)
        self.assertEqual(self.error(forced)["code"], "permission_denied")
        self.assertFalse(WarrantyClaim.objects.exists())

    def test_a_seller_cannot_use_the_flag_even_when_it_is_not_needed(self):
        sale = self.sell(2)
        response = self.open(sale, override=True, override_note="x")
        self.assertEqual(response.status_code, 403)
        self.assertEqual(self.open(sale, override=False).status_code, 201)

    def test_owner_and_manager_accept_an_expired_claim_with_a_note(self):
        sale = self.sell(3)
        for client, role in ((self.owner, Role.OWNER), (self.manager, Role.MANAGER)):
            with self.subTest(role=role), self.expired(sale):
                response = self.open(
                    sale,
                    client=client,
                    override=True,
                    override_note="  Regular customer, ok  ",
                )
                self.assertEqual(response.status_code, 201, response.content)
                claim = response.json()
                self.assertTrue(claim["out_of_warranty"])
                self.assertEqual(claim["opened_by"]["id"], str(self.w.users[role].pk))
                self.assertEqual(len(claim["events"]), 1)
                self.assertEqual(claim["events"][0]["kind"], "opened")
                self.assertEqual(claim["events"][0]["note"], "Regular customer, ok")
                self.assertEqual(claim["events"][0]["actor"]["id"], str(self.w.users[role].pk))
        audit = AuditEvent.objects.filter(action="warranty.opened").order_by("created_at")[0]
        self.assertTrue(audit.metadata["out_of_warranty"])
        self.assertEqual(audit.metadata["override_note"], "Regular customer, ok")

    def test_the_note_is_mandatory(self):
        sale = self.sell(2)
        with self.expired(sale):
            for extra in (
                {"override": True},
                {"override": True, "override_note": ""},
                {"override": True, "override_note": "   "},
            ):
                with self.subTest(extra=extra):
                    response = self.open(sale, client=self.owner, **extra)
                    self.assertEqual(response.status_code, 400)
                    self.assertIn("override_note", self.error(response)["fields"])
            # without the flag the owner is refused like everybody else
            self.assertEqual(self.open(sale, client=self.owner).status_code, 409)
        self.assertFalse(WarrantyClaim.objects.exists())

    def test_a_product_without_warranty_can_be_accepted_by_the_owner(self):
        sale = self.sell(2, product=self.product_with(0))
        claim = self.opened(
            sale, client=self.owner, override=True, override_note="Goodwill, long-time client"
        )
        self.assertTrue(claim["out_of_warranty"])
        self.assertIsNone(claim["sale_line"]["warranty_until"])
        self.assertEqual(claim["sale_line"]["warranty_months"], 0)

    def test_the_override_of_a_claim_that_needs_none_changes_nothing(self):
        sale = self.sell(2)
        claim = self.opened(sale, client=self.owner, override=True, override_note="just in case")
        self.assertFalse(claim["out_of_warranty"])
        self.assertEqual(claim["events"][0]["note"], "")


class OpeningTests(WarrantyCase):
    def test_the_claim_has_the_documented_shape(self):
        customer = Customer.objects.create(
            business=self.w.a, name="Aýgül Şäher", phone="+99365000000"
        )
        sale = self.sell(7, price="80.00", customer=str(customer.pk))
        claim = self.opened(sale, 2, problem="Дребезжит при торможении")
        line = sale["lines"][0]
        seller = self.w.users[Role.SALES]
        self.assertEqual(
            set(claim),
            {
                "id",
                "number",
                "status",
                "outcome",
                "out_of_warranty",
                "sale",
                "sale_line",
                "product",
                "quantity",
                "customer_name",
                "customer_phone",
                "problem",
                "resolution_note",
                "return",
                "opened_by",
                "opened_at",
                "closed_at",
                "events",
            },
        )
        self.assertEqual(claim["number"], 1)
        self.assertEqual((claim["status"], claim["outcome"]), ("open", None))
        self.assertFalse(claim["out_of_warranty"])
        self.assertEqual(claim["sale"], {"id": sale["id"], "number": sale["number"]})
        self.assertEqual(
            claim["sale_line"],
            {
                "id": line["id"],
                "warranty_months": 6,
                "warranty_terms": "Six months, receipt needed",
                "warranty_until": line["warranty_until"],
                "unit_price": "80.00",
                "quantity": "7.000",
            },
        )
        self.assertEqual(
            claim["product"],
            {"sku": "BP-1", "name": "Brake pad", "unit_symbol": "pc", "unit_decimals": 0},
        )
        self.assertEqual(claim["quantity"], "2.000")
        self.assertEqual(claim["customer_name"], "Aýgül Şäher")
        self.assertEqual(claim["customer_phone"], "+99365000000")
        self.assertEqual(claim["problem"], "Дребезжит при торможении")
        self.assertEqual(claim["resolution_note"], "")
        self.assertIsNone(claim["return"])
        self.assertEqual(claim["opened_by"], {"id": str(seller.pk), "name": seller.username})
        self.assertIsNone(claim["closed_at"])
        self.assertTrue(claim["opened_at"])
        self.assertEqual(len(claim["events"]), 1)
        event = claim["events"][0]
        self.assertEqual((event["kind"], event["note"], event["outcome"]), ("opened", "", None))
        self.assertEqual(event["actor"]["id"], str(seller.pk))
        self.assertEqual(AuditEvent.objects.filter(action="warranty.opened").count(), 1)

    def test_the_snapshots_do_not_follow_later_edits(self):
        customer = Customer.objects.create(business=self.w.a, name="Old Name", phone="111")
        sale = self.sell(2, customer=str(customer.pk))
        claim = self.opened(sale)
        Customer.objects.filter(pk=customer.pk).update(name="New Name", phone="222")
        Product.objects.filter(pk=self.w.pad.pk).update(name="Renamed", sku="NEW-SKU")
        shown = self.owner.get(f"{self.w.base}/warranty-claims/{claim['id']}/").json()
        self.assertEqual((shown["customer_name"], shown["customer_phone"]), ("Old Name", "111"))
        self.assertEqual((shown["product"]["sku"], shown["product"]["name"]), ("BP-1", "Brake pad"))

    def test_a_walk_in_sale_has_no_customer(self):
        claim = self.opened(self.sell(1))
        self.assertEqual((claim["customer_name"], claim["customer_phone"]), ("", ""))

    def test_numbers_run_per_business(self):
        sale = self.sell(5)
        self.assertEqual([self.opened(sale)["number"] for _ in range(3)], [1, 2, 3])
        b_base = f"/api/v1/businesses/{self.w.b.pk}"
        self.assertEqual(WarrantyClaim.objects.filter(business=self.w.a).count(), 3)
        self.assertEqual(self.w.b_api.get(f"{b_base}/warranty-claims/").json()["count"], 0)

    def test_the_quantity_cannot_exceed_what_was_sold(self):
        sale = self.sell(3)
        over = self.open(sale, 4)
        self.assertEqual(over.status_code, 409)
        self.assertEqual(self.error(over)["code"], "over_claim")
        self.assertEqual(self.error(over)["params"], {"claimable": "3.000"})
        self.assertEqual(self.open(sale, 3).status_code, 201)

    def test_what_a_customer_already_returned_cannot_be_claimed(self):
        sale = self.sell(5)
        back = self.sales.post(
            f"{self.w.base}/sales/{sale['id']}/returns/",
            {
                "reason": "Did not fit",
                "lines": [{"sale_line": sale["lines"][0]["id"], "quantity": "2"}],
            },
            format="json",
            HTTP_IDEMPOTENCY_KEY=str(uuid.uuid4()),
        )
        self.assertEqual(back.status_code, 201, back.content)
        over = self.open(sale, 4)
        self.assertEqual(self.error(over)["code"], "over_claim")
        self.assertEqual(self.error(over)["params"], {"claimable": "3.000"})
        self.assertEqual(self.open(sale, 3).status_code, 201)

    def test_a_fully_returned_line_has_nothing_left_to_claim(self):
        sale = self.sell(2)
        self.sales.post(
            f"{self.w.base}/sales/{sale['id']}/returns/",
            {"reason": "x", "lines": [{"sale_line": sale["lines"][0]["id"], "quantity": "2"}]},
            format="json",
            HTTP_IDEMPOTENCY_KEY=str(uuid.uuid4()),
        )
        response = self.open(sale, 1)
        self.assertEqual(self.error(response)["code"], "over_claim")
        self.assertEqual(self.error(response)["params"], {"claimable": "0.000"})

    def test_several_claims_may_cover_one_line(self):
        sale = self.sell(5)
        self.assertEqual(self.open(sale, 2).status_code, 201)
        self.assertEqual(self.open(sale, 2).status_code, 201)
        self.assertEqual(WarrantyClaim.objects.count(), 2)

    def test_quantity_follows_the_units_precision_and_must_be_positive(self):
        sale = self.sell(3)
        for quantity in ("0", "-1", "0.5", "abc", "1.0005"):
            with self.subTest(quantity=quantity):
                response = self.open(sale, quantity)
                self.assertEqual(response.status_code, 400, response.content)
        litres = self.product_with(6, unit=self.w.litre, name="Oil")
        oil = self.sell("5.00", product=litres)
        self.assertEqual(self.open(oil, "1.5").status_code, 201)
        self.assertEqual(self.open(oil, "1.555").status_code, 400)

    def test_the_problem_is_required_and_limited(self):
        sale = self.sell(1)
        for problem in ("", "   "):
            response = self.open(sale, 1, problem=problem)
            self.assertEqual(response.status_code, 400)
            self.assertIn("problem", self.error(response)["fields"])
        self.assertEqual(self.open(sale, 1, problem="x" * 1001).status_code, 400)
        self.assertEqual(self.open(sale, 1, problem="x" * 1000).status_code, 201)
        self.assertEqual(
            self.sales.post(f"{self.w.base}/warranty-claims/", {}, format="json").status_code, 400
        )

    def test_a_sale_line_of_another_business_or_an_unknown_one_is_refused(self):
        b_base = f"/api/v1/businesses/{self.w.b.pk}"
        line = self.sell(1)["lines"][0]["id"]
        body = {"quantity": "1", "problem": "x"}
        theirs = self.w.b_api.post(
            f"{b_base}/warranty-claims/", {"sale_line": line, **body}, format="json"
        )
        unknown = self.owner.post(
            f"{self.w.base}/warranty-claims/",
            {"sale_line": str(uuid.uuid4()), **body},
            format="json",
        )
        for response in (theirs, unknown):
            self.assertEqual(response.status_code, 400, response.content)
            code = self.error(response)["fields"]["sale_line"][0]["code"]
            self.assertEqual(code, "does_not_exist")
        self.assertFalse(WarrantyClaim.objects.exists())

    def test_a_seller_cannot_open_a_claim_for_another_locations_sale(self):
        product = self.product_with(6, stock=0)
        self.w.stock(product, self.w.warehouse, 5, "5.00")
        sale = self.sell(2, location=self.w.warehouse, product=product)  # sold by the owner
        self.assertEqual(sale["location"]["id"], str(self.w.warehouse.pk))
        response = self.open(sale, 1)
        self.assertEqual(response.status_code, 403)
        self.assertEqual(self.error(response)["code"], "location_not_permitted")
        self.assertEqual(self.open(sale, 1, client=self.owner).status_code, 201)


class NotesTests(WarrantyCase):
    def test_notes_are_added_in_order(self):
        claim = self.opened(self.sell(2))
        url = f"{self.w.base}/warranty-claims/{claim['id']}/notes/"
        first = self.sales.post(url, {"note": "Customer will bring the receipt"}, format="json")
        self.assertEqual(first.status_code, 201, first.content)
        second = self.manager.post(url, {"note": "Receipt seen"}, format="json")
        events = second.json()["events"]
        self.assertEqual([e["kind"] for e in events], ["opened", "note", "note"])
        self.assertEqual(
            [e["note"] for e in events[1:]], ["Customer will bring the receipt", "Receipt seen"]
        )
        self.assertEqual(events[2]["actor"]["id"], str(self.w.users[Role.MANAGER].pk))
        self.assertEqual(AuditEvent.objects.filter(action="warranty.noted").count(), 2)

    def test_a_note_cannot_be_blank_or_added_to_a_closed_claim(self):
        claim = self.opened(self.sell(2))
        url = f"{self.w.base}/warranty-claims/{claim['id']}/notes/"
        for note in ("", "  ", None):
            self.assertEqual(self.sales.post(url, {"note": note}, format="json").status_code, 400)
        self.assertEqual(self.sales.post(url, {"note": "x" * 1001}, format="json").status_code, 400)
        self.closed(claim, "repair")
        late = self.sales.post(url, {"note": "Too late"}, format="json")
        self.assertEqual(late.status_code, 409)
        self.assertEqual(self.error(late)["code"], "claim_closed")
        self.assertEqual(WarrantyEvent.objects.filter(kind="note").count(), 0)

    def test_the_events_are_append_only(self):
        claim = self.opened(self.sell(1))
        event = WarrantyEvent.objects.get(claim_id=claim["id"])
        event.note = "changed"
        with self.assertRaises(RuntimeError):
            event.save()
        with self.assertRaises(RuntimeError):
            event.delete()
        with self.assertRaises(DatabaseError), transaction.atomic():
            WarrantyEvent.objects.filter(pk=event.pk).update(note="changed")


class CloseTests(WarrantyCase):
    def test_a_repair_moves_nothing(self):
        sale = self.sell(3)
        claim = self.opened(sale, 2)
        before = (self.on_hand(), self.on_hand("damaged"), StockMovement.objects.count())
        closed = self.closed(claim, "repair", "Pads reseated")
        self.assertEqual((closed["status"], closed["outcome"]), ("closed", "repair"))
        self.assertEqual(closed["resolution_note"], "Pads reseated")
        self.assertIsNotNone(closed["closed_at"])
        self.assertIsNone(closed["return"])
        self.assertEqual(
            (self.on_hand(), self.on_hand("damaged"), StockMovement.objects.count()), before
        )
        self.assertEqual([e["kind"] for e in closed["events"]], ["opened", "closed"])
        last = closed["events"][-1]
        self.assertEqual((last["outcome"], last["note"]), ("repair", "Pads reseated"))
        row = WarrantyClaim.objects.get(pk=claim["id"])
        self.assertEqual((row.closed_by, row.return_id), (self.w.owner, None))
        self.assertEqual(
            AuditEvent.objects.get(action="warranty.closed").metadata["outcome"], "repair"
        )

    def test_a_note_is_optional_for_a_repair_but_required_for_a_rejection(self):
        claim = self.opened(self.sell(2))
        for note in ("", "   "):
            response = self.close(claim, "rejected", note)
            self.assertEqual(response.status_code, 400)
            self.assertIn("note", self.error(response)["fields"])
        self.assertEqual(self.close(claim, "rejected").status_code, 400)
        self.assertEqual(WarrantyClaim.objects.get(pk=claim["id"]).status, "open")
        closed = self.closed(claim, "rejected", "Damage from a crash, not a defect")
        self.assertEqual(closed["outcome"], "rejected")
        self.assertEqual(StockMovement.objects.filter(document_type="warranty").count(), 0)
        again = self.opened(self.sell(1))
        self.assertEqual(self.closed(again, "repair")["resolution_note"], "")

    def test_the_outcome_must_be_one_of_the_four(self):
        claim = self.opened(self.sell(1))
        self.assertEqual(self.close(claim, "gift").status_code, 400)
        self.assertEqual(self.close(claim, "").status_code, 400)
        self.assertEqual(self.close(claim, "repair", "x" * 501).status_code, 400)
        self.assertEqual(
            self.owner.post(
                f"{self.w.base}/warranty-claims/{claim['id']}/close/",
                {},
                format="json",
                HTTP_IDEMPOTENCY_KEY=str(uuid.uuid4()),
            ).status_code,
            400,
        )

    def test_a_replacement_swaps_one_for_one_at_the_cost_the_unit_was_sold_at(self):
        sale = self.sell(7)  # slices: 5 at 50.00 and 2 at 60.00 = 370.00; 3 left at 60.00
        claim = self.opened(sale, 2)
        self.assertEqual((self.on_hand(), self.on_hand("damaged")), (D(3), D(0)))
        closed = self.closed(claim, "replacement", "Swapped at the counter")
        self.assertEqual(closed["outcome"], "replacement")
        self.assertIsNone(closed["return"])
        self.assertEqual((self.on_hand(), self.on_hand("damaged")), (D(1), D(2)))
        moves = StockMovement.objects.filter(document_type="warranty", document_id=claim["id"])
        self.assertEqual(moves.count(), 2)
        out = moves.get(movement_type="warranty_out")
        into = moves.get(movement_type="warranty_in")
        self.assertEqual(
            (out.quantity, out.condition, out.unit_cost), (D(-2), "sellable", D("60.00"))
        )
        self.assertEqual(
            (into.quantity, into.condition, into.unit_cost), (D(2), "damaged", D("52.86"))
        )  # 370.00 / 7 = 52.857...
        self.assertEqual({m.location_id for m in moves}, {self.store.pk})
        self.assertEqual({m.reason for m in moves}, {"Warranty W-0001"})
        self.assertEqual({m.actor_id for m in moves}, {self.w.owner.pk})
        self.assertEqual({m.product_id for m in moves}, {self.w.pad.pk})

    def test_the_average_cost_is_rounded_half_up(self):
        product = self.product_with(6, stock=0, name="Spark plug")
        self.w.stock(product, self.store, 1, "10.00")
        self.w.stock(product, self.store, 1, "10.01")
        self.w.stock(product, self.store, 3, "7.00")
        sale = self.sell(2, product=product)  # cost 20.01 -> 10.005 a unit -> 10.01, not 10.00
        claim = self.opened(sale, 1)
        self.closed(claim, "replacement")
        into = StockMovement.objects.get(movement_type="warranty_in")
        self.assertEqual((into.quantity, into.unit_cost), (D(1), D("10.01")))
        out = StockMovement.objects.get(movement_type="warranty_out")
        self.assertEqual((out.quantity, out.unit_cost), (D(-1), D("7.00")))

    def test_a_replacement_needs_stock_and_otherwise_changes_nothing(self):
        sale = self.sell(10)  # everything sold: nothing to replace with
        claim = self.opened(sale, 1)
        response = self.close(claim, "replacement")
        self.assertEqual(response.status_code, 409)
        self.assertEqual(self.error(response)["code"], "insufficient_stock")
        row = WarrantyClaim.objects.get(pk=claim["id"])
        self.assertEqual((row.status, row.outcome, row.closed_at), ("open", None, None))
        self.assertFalse(StockMovement.objects.filter(document_type="warranty").exists())
        self.assertEqual(WarrantyEvent.objects.filter(kind="closed").count(), 0)
        self.w.stock(self.w.pad, self.store, 1, "70.00")  # stock arrives: now it can be closed
        self.assertEqual(self.closed(claim, "replacement")["status"], "closed")

    def test_a_refund_is_a_return_of_the_sale_linked_to_the_claim(self):
        sale = self.sell(4, price="80.00")
        claim = self.opened(sale, 2)
        before = self.on_hand()
        closed = self.closed(claim, "refund", "Money back")
        self.assertEqual(closed["outcome"], "refund")
        made = SaleReturn.objects.get()
        self.assertEqual(closed["return"], {"id": str(made.pk), "number": made.number})
        self.assertEqual(made.warranty_claim_id, uuid.UUID(claim["id"]))
        self.assertEqual((made.reason, made.note), ("Warranty W-0001", "Money back"))
        self.assertEqual(made.refund_total, D("160.00"))  # what was paid for 2 pieces
        self.assertEqual(made.created_by, self.w.owner)
        line = made.lines.get()
        self.assertEqual((line.quantity, line.condition), (D(2), "damaged"))
        self.assertEqual(str(line.sale_line_id), sale["lines"][0]["id"])
        self.assertEqual(self.on_hand(), before)  # defective goods do not go back on the shelf
        self.assertEqual(self.on_hand("damaged"), D(2))
        shown = self.owner.get(f"{self.w.base}/sales/{sale['id']}/").json()
        self.assertEqual(shown["lines"][0]["returnable_quantity"], "2.000")
        self.assertEqual(shown["lines"][0]["returned_quantity"], "2.000")
        self.assertEqual(
            self.owner.get(f"{self.w.base}/returns/{made.pk}/").json()["number"], made.number
        )

    def test_a_refund_is_accepted_after_the_return_window_has_closed(self):
        product = self.product_with(6, return_days=0, name="Final sale")
        sale = self.sell(2, product=product)
        plain = self.sales.post(
            f"{self.w.base}/sales/{sale['id']}/returns/",
            {"reason": "x", "lines": [{"sale_line": sale["lines"][0]["id"], "quantity": "1"}]},
            format="json",
            HTTP_IDEMPOTENCY_KEY=str(uuid.uuid4()),
        )
        self.assertEqual(self.error(plain)["code"], "returns_not_accepted")  # a normal return: no
        claim = self.opened(sale, 1)
        self.assertEqual(
            self.closed(claim, "refund")["outcome"], "refund"
        )  # a warranty refund: yes
        self.assertEqual(SaleReturn.objects.count(), 1)

    def test_a_refund_respects_what_is_still_returnable(self):
        sale = self.sell(5)
        claim = self.opened(sale, 3)
        back = self.sales.post(
            f"{self.w.base}/sales/{sale['id']}/returns/",
            {"reason": "x", "lines": [{"sale_line": sale["lines"][0]["id"], "quantity": "4"}]},
            format="json",
            HTTP_IDEMPOTENCY_KEY=str(uuid.uuid4()),
        )
        self.assertEqual(back.status_code, 201)
        response = self.close(claim, "refund")
        self.assertEqual(response.status_code, 409)
        self.assertEqual(self.error(response)["code"], "over_return")
        row = WarrantyClaim.objects.get(pk=claim["id"])
        self.assertEqual((row.status, row.return_id), ("open", None))
        self.assertEqual(SaleReturn.objects.count(), 1)  # only the customer's own return
        self.assertEqual(self.closed(claim, "repair")["outcome"], "repair")  # still resolvable

    def test_a_refund_of_an_out_of_warranty_claim_works(self):
        sale = self.sell(2, product=self.product_with(0))
        claim = self.opened(sale, 1, client=self.owner, override=True, override_note="Goodwill")
        closed = self.closed(claim, "refund")
        self.assertTrue(closed["out_of_warranty"])
        self.assertIsNotNone(closed["return"])

    def test_closing_twice_is_refused(self):
        claim = self.opened(self.sell(3), 1)
        self.closed(claim, "replacement")
        again = self.close(claim, "replacement")
        self.assertEqual(again.status_code, 409)
        self.assertEqual(self.error(again)["code"], "claim_closed")
        other = self.close(claim, "refund")
        self.assertEqual(self.error(other)["code"], "claim_closed")
        self.assertEqual(StockMovement.objects.filter(document_type="warranty").count(), 2)
        self.assertEqual(SaleReturn.objects.count(), 0)
        self.assertEqual(WarrantyEvent.objects.filter(kind="closed").count(), 1)

    def test_a_retry_with_the_same_key_replays_the_answer_and_acts_once(self):
        claim = self.opened(self.sell(3), 1)
        key = uuid.uuid4()
        first = self.close(claim, "replacement", "swapped", key=key)
        self.assertEqual(first.status_code, 200)
        self.assertNotIn("Idempotent-Replay", first.headers)
        replay = self.close(claim, "replacement", "swapped", key=key)
        self.assertEqual(replay.status_code, 200)
        self.assertEqual(replay["Idempotent-Replay"], "true")
        self.assertEqual(replay.json(), first.json())
        self.assertEqual(StockMovement.objects.filter(document_type="warranty").count(), 2)
        self.assertEqual(WarrantyEvent.objects.filter(kind="closed").count(), 1)
        reused = self.close(claim, "repair", "swapped", key=key)  # same key, another request
        self.assertEqual(reused.status_code, 422)
        self.assertEqual(self.error(reused)["code"], "idempotency_key_reused")

    def test_a_refund_retry_refunds_once(self):
        claim = self.opened(self.sell(3), 1)
        key = uuid.uuid4()
        self.assertEqual(self.close(claim, "refund", key=key).status_code, 200)
        self.assertEqual(self.close(claim, "refund", key=key).status_code, 200)
        self.assertEqual(SaleReturn.objects.count(), 1)

    def test_the_key_is_required_and_the_lost_answer_can_be_asked_for(self):
        claim = self.opened(self.sell(3), 1)
        missing = self.owner.post(
            f"{self.w.base}/warranty-claims/{claim['id']}/close/",
            {"outcome": "repair", "note": ""},
            format="json",
        )
        self.assertEqual(missing.status_code, 400)
        self.assertEqual(self.error(missing)["code"], "idempotency_key_required")
        self.assertEqual(WarrantyClaim.objects.get(pk=claim["id"]).status, "open")
        key = uuid.uuid4()
        done = self.close(claim, "repair", key=key).json()
        status = self.owner.get(f"{self.w.base}/operations/warranty_resolve/{key}/")
        self.assertEqual(status.status_code, 200)
        self.assertEqual(status.json()["response"]["id"], done["id"])
        self.assertEqual(status.json()["response"]["outcome"], "repair")
        # only the caller's own operations are visible
        other = self.manager.get(f"{self.w.base}/operations/warranty_resolve/{key}/")
        self.assertEqual(other.status_code, 404)

    def test_a_failed_close_can_be_retried_with_the_same_key(self):
        claim = self.opened(self.sell(10), 1)
        key = uuid.uuid4()
        self.assertEqual(self.close(claim, "replacement", key=key).status_code, 409)
        self.w.stock(self.w.pad, self.store, 1, "70.00")
        self.assertEqual(self.close(claim, "replacement", key=key).status_code, 200)

    def test_a_manager_may_close_too(self):
        claim = self.opened(self.sell(2), 1)
        closed = self.closed(claim, "repair", client=self.manager)
        self.assertEqual(
            WarrantyClaim.objects.get(pk=claim["id"]).closed_by, self.w.users[Role.MANAGER]
        )
        self.assertEqual(closed["status"], "closed")


class ListAndAccessTests(WarrantyCase):
    def setUp(self):
        super().setUp()
        self.customer = Customer.objects.create(business=self.w.a, name="Şäher Ýüpek", phone="1")
        sale = self.sell(6, customer=str(self.customer.pk))
        self.sale = sale
        self.c1 = self.opened(sale, 1)
        self.c2 = self.opened(sale, 1)
        other = self.sell(2, product=self.product_with(12, name="Тормозные колодки"))
        self.other_sale = other
        self.c3 = self.opened(other, 1)
        self.closed(self.c2, "repair")

    def ids(self, query="", client=None):
        response = (client or self.owner).get(f"{self.w.base}/warranty-claims/{query}")
        self.assertEqual(response.status_code, 200, response.content)
        return [c["id"] for c in response.json()["results"]]

    def test_the_list_is_paginated_newest_first_without_events(self):
        body = self.owner.get(f"{self.w.base}/warranty-claims/").json()
        self.assertEqual(set(body), {"count", "next", "previous", "results"})
        self.assertEqual(body["count"], 3)
        self.assertEqual(
            [c["id"] for c in body["results"]], [self.c3["id"], self.c2["id"], self.c1["id"]]
        )
        self.assertNotIn("events", body["results"][0])
        self.assertEqual(
            set(body["results"][0]) | {"events"}, set(self.c1)
        )  # the same shape as the detail
        page = self.owner.get(f"{self.w.base}/warranty-claims/?limit=2&offset=2").json()
        self.assertEqual([c["id"] for c in page["results"]], [self.c1["id"]])

    def test_a_refund_shows_its_return_in_the_list(self):
        claim = self.opened(self.sell(2), 1)
        self.closed(claim, "refund")
        row = [
            c
            for c in self.owner.get(f"{self.w.base}/warranty-claims/").json()["results"]
            if c["id"] == claim["id"]
        ][0]
        self.assertEqual(row["return"], {"id": str(SaleReturn.objects.get().pk), "number": 1})

    def test_filters(self):
        self.assertEqual(self.ids("?status=open"), [self.c3["id"], self.c1["id"]])
        self.assertEqual(self.ids("?status=closed"), [self.c2["id"]])
        self.assertEqual(self.ids(f"?sale={self.sale['id']}"), [self.c2["id"], self.c1["id"]])
        self.assertEqual(self.ids("?q=W-0003"), [self.c3["id"]])
        self.assertEqual(self.ids("?q=w-3"), [self.c3["id"]])
        self.assertEqual(self.ids("?q=2"), [self.c2["id"]])
        self.assertEqual(self.ids("?q=%C5%9E%C3%84HER"), [self.c2["id"], self.c1["id"]])  # ŞÄHER
        self.assertEqual(self.ids("?q=ýüpek"), [self.c2["id"], self.c1["id"]])
        self.assertEqual(self.ids("?q=%D0%BA%D0%BE%D0%BB%D0%BE%D0%B4%D0%BA%D0%B8"), [self.c3["id"]])
        self.assertEqual(self.ids("?q=brake"), [self.c2["id"], self.c1["id"]])
        self.assertEqual(self.ids("?q=nothing"), [])
        self.assertEqual(self.ids("?status=open&q=brake"), [self.c1["id"]])
        for query in ("?status=weird", "?sale=nope"):
            self.assertEqual(
                self.owner.get(f"{self.w.base}/warranty-claims/{query}").status_code, 400
            )

    def test_sellers_see_their_locations_only(self):
        warehouse_product = self.product_with(6, stock=0, name="Warehouse thing")
        self.w.stock(warehouse_product, self.w.warehouse, 5, "5.00")
        far = self.sell(2, location=self.w.warehouse, product=warehouse_product)
        far_claim = self.opened(far, 1, client=self.owner)
        self.assertEqual(len(self.ids()), 4)  # the owner sees all
        mine = self.ids(client=self.sales)
        self.assertEqual(sorted(mine), sorted([self.c1["id"], self.c2["id"], self.c3["id"]]))
        base = f"{self.w.base}/warranty-claims/{far_claim['id']}/"
        self.assertEqual(self.sales.get(base).status_code, 404)
        self.assertEqual(
            self.sales.post(f"{base}notes/", {"note": "x"}, format="json").status_code, 404
        )
        self.assertEqual(
            self.sales.get(f"{self.w.base}/warranty-claims/{self.c1['id']}/").status_code, 200
        )
        self.assertEqual(self.manager.get(base).status_code, 200)
        self.assertEqual(
            self.owner.get(f"{self.w.base}/warranty-claims/?sale={far['id']}").json()["count"], 1
        )
        self.assertEqual(
            self.sales.get(f"{self.w.base}/warranty-claims/?sale={far['id']}").json()["count"], 0
        )

    def test_roles(self):
        # sales: look, open, add notes; not close
        self.assertEqual(
            self.sales.get(f"{self.w.base}/warranty-claims/{self.c1['id']}/").status_code, 200
        )
        self.assertEqual(
            self.sales.post(
                f"{self.w.base}/warranty-claims/{self.c1['id']}/notes/",
                {"note": "x"},
                format="json",
            ).status_code,
            201,
        )
        self.assertEqual(self.close(self.c1, "repair", client=self.sales).status_code, 403)
        # warehouse: nothing
        warehouse = self.w.api[Role.WAREHOUSE]
        url = f"{self.w.base}/warranty-claims/"
        self.assertEqual(warehouse.get(url).status_code, 403)
        self.assertEqual(warehouse.get(f"{url}{self.c1['id']}/").status_code, 403)
        self.assertEqual(warehouse.post(url, {}, format="json").status_code, 403)
        self.assertEqual(
            warehouse.post(
                f"{url}{self.c1['id']}/notes/", {"note": "x"}, format="json"
            ).status_code,
            403,
        )
        self.assertEqual(self.close(self.c1, "repair", client=warehouse).status_code, 403)
        self.assertEqual(WarrantyClaim.objects.get(pk=self.c1["id"]).status, "open")

    def test_another_business_gets_a_404_everywhere(self):
        b_base = f"/api/v1/businesses/{self.w.b.pk}"
        for base in (self.w.base, b_base):
            url = f"{base}/warranty-claims/{self.c1['id']}/"
            with self.subTest(base=base):
                self.assertEqual(self.w.b_api.get(url).status_code, 404)
                self.assertEqual(
                    self.w.b_api.post(f"{url}notes/", {"note": "x"}, format="json").status_code, 404
                )
                self.assertEqual(
                    self.w.b_api.post(
                        f"{url}close/",
                        {"outcome": "repair"},
                        format="json",
                        HTTP_IDEMPOTENCY_KEY=str(uuid.uuid4()),
                    ).status_code,
                    404,
                )
        self.assertEqual(self.w.b_api.get(f"{self.w.base}/warranty-claims/").status_code, 404)
        self.assertEqual(self.w.b_api.get(f"{b_base}/warranty-claims/").json()["count"], 0)
        self.assertEqual(WarrantyClaim.objects.get(pk=self.c1["id"]).status, "open")
        self.assertEqual(
            self.owner.get(f"{self.w.base}/warranty-claims/{uuid.uuid4()}/").status_code, 404
        )

    def test_nothing_without_signing_in(self):
        anonymous = APIClient()
        self.assertEqual(anonymous.get(f"{self.w.base}/warranty-claims/").status_code, 401)
        self.assertEqual(anonymous.post(f"{self.w.base}/warranty-claims/", {}).status_code, 401)


class ReconcileTests(WarrantyCase):
    """Break things on purpose and see `reconcile` notice. These tests leave the data broken,
    so they do not run the usual end-of-test check."""

    def tearDown(self):
        super(WarrantyCase, self).tearDown()

    def differences(self):
        return services.reconcile()

    def test_a_consistent_ledger_has_no_differences(self):
        self.closed(self.opened(self.sell(1), 1), "repair")
        self.closed(self.opened(self.sell(1), 1), "replacement")
        self.closed(self.opened(self.sell(1), 1), "refund")
        self.closed(self.opened(self.sell(1), 1), "rejected", "no")
        self.opened(self.sell(1), 1)
        self.assertEqual(ledger_differences(), [])
        self.assertEqual(self.differences(), [])

    def test_a_replacement_whose_movements_do_not_match_is_found(self):
        claim = self.opened(self.sell(3), 2)
        self.closed(claim, "replacement")
        WarrantyClaim.objects.filter(pk=claim["id"]).update(quantity=D(1))
        self.assertTrue(any("W-0001" in d for d in self.differences()), self.differences())

    def test_warranty_movements_on_another_outcome_are_found(self):
        claim = self.opened(self.sell(3), 1)
        self.closed(claim, "replacement")
        WarrantyClaim.objects.filter(pk=claim["id"]).update(outcome="repair")
        self.assertTrue(any("warranty_out" in d for d in self.differences()))

    def test_a_replacement_without_movements_is_found(self):
        claim = self.opened(self.sell(3), 1)
        self.closed(claim, "repair")
        WarrantyClaim.objects.filter(pk=claim["id"]).update(outcome="replacement")
        self.assertTrue(any("warranty_out" in d for d in self.differences()))

    def test_a_refund_without_its_return_is_found(self):
        claim = self.opened(self.sell(3), 1)
        self.closed(claim, "refund")
        WarrantyClaim.objects.filter(pk=claim["id"]).update(return_id=None)
        found = self.differences()
        self.assertTrue(any("refund without a return" in d for d in found), found)
        WarrantyClaim.objects.filter(pk=claim["id"]).update(return_id=uuid.uuid4())
        self.assertTrue(any("refund without a return" in d for d in self.differences()))

    def test_a_return_that_took_another_quantity_is_found(self):
        claim = self.opened(self.sell(3), 2)
        self.closed(claim, "refund")
        WarrantyClaim.objects.filter(pk=claim["id"]).update(quantity=D(1))
        self.assertTrue(any("the return took" in d for d in self.differences()))

    def test_a_return_of_a_claim_that_does_not_point_back_is_found(self):
        claim = self.opened(self.sell(3), 1)
        self.closed(claim, "refund")
        WarrantyClaim.objects.filter(pk=claim["id"]).update(outcome="repair", return_id=None)
        found = self.differences()
        self.assertTrue(any("does not point back" in d for d in found), found)

    def test_a_claim_for_more_than_was_sold_is_found(self):
        claim = self.opened(self.sell(3), 1)
        WarrantyClaim.objects.filter(pk=claim["id"]).update(quantity=D(99))
        self.assertTrue(any("claims 99.000 of 3.000 sold" in d for d in self.differences()))

    def test_the_database_refuses_a_closed_claim_without_an_outcome(self):
        claim = self.opened(self.sell(3), 1)
        self.closed(claim, "repair")
        with self.assertRaises(IntegrityError), transaction.atomic():
            WarrantyClaim.objects.filter(pk=claim["id"]).update(outcome=None)
        with self.assertRaises(IntegrityError), transaction.atomic():
            WarrantyClaim.objects.filter(pk=claim["id"]).update(status="open")
        with self.assertRaises(IntegrityError), transaction.atomic():
            WarrantyClaim.objects.filter(pk=claim["id"]).update(return_id=uuid.uuid4())
        with self.assertRaises(IntegrityError), transaction.atomic():
            WarrantyClaim.objects.filter(pk=claim["id"]).update(quantity=D(0))

    def test_the_stock_command_checks_claims_too(self):
        claim = self.opened(self.sell(3), 1)
        self.closed(claim, "replacement")
        out = StringIO()
        call_command("reconcile_stock", stdout=out)
        self.assertIn("consistent", out.getvalue())
        WarrantyClaim.objects.filter(pk=claim["id"]).update(outcome="repair")
        with self.assertRaises(CommandError):
            call_command("reconcile_stock", stdout=StringIO(), stderr=StringIO())


class WarrantyConcurrencyTests(APITransactionTestCase):
    """Real commits and real threads against PostgreSQL."""

    def setUp(self):
        super().setUp()
        self.w = World()
        Product.objects.filter(pk=self.w.pad.pk).update(warranty_months=12)
        self.w.pad.refresh_from_db()
        self.w.stock(self.w.pad, self.w.store, 10, "50.00")
        sale = (
            client_for(self.w.users[Role.SALES])
            .post(
                f"{self.w.base}/sales/",
                {
                    "location": str(self.w.store.pk),
                    "lines": [
                        {"product": str(self.w.pad.pk), "quantity": "6", "unit_price": "100.00"}
                    ],
                },
                format="json",
                HTTP_IDEMPOTENCY_KEY=str(uuid.uuid4()),
            )
            .json()
        )
        self.sale = sale
        self.claim = (
            client_for(self.w.users[Role.SALES])
            .post(
                f"{self.w.base}/warranty-claims/",
                {"sale_line": sale["lines"][0]["id"], "quantity": "1", "problem": "Broken"},
                format="json",
            )
            .json()
        )

    def tearDown(self):
        self.assertEqual(ledger_differences(), [])
        super().tearDown()

    def close(self, outcome, key=None):
        try:
            return client_for(self.w.owner).post(
                f"{self.w.base}/warranty-claims/{self.claim['id']}/close/",
                {"outcome": outcome, "note": "x"},
                format="json",
                HTTP_IDEMPOTENCY_KEY=str(key or uuid.uuid4()),
            )
        finally:
            connections.close_all()

    def parallel(self, calls):
        barrier = threading.Barrier(len(calls))

        def worker(call):
            barrier.wait(timeout=10)
            return call()

        with ThreadPoolExecutor(max_workers=len(calls)) as pool:
            return list(pool.map(worker, calls))

    def test_two_replacements_of_one_claim_make_one_swap(self):
        responses = self.parallel(
            [lambda: self.close("replacement"), lambda: self.close("replacement")]
        )
        self.assertEqual(sorted(r.status_code for r in responses), [200, 409])
        failed = [r for r in responses if r.status_code == 409][0]
        self.assertEqual(failed.json()["error"]["code"], "claim_closed")
        self.assertEqual(StockMovement.objects.filter(document_type="warranty").count(), 2)
        self.assertEqual(WarrantyEvent.objects.filter(kind="closed").count(), 1)

    def test_many_simultaneous_closes_with_different_outcomes_make_exactly_one(self):
        outcomes = ["replacement", "refund", "repair", "rejected", "replacement", "refund"]
        responses = self.parallel([lambda o=o: self.close(o) for o in outcomes])
        codes = sorted(r.status_code for r in responses)
        self.assertEqual(codes, [200] + [409] * 5)
        claim = WarrantyClaim.objects.get(pk=self.claim["id"])
        self.assertEqual(claim.status, "closed")
        self.assertEqual(WarrantyEvent.objects.filter(kind="closed").count(), 1)
        moved = StockMovement.objects.filter(document_type="warranty").count()
        returned = SaleReturn.objects.count()
        self.assertEqual(
            (moved, returned),
            {"replacement": (2, 0), "refund": (0, 1)}.get(claim.outcome, (0, 0)),
        )

    def test_eight_simultaneous_copies_of_one_close_make_one_close(self):
        key = uuid.uuid4()
        responses = self.parallel([lambda: self.close("replacement", key) for _ in range(8)])
        self.assertEqual({r.status_code for r in responses}, {200})
        self.assertEqual(len({r.json()["id"] for r in responses}), 1)
        self.assertEqual(StockMovement.objects.filter(document_type="warranty").count(), 2)

    def test_a_refund_and_a_customer_return_cannot_bring_back_more_than_was_sold(self):
        # 6 sold, a claim for 1 is open: a return of all 6 and the refund race for the last unit
        def customer_return():
            try:
                return client_for(self.w.users[Role.SALES]).post(
                    f"{self.w.base}/sales/{self.sale['id']}/returns/",
                    {
                        "reason": "x",
                        "lines": [{"sale_line": self.sale["lines"][0]["id"], "quantity": "6"}],
                    },
                    format="json",
                    HTTP_IDEMPOTENCY_KEY=str(uuid.uuid4()),
                )
            finally:
                connections.close_all()

        returned_back, refunded = self.parallel([customer_return, lambda: self.close("refund")])
        # whoever got the sale row first wins; the other finds nothing left to bring back
        self.assertIn((returned_back.status_code, refunded.status_code), {(201, 409), (409, 200)})
        if refunded.status_code == 409:
            self.assertEqual(refunded.json()["error"]["code"], "over_return")
            self.assertEqual(WarrantyClaim.objects.get(pk=self.claim["id"]).status, "open")
        taken = sum(
            (line.quantity for ret in SaleReturn.objects.all() for line in ret.lines.all()), D(0)
        )
        self.assertEqual(taken, D(6) if returned_back.status_code == 201 else D(1))
