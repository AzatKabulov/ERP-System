import threading
import uuid
from concurrent.futures import ThreadPoolExecutor
from decimal import Decimal

from django.db import DatabaseError, connection, connections, transaction

from apps.audit.models import AuditEvent
from apps.businesses.models import ExchangeRate, Role
from apps.catalog.models import Product
from apps.common.testing import APITestCase, APITransactionTestCase, client_for
from apps.inventory.models import StockBalance, StockMovement
from apps.inventory.tests.support import World, ledger_differences, make_product
from apps.sales.models import Customer, Sale, SaleLine

D = Decimal


class SalesCase(APITestCase):
    def setUp(self):
        super().setUp()
        self.w = World()
        self.owner = self.w.api[Role.OWNER]
        self.sales = self.w.api[Role.SALES]
        self.store = self.w.store
        self.w.stock(self.w.pad, self.store, 10, "50.00")  # sells at 100.00

    def tearDown(self):
        self.assertEqual(ledger_differences(), [])  # stock, orders and sales all agree
        super().tearDown()

    # -- helpers ------------------------------------------------------------------------
    @staticmethod
    def line(product, quantity=1, discount=None):
        body = {"product": str(product.pk), "quantity": str(quantity)}
        if discount is not None:
            body["discount"] = str(discount)
        return body

    @staticmethod
    def pay(amount, method="cash"):
        return {"method": method, "amount": str(amount)}

    def sell(self, lines=None, payments=None, *, client=None, location=None, key=None, **extra):
        body = {
            "location": str((location or self.store).pk),
            "lines": lines if lines is not None else [self.line(self.w.pad, 3)],
            "payments": payments if payments is not None else [self.pay("300.00")],
            **extra,
        }
        return (client or self.sales).post(
            f"{self.w.base}/sales/",
            body,
            format="json",
            HTTP_IDEMPOTENCY_KEY=str(key or uuid.uuid4()),
        )

    def ok(self, **kwargs):
        response = self.sell(**kwargs)
        self.assertEqual(response.status_code, 201, response.content)
        return response.json()

    def on_hand(self, product, location=None):
        row = StockBalance.objects.filter(
            product=product, location=location or self.store, condition="sellable"
        ).first()
        return row.quantity if row else D(0)

    def usd_product(self, price="10.00", sku="USD-1"):
        product = make_product(self.w.a, sku, "Imported filter", self.w.unit, price)
        Product.objects.filter(pk=product.pk).update(price_currency="USD")
        product.refresh_from_db()
        self.w.stock(product, self.store, 20, "20.00")
        return product

    def set_rate(self, rate="3.5"):
        ExchangeRate.objects.create(business=self.w.a, rate=D(rate), set_by=self.w.owner)


