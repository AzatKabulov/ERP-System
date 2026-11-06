"""Numbers that fit every field on their own but not together. The database refuses them; the
API must answer with a clear 400 and leave everything as it was, never a bare 500."""

from decimal import Decimal

from apps.sales.models import Sale

from .test_sales import SalesCase

D = Decimal


class OversizedSaleTests(SalesCase):
    def test_a_line_total_too_big_for_the_database_is_a_400_and_changes_nothing(self):
        # 20 x 99,999,999,999.99 = 1,999,999,999,999.80: each number is allowed on its own, but
        # the total needs more than the 14 digits money is stored in.
        self.w.stock(self.w.pad, self.store, 20, "50.00")
        before = self.on_hand(self.w.pad)
        response = self.sell(lines=[self.line(self.w.pad, 20, price="99999999999.99")])
        self.assertEqual(response.status_code, 400, response.content)
        error = response.json()["error"]
        self.assertEqual(error["code"], "validation_error")
        self.assertEqual(error["fields"]["non_field_errors"][0]["code"], "value_out_of_range")
        self.assertEqual(Sale.objects.count(), 0)
        self.assertEqual(self.on_hand(self.w.pad), before)  # the goods never left the shelf

    def test_the_same_key_can_be_used_again_after_the_refusal(self):
        self.w.stock(self.w.pad, self.store, 20, "50.00")
        key = "7d1f6c1e-6e36-4c52-9d67-0c1c4f0f0a11"
        refused = self.sell(lines=[self.line(self.w.pad, 20, price="99999999999.99")], key=key)
        self.assertEqual(refused.status_code, 400)
        fixed = self.sell(lines=[self.line(self.w.pad, 2, price="100.00")], key=key)
        self.assertEqual(fixed.status_code, 201, fixed.content)
        self.assertEqual(fixed.json()["total"], "200.00")