class SaleBasicsTests(SalesCase):
    def test_a_cash_sale_takes_the_goods_out_and_records_everything(self):
        sale = self.ok()
        self.assertEqual(sale["number"], 1)
        self.assertEqual(sale["total"], "300.00")
        self.assertEqual(sale["paid"], "300.00")
        self.assertEqual(sale["change_given"], "0.00")
        self.assertEqual(self.on_hand(self.w.pad), D(7))
        line = sale["lines"][0]
        self.assertEqual(
            (line["sku"], line["name"], line["quantity"], line["unit_price"]),
            ("BP-1", "Brake pad", "3.000", "100.00"),
        )
        self.assertEqual(line["line_total"], "300.00")
        movement = StockMovement.objects.get(document_type="sale")
        self.assertEqual((movement.movement_type, movement.quantity), ("sale", D(-3)))
        self.assertEqual(str(movement.document_id), sale["id"])
        self.assertEqual(sale["cashier"]["name"], "a-sales")
        self.assertNotIn("cost_total", str(sale))  # a salesperson never sees costs
        self.assertEqual(
            AuditEvent.objects.filter(action="sale.completed", business=self.w.a).count(), 1
        )

    def test_the_owner_sees_cost_and_profit(self):
        sale = self.ok(client=self.owner)
        self.assertEqual(sale["lines"][0]["cost_total"], "150.00")
        self.assertEqual((sale["cost_total"], sale["profit"]), ("150.00", "150.00"))

    def test_numbers_run_on_without_gaps_and_per_business(self):
        self.assertEqual([self.ok()["number"] for _ in range(2)], [1, 2])
        refused = self.sell(lines=[self.line(self.w.pad, 99)], payments=[self.pay("9900")])
        self.assertEqual(refused.status_code, 409)
        self.assertEqual(self.ok()["number"], 3)  # the refused attempt used no number

    def test_rounding_is_half_up_to_two_decimals(self):
        self.w.oil.price_amount = D("0.35")
        self.w.oil.save()
        self.w.stock(self.w.oil, self.store, 10, "0.10")
        sale = self.ok(lines=[self.line(self.w.oil, "0.50")], payments=[self.pay("1.00")])
        self.assertEqual(sale["lines"][0]["gross"], "0.18")  # 0.175 rounds up
        self.assertEqual(sale["change_given"], "0.82")

    def test_fractional_quantities_follow_the_unit(self):
        self.w.stock(self.w.oil, self.store, 10, "8.00")
        bad = self.sell(lines=[self.line(self.w.pad, "1.5")], payments=[self.pay(150)])
        self.assertEqual(bad.status_code, 400)
        good = self.sell(lines=[self.line(self.w.oil, "2.5")], payments=[self.pay(250)])
        self.assertEqual(good.status_code, 201, good.content)

    def test_usd_prices_are_converted_at_the_current_rate_and_the_rate_is_kept(self):
        product = self.usd_product("10.10")
        self.set_rate("3.5")
        sale = self.ok(lines=[self.line(product, 3)], payments=[self.pay("110.00")])
        line = sale["lines"][0]
        self.assertEqual((line["price_amount"], line["price_currency"]), ("10.10", "USD"))
        self.assertEqual(line["unit_price"], "35.35")  # 10.10 x 3.5
        self.assertEqual(line["line_total"], "106.05")
        self.assertEqual(sale["usd_rate"], "3.500000")
        self.set_rate("4.0")  # a later rate never touches the sale
        detail = self.sales.get(f"{self.w.base}/sales/{sale['id']}/").json()
        self.assertEqual((detail["usd_rate"], detail["total"]), ("3.500000", "106.05"))

    def test_a_usd_price_without_a_rate_cannot_be_sold(self):
        product = self.usd_product()
        response = self.sell(lines=[self.line(product, 1)], payments=[self.pay(100)])
        self.assertEqual(
            (response.status_code, response.json()["error"]["code"]), (409, "rate_missing")
        )
        self.assertEqual(Sale.objects.count(), 0)

    def test_customer_is_optional_and_copied_onto_the_sale(self):
        customer = Customer.objects.create(business=self.w.a, name="Ýusup Ataýew", phone="+993 65")
        sale = self.ok(customer=str(customer.pk))
        self.assertEqual(sale["customer"]["name"], "Ýusup Ataýew")
        customer.name = "Renamed"
        customer.save()
        detail = self.sales.get(f"{self.w.base}/sales/{sale['id']}/").json()
        self.assertEqual(
            (detail["customer_name"], detail["customer_phone"]), ("Ýusup Ataýew", "+993 65")
        )
        walk_in = self.ok()
        self.assertIsNone(walk_in["customer"])

    def test_warranty_terms_are_frozen_on_the_sale(self):
        Product.objects.filter(pk=self.w.pad.pk).update(
            warranty_months=12, warranty_terms="Only with the receipt"
        )
        sale = self.ok()
        Product.objects.filter(pk=self.w.pad.pk).update(warranty_months=3, warranty_terms="Changed")
        detail = self.sales.get(f"{self.w.base}/sales/{sale['id']}/").json()
        line = detail["lines"][0]
        self.assertEqual(
            (line["warranty_months"], line["warranty_terms"]), (12, "Only with the receipt")
        )

    def test_fifo_cost_across_layers(self):
        self.w.stock(self.w.pad, self.store, 10, "60.00")  # now 10 @50 then 10 @60
        sale = self.ok(
            client=self.owner, lines=[self.line(self.w.pad, 15)], payments=[self.pay(1500)]
        )
        self.assertEqual(sale["lines"][0]["cost_total"], "800.00")  # 10x50 + 5x60


class DiscountTests(SalesCase):
    def test_a_line_discount_lowers_the_total_and_is_recorded(self):
        sale = self.ok(lines=[self.line(self.w.pad, 3, discount="20.00")], payments=[self.pay(280)])
        self.assertEqual((sale["total"], sale["discount_total"]), ("280.00", "20.00"))
        line = sale["lines"][0]
        self.assertEqual(
            (line["gross"], line["discount"], line["line_total"]), ("300.00", "20.00", "280.00")
        )

    def test_anyone_who_sells_may_discount_without_a_limit(self):
        sale = self.ok(lines=[self.line(self.w.pad, 3, discount="300.00")], payments=[])
        self.assertEqual(sale["total"], "0.00")  # a free item is a (logged) discount of 100%

    def test_a_discount_cannot_exceed_the_line(self):
        response = self.sell(lines=[self.line(self.w.pad, 3, discount="300.01")])
        self.assertEqual(response.status_code, 400)
        self.assertEqual(
            response.json()["error"]["fields"]["lines.0.discount"][0]["code"], "discount_too_large"
        )
        negative = self.sell(lines=[self.line(self.w.pad, 3, discount="-1")])
        self.assertEqual(negative.status_code, 400)
        self.assertEqual(Sale.objects.count(), 0)


class PaymentTests(SalesCase):
    def test_split_payments_must_add_up(self):
        sale = self.ok(payments=[self.pay("100.00"), self.pay("200.00", "card")])
        self.assertEqual([p["method"] for p in sale["payments"]], ["cash", "card"])
        self.assertEqual(sale["change_given"], "0.00")

    def test_cash_over_the_total_is_change(self):
        sale = self.ok(payments=[self.pay("500.00")])
        self.assertEqual((sale["paid"], sale["change_given"]), ("500.00", "200.00"))

    def test_only_cash_can_give_change(self):
        for payments in (
            [self.pay("350.00", "card")],
            [self.pay("100.00"), self.pay("500.00", "transfer")],
        ):
            with self.subTest(payments=payments):
                response = self.sell(payments=payments)
                self.assertEqual(response.status_code, 400)
                self.assertEqual(response.json()["error"]["code"], "payment_mismatch")
        self.assertEqual(Sale.objects.count(), 0)

    def test_a_sale_must_be_paid_in_full(self):
        for payments in ([self.pay("299.99")], []):
            with self.subTest(payments=payments):
                response = self.sell(payments=payments)
                self.assertEqual(response.status_code, 400)
                self.assertEqual(response.json()["error"]["code"], "payment_mismatch")
        self.assertEqual(self.on_hand(self.w.pad), D(10))

    def test_a_zero_total_needs_no_payment_and_takes_none(self):
        free = [self.line(self.w.pad, 1, discount="100.00")]
        self.assertEqual(self.sell(lines=free, payments=[self.pay("1.00")]).status_code, 400)
        self.assertEqual(self.sell(lines=free, payments=[]).status_code, 201)

    def test_bad_payment_input(self):
        for payments in (
            [self.pay("0.00")],
            [self.pay("-5")],
            [{"method": "credit", "amount": "300"}],
        ):
            with self.subTest(payments=payments):
                self.assertEqual(self.sell(payments=payments).status_code, 400)

    def test_an_outdated_total_is_refused_instead_of_charging_something_else(self):
        stale = self.sell(expected_total="250.00")
        self.assertEqual((stale.status_code, stale.json()["error"]["code"]), (409, "price_changed"))
        self.assertEqual(stale.json()["error"]["params"]["total"], "300.00")
        self.assertEqual(Sale.objects.count(), 0)
        self.assertEqual(self.sell(expected_total="300.00").status_code, 201)


class ValidationAndAccessTests(SalesCase):
    def test_lines_are_validated(self):
        cases = {
            "no lines": [],
            "same product twice": [self.line(self.w.pad, 1), self.line(self.w.pad, 2)],
            "zero quantity": [self.line(self.w.pad, 0)],
            "other business's product": [self.line(self.w.b_product, 1)],
        }
        for name, lines in cases.items():
            with self.subTest(name):
                self.assertEqual(self.sell(lines=lines, payments=[self.pay(100)]).status_code, 400)
        self.assertEqual(Sale.objects.count(), 0)

    def test_an_archived_product_cannot_be_sold(self):
        Product.objects.filter(pk=self.w.pad.pk).update(is_active=False)
        response = self.sell()
        self.assertEqual(
            (response.status_code, response.json()["error"]["code"]), (409, "product_archived")
        )

    def test_selling_more_than_there_is_is_refused_and_changes_nothing(self):
        response = self.sell(lines=[self.line(self.w.pad, 11)], payments=[self.pay(1100)])
        self.assertEqual(
            (response.status_code, response.json()["error"]["code"]), (409, "insufficient_stock")
        )
        self.assertEqual(response.json()["error"]["params"]["product"], str(self.w.pad.pk))
        self.assertEqual(self.on_hand(self.w.pad), D(10))
        self.assertEqual(
            (Sale.objects.count(), StockMovement.objects.filter(document_type="sale").count()),
            (0, 0),
        )

    def test_one_short_line_stops_the_whole_sale(self):
        self.w.stock(self.w.oil, self.store, 1, "8.00")
        response = self.sell(
            lines=[self.line(self.w.pad, 2), self.line(self.w.oil, 5)], payments=[self.pay(1000)]
        )
        self.assertEqual(response.status_code, 409)
        self.assertEqual(self.on_hand(self.w.pad), D(10))  # the good line was not sold either

    def test_roles_and_locations(self):
        self.w.stock(self.w.pad, self.w.warehouse, 5, "50.00")
        warehouse_sale = self.sell(location=self.w.warehouse, client=self.sales)
        self.assertEqual(
            (warehouse_sale.status_code, warehouse_sale.json()["error"]["code"]),
            (403, "location_not_permitted"),
        )
        self.assertEqual(self.sell(location=self.w.warehouse, client=self.owner).status_code, 201)
        self.assertEqual(self.sell(client=self.w.api[Role.MANAGER]).status_code, 201)
        self.assertEqual(self.sell(client=self.w.api[Role.WAREHOUSE]).status_code, 403)
        outsider = self.sell(client=self.w.b_api)
        self.assertEqual(outsider.status_code, 404)

    def test_a_location_of_another_business_is_not_accepted(self):
        response = self.sell(location=self.w.b_store, client=self.owner)
        self.assertEqual(response.status_code, 400)

    def test_an_inactive_location_cannot_sell(self):
        self.store.is_active = False
        self.store.save()
        response = self.sell(client=self.owner)
        self.assertEqual(
            (response.status_code, response.json()["error"]["code"]), (409, "location_inactive")
        )


class ReadingTests(SalesCase):
    def setUp(self):
        super().setUp()
        self.w.stock(self.w.pad, self.w.warehouse, 5, "50.00")
        self.first = self.ok()
        self.second = self.ok(
            client=self.owner,
            location=self.w.warehouse,
            lines=[self.line(self.w.pad, 1)],
            payments=[self.pay(100, "card")],
        )

    def listing(self, client=None, query=""):
        return (client or self.owner).get(f"{self.w.base}/sales/{query}").json()

    def test_owner_sees_all_locations_sales_staff_only_their_own(self):
        self.assertEqual([s["number"] for s in self.listing()["results"]], [2, 1])
        mine = self.listing(self.sales)["results"]
        self.assertEqual([s["number"] for s in mine], [1])
        self.assertNotIn("cost_total", str(mine))
        hidden = self.sales.get(f"{self.w.base}/sales/{self.second['id']}/")
        self.assertEqual(hidden.status_code, 404)  # another location's sale

    def test_summary_fields(self):
        row = self.listing()["results"][0]
        self.assertEqual((row["total"], row["line_count"], row["methods"]), ("100.00", 1, ["card"]))
        self.assertEqual(row["location"]["name"], "A Warehouse")

    def test_filters(self):
        self.assertEqual(len(self.listing(query=f"?location={self.w.warehouse.pk}")["results"]), 1)
        for text in ("S-000002", "2", "s-000002"):
            self.assertEqual(
                [s["number"] for s in self.listing(query=f"?q={text}")["results"]], [2]
            )
        self.assertEqual(self.listing(query="?date_from=2099-01-01")["count"], 0)
        self.assertEqual(self.listing(query="?date_to=2000-01-01")["count"], 0)
        self.assertEqual(self.listing(query="?date_from=2000-01-01&date_to=2099-01-01")["count"], 2)
        self.assertEqual(
            self.owner.get(f"{self.w.base}/sales/?date_from=nonsense").status_code, 400
        )

    def test_denied_to_warehouse_and_other_businesses(self):
        self.assertEqual(self.w.api[Role.WAREHOUSE].get(f"{self.w.base}/sales/").status_code, 403)
        self.assertEqual(self.w.b_api.get(f"{self.w.base}/sales/").status_code, 404)
        self.assertEqual(
            self.w.b_api.get(f"{self.w.base}/sales/{self.first['id']}/").status_code, 404
        )
        wrong = f"/api/v1/businesses/{self.w.b.pk}/sales/{self.first['id']}/"
        self.assertEqual(self.w.b_api.get(wrong).status_code, 404)


class HistoryIsFixedTests(SalesCase):
    def test_sales_cannot_be_edited_or_deleted_even_with_raw_sql(self):
        self.ok()
        for table in ("sales_sale", "sales_saleline", "sales_salepayment"):
            for sql in (f"DELETE FROM {table}",):
                with self.subTest(table=table, sql=sql):
                    with self.assertRaises(DatabaseError), transaction.atomic():
                        with connection.cursor() as cursor:
                            cursor.execute(sql)
        with self.assertRaises(DatabaseError), transaction.atomic():
            with connection.cursor() as cursor:
                cursor.execute("UPDATE sales_sale SET total = 1")
        self.assertEqual(Sale.objects.get().total, D("300.00"))

    def test_the_orm_refuses_to_change_a_sale(self):
        self.ok()
        sale = Sale.objects.get()
        sale.total = D(1)
        with self.assertRaises(RuntimeError):
            sale.save()
        with self.assertRaises(RuntimeError):
            SaleLine.objects.get().delete()


class CustomerTests(SalesCase):
    def test_create_search_edit_deactivate(self):
        url = f"{self.w.base}/customers/"
        created = self.sales.post(
            url, {"name": "Ýusup Ataýew", "phone": "+993 65 123456"}, format="json"
        )
        self.assertEqual(created.status_code, 201, created.content)
        cid = created.json()["id"]
        self.sales.post(url, {"name": "Иван Петров"}, format="json")
        self.assertEqual(self.sales.get(url).json()["count"], 2)
        self.assertEqual(self.sales.get(f"{url}?q=ýUSUP").json()["count"], 1)  # Turkmen letters
        self.assertEqual(self.sales.get(f"{url}?q=иван").json()["count"], 1)
        self.assertEqual(self.sales.get(f"{url}?q=993").json()["count"], 1)
        edit = self.sales.patch(f"{url}{cid}/", {"name": "Ýusup A."}, format="json")
        self.assertEqual(edit.json()["name"], "Ýusup A.")
        self.assertEqual(self.sales.get(f"{url}?q=a.").json()["count"], 1)
        self.sales.patch(f"{url}{cid}/", {"is_active": False}, format="json")
        self.assertEqual(self.sales.get(url).json()["count"], 1)
        self.assertEqual(self.sales.get(f"{url}?active=0").json()["count"], 1)
        blank = self.sales.post(url, {"name": "  "}, format="json")
        self.assertEqual(blank.status_code, 400)

    def test_an_inactive_customer_cannot_be_put_on_a_sale(self):
        customer = Customer.objects.create(business=self.w.a, name="Old", is_active=False)
        self.assertEqual(self.sell(customer=str(customer.pk)).status_code, 400)

    def test_roles_and_isolation(self):
        url = f"{self.w.base}/customers/"
        self.assertEqual(self.w.api[Role.WAREHOUSE].get(url).status_code, 403)
        self.assertEqual(
            self.w.api[Role.WAREHOUSE].post(url, {"name": "X"}, format="json").status_code, 403
        )
        self.assertEqual(self.w.b_api.get(url).status_code, 404)
        foreign = Customer.objects.create(business=self.w.b, name="Foreign")
        self.assertEqual(self.sell(customer=str(foreign.pk)).status_code, 400)
        self.assertEqual(
            self.owner.get(f"{url}{foreign.pk}/").status_code, 404
        )  # not found through another business's URL


class RetryTests(SalesCase):
    def test_same_key_replays_the_same_sale(self):
        key = uuid.uuid4()
        first = self.sell(key=key)
        second = self.sell(key=key)
        self.assertEqual((first.status_code, second.status_code), (201, 201))
        self.assertEqual(first.json(), second.json())
        self.assertEqual(second["Idempotent-Replay"], "true")
        self.assertEqual(Sale.objects.count(), 1)
        self.assertEqual(self.on_hand(self.w.pad), D(7))

    def test_same_key_with_another_cart_is_refused(self):
        key = uuid.uuid4()
        self.sell(key=key)
        clash = self.sell(key=key, lines=[self.line(self.w.pad, 4)], payments=[self.pay(400)])
        self.assertEqual(
            (clash.status_code, clash.json()["error"]["code"]), (422, "idempotency_key_reused")
        )
        self.assertEqual(self.on_hand(self.w.pad), D(7))

    def test_a_key_is_required(self):
        response = self.sales.post(
            f"{self.w.base}/sales/",
            {
                "location": str(self.store.pk),
                "lines": [self.line(self.w.pad)],
                "payments": [self.pay(100)],
            },
            format="json",
        )
        self.assertEqual(response.json()["error"]["code"], "idempotency_key_required")

    def test_a_refused_sale_does_not_burn_the_key(self):
        key = uuid.uuid4()
        too_many = self.sell(key=key, lines=[self.line(self.w.pad, 11)], payments=[self.pay(1100)])
        self.assertEqual(too_many.status_code, 409)
        self.w.stock(self.w.pad, self.store, 5, "50.00")
        retry = self.sell(key=key, lines=[self.line(self.w.pad, 11)], payments=[self.pay(1100)])
        self.assertEqual(retry.status_code, 201)

    def test_the_restart_scenario(self):
        """The sale committed, the tablet died before the answer arrived. After the restart it
        asks about its saved key, finds the sale, and a resend still gives exactly one sale."""
        key = uuid.uuid4()
        self.sell(key=key)  # the answer is "lost"
        status = self.sales.get(f"{self.w.base}/operations/sale_complete/{key}/")
        self.assertEqual(status.status_code, 200)
        self.assertEqual(status.json()["response"]["number"], 1)
        resend = self.sell(key=key)
        self.assertEqual(resend.json()["id"], status.json()["response"]["id"])
        self.assertEqual(Sale.objects.count(), 1)

    def test_a_colleague_cannot_see_someone_elses_operation(self):
        key = uuid.uuid4()
        self.sell(key=key)
        other = self.w.api[Role.MANAGER].get(f"{self.w.base}/operations/sale_complete/{key}/")
        self.assertEqual(other.status_code, 404)


class SaleConcurrencyTests(APITransactionTestCase):
    """Real commits and real threads against PostgreSQL."""

    def setUp(self):
        super().setUp()
        self.w = World()
        self.w.stock(self.w.pad, self.w.store, 5, "50.00")

    def tearDown(self):
        self.assertEqual(ledger_differences(), [])
        super().tearDown()

    def sell(self, quantity, key=None, user=Role.SALES):
        try:
            return client_for(self.w.users[user]).post(
                f"{self.w.base}/sales/",
                {
                    "location": str(self.w.store.pk),
                    "lines": [{"product": str(self.w.pad.pk), "quantity": str(quantity)}],
                    "payments": [{"method": "cash", "amount": str(100 * quantity)}],
                },
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

    def test_two_tablets_selling_the_last_unit_only_one_sale_happens(self):
        self.w.remove(self.w.pad, self.w.store, 4)  # one unit left
        responses = self.parallel([lambda: self.sell(1), lambda: self.sell(1, user=Role.MANAGER)])
        self.assertEqual(sorted(r.status_code for r in responses), [201, 409])
        failed = next(r for r in responses if r.status_code == 409)
        self.assertEqual(failed.json()["error"]["code"], "insufficient_stock")
        self.assertEqual(Sale.objects.count(), 1)
        self.assertEqual(StockBalance.objects.get().quantity, D(0))

    def test_many_simultaneous_sales_never_oversell_and_numbers_have_no_gaps(self):
        responses = self.parallel([lambda: self.sell(1) for _ in range(12)])
        statuses = sorted(r.status_code for r in responses)
        self.assertEqual(statuses, [201] * 5 + [409] * 7)
        self.assertEqual(sorted(Sale.objects.values_list("number", flat=True)), [1, 2, 3, 4, 5])
        self.assertEqual(StockBalance.objects.get().quantity, D(0))

    def test_eight_simultaneous_copies_of_one_sale_make_one_sale(self):
        key = uuid.uuid4()
        responses = self.parallel([lambda: self.sell(2, key=key) for _ in range(8)])
        self.assertEqual({r.status_code for r in responses}, {201})
        self.assertEqual(len({r.json()["id"] for r in responses}), 1)
        self.assertEqual(Sale.objects.count(), 1)
        self.assertEqual(StockBalance.objects.get().quantity, D(3))
