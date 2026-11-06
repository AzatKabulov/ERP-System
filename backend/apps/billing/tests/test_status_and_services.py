from datetime import UTC, date, datetime
from decimal import Decimal

from django.db import connection
from django.test import TestCase

from apps.billing import services
from apps.billing.models import Client, Plan, SubscriptionEvent
from apps.billing.status import ACTIVE, EXPIRING, FREE, GRACE, READ_ONLY, SUSPENDED, status_of
from apps.businesses.models import Business, Membership, Role
from apps.common.testing import make_business, make_member

UTC = UTC


def at(text: str) -> datetime:
    return datetime.fromisoformat(text).replace(tzinfo=UTC)


class AddMonthsTests(TestCase):
    def test_calendar_months(self):
        self.assertEqual(services.add_months(date(2026, 6, 3), 1), date(2026, 7, 3))
        self.assertEqual(services.add_months(date(2026, 6, 3), 3), date(2026, 9, 3))
        self.assertEqual(services.add_months(date(2026, 6, 3), 12), date(2027, 6, 3))

    def test_short_months_and_year_end(self):
        self.assertEqual(services.add_months(date(2026, 1, 31), 1), date(2026, 2, 28))
        self.assertEqual(services.add_months(date(2028, 1, 31), 1), date(2028, 2, 29))
        self.assertEqual(services.add_months(date(2026, 11, 30), 3), date(2027, 2, 28))
        self.assertEqual(services.add_months(date(2026, 12, 15), 1), date(2027, 1, 15))


class StatusTests(TestCase):
    """The store is in Asia/Ashgabat (UTC+5): its day ends at 19:00 UTC."""

    def setUp(self):
        self.business = make_business("Shop")
        self.client_row = Client.objects.create(business=self.business)

    def paid_until(self, local_day: date):
        self.client_row.paid_until = services.end_of_day(self.business, local_day)
        self.client_row.save()
        self.business.refresh_from_db()
        return self.client_row.paid_until

    def status(self, now):
        return status_of(Business.objects.select_related("client").get(pk=self.business.pk), now)

    def test_no_client_row_means_free(self):
        other = make_business("Never billed")
        self.assertEqual(status_of(other).state, FREE)

    def test_free_override_never_expires(self):
        self.client_row.override = "free"
        self.client_row.paid_until = at("2020-01-01T00:00:00")
        self.client_row.save()
        self.assertEqual(self.status(at("2030-01-01T00:00:00")).state, FREE)

    def test_never_paid_is_read_only(self):
        self.assertEqual(self.status(at("2026-11-01T00:00:00")).state, READ_ONLY)

    def test_suspended_beats_a_paid_period(self):
        self.paid_until(date(2027, 1, 1))
        self.client_row.override = "suspended"
        self.client_row.save()
        status = self.status(at("2026-11-01T00:00:00"))
        self.assertEqual(status.state, SUSPENDED)
        self.assertFalse(status.allows_reads)

    def test_every_boundary(self):
        ends = self.paid_until(date(2026, 11, 10))  # 2026-11-10 23:59:59+05 = 18:59:59 UTC
        self.assertEqual(ends, at("2026-11-10T18:59:59"))
        cases = [
            ("2026-11-02T10:00:00", ACTIVE, 8),
            ("2026-11-03T10:00:00", EXPIRING, 7),  # a week or less left
            ("2026-11-10T18:59:59", EXPIRING, 0),  # the last paid second still works fully
            ("2026-11-10T19:00:00", GRACE, -1),  # 00:00 on the 11th in the shop: rolled over
            ("2026-11-17T18:59:59", GRACE, -7),  # last second of the grace days
            ("2026-11-17T19:00:00", READ_ONLY, -8),
        ]
        for now, state, days_left in cases:
            with self.subTest(now=now):
                status = self.status(at(now))
                self.assertEqual((status.state, status.days_left), (state, days_left))

    def test_what_each_state_allows(self):
        self.paid_until(date(2026, 11, 10))
        for now, reads, writes in [
            ("2026-11-02T10:00:00", True, True),
            ("2026-11-12T10:00:00", True, True),  # grace: nothing stops mid-sale
            ("2026-11-30T10:00:00", True, False),  # read-only
        ]:
            with self.subTest(now=now):
                status = self.status(at(now))
                self.assertEqual((status.allows_reads, status.allows_writes), (reads, writes))

    def test_the_stores_own_time_zone_decides_the_day(self):
        self.business.timezone = "Asia/Kuala_Lumpur"  # UTC+8: the day ends at 16:00 UTC
        self.business.save()
        ends = self.paid_until(date(2026, 11, 10))
        self.assertEqual(ends, at("2026-11-10T15:59:59"))


class ServiceTests(TestCase):
    def setUp(self):
        self.business = make_business("Shop")
        self.client_row = Client.objects.create(business=self.business)
        self.actor = make_member(self.business, Role.OWNER, username="operator")
        self.monthly = Plan.objects.get(code="monthly")
        self.yearly = Plan.objects.get(code="yearly")

    def reload(self):
        return Client.objects.select_related("business").get(pk=self.client_row.pk)

    def test_seeded_plans(self):
        self.assertEqual(
            list(Plan.objects.values_list("code", "months")),
            [("monthly", 1), ("quarterly", 3), ("yearly", 12), ("custom", None)],
        )

    def test_first_renewal_starts_today(self):
        now = at("2026-11-03T10:00:00")  # 15:00 in the shop, 3 November
        event = services.renew(self.client_row, self.monthly, self.actor, now=now)
        client = self.reload()
        self.assertEqual(client.paid_until, at("2026-12-03T18:59:59"))
        self.assertFalse(client.is_trial)
        self.assertEqual(client.plan, self.monthly)
        self.assertEqual((event.kind, event.months, event.old_until), ("renew", 1, None))
        self.assertEqual(event.new_until, client.paid_until)

    def test_early_renewal_adds_after_the_current_end(self):
        services.renew(self.client_row, self.monthly, self.actor, now=at("2026-11-03T10:00:00"))
        services.renew(self.client_row, self.monthly, self.actor, now=at("2026-11-20T10:00:00"))
        self.assertEqual(self.reload().paid_until, at("2027-01-03T18:59:59"))

    def test_late_renewal_starts_today_not_at_the_old_end(self):
        services.renew(self.client_row, self.monthly, self.actor, now=at("2026-11-03T10:00:00"))
        services.renew(self.client_row, self.monthly, self.actor, now=at("2027-01-15T10:00:00"))
        self.assertEqual(self.reload().paid_until, at("2027-02-15T18:59:59"))

    def test_a_payment_is_recorded_with_the_package_price(self):
        self.monthly.price = Decimal("150.00")
        self.monthly.save()
        event = services.renew(
            self.client_row, self.monthly, self.actor, method="cash", reference="receipt 17"
        )
        self.assertEqual(
            (event.amount, event.currency, event.method), (Decimal("150.00"), "TMT", "cash")
        )
        self.assertEqual(event.reference, "receipt 17")

    def test_custom_days_need_a_reason_and_a_sane_number(self):
        for days in (0, -3, 4000, 1.5):
            with self.subTest(days=days), self.assertRaises(services.BillingError):
                services.extend_days(self.client_row, days, self.actor, note="reason")
        with self.assertRaises(services.BillingError):
            services.extend_days(self.client_row, 7, self.actor, note="  ")
        self.assertIsNone(self.reload().paid_until)

    def test_custom_days_extend_from_the_end_or_from_today(self):
        services.renew(self.client_row, self.monthly, self.actor, now=at("2026-11-03T10:00:00"))
        services.extend_days(
            self.client_row, 7, self.actor, note="pays next week", now=at("2026-11-30T10:00:00")
        )
        self.assertEqual(self.reload().paid_until, at("2026-12-10T18:59:59"))
        services.extend_days(
            self.client_row, 7, self.actor, note="lapsed, reopened", now=at("2027-03-01T10:00:00")
        )
        self.assertEqual(self.reload().paid_until, at("2027-03-08T18:59:59"))

    def test_goodwill_days_keep_a_trial_but_money_ends_it(self):
        services.start_trial(self.client_row, self.actor, days=14, now=at("2026-11-03T10:00:00"))
        self.assertTrue(self.reload().is_trial)
        services.extend_days(self.client_row, 3, self.actor, note="more time to try")
        self.assertTrue(self.reload().is_trial)
        services.extend_days(
            self.client_row, 30, self.actor, note="paid", amount=100, method="cash"
        )
        self.assertFalse(self.reload().is_trial)

    def test_a_correction_can_shorten_and_is_recorded(self):
        services.renew(self.client_row, self.yearly, self.actor, now=at("2026-11-03T10:00:00"))
        before = self.reload().paid_until
        event = services.correct_end(self.client_row, date(2026, 12, 1), self.actor, note="typo")
        self.assertEqual(self.reload().paid_until, at("2026-12-01T18:59:59"))
        self.assertEqual((event.old_until, event.kind), (before, "correction"))
        with self.assertRaises(services.BillingError):
            services.correct_end(self.client_row, date(2026, 12, 1), self.actor, note="")

    def test_suspend_and_resume_keep_the_paid_time(self):
        services.renew(self.client_row, self.monthly, self.actor, now=at("2026-11-03T10:00:00"))
        paid = self.reload().paid_until
        with self.assertRaises(services.BillingError):
            services.suspend(self.client_row, self.actor, note="")
        services.suspend(self.client_row, self.actor, note="chargeback dispute")
        self.assertEqual(self.reload().override, "suspended")
        services.resume(self.client_row, self.actor)
        client = self.reload()
        self.assertEqual((client.override, client.paid_until), ("", paid))

    def test_free_access_needs_a_reason(self):
        with self.assertRaises(services.BillingError):
            services.set_free(self.client_row, True, self.actor, note="")
        services.set_free(self.client_row, True, self.actor, note="partner demo shop")
        self.assertEqual(self.reload().override, "free")
        services.set_free(self.client_row, False, self.actor, note="now a customer")
        self.assertEqual(self.reload().override, "")

    def test_the_history_is_append_only_even_for_raw_sql(self):
        services.renew(self.client_row, self.monthly, self.actor)
        event = SubscriptionEvent.objects.get()
        with self.assertRaises(RuntimeError):
            event.save()
        with self.assertRaises(RuntimeError):
            event.delete()
        with connection.cursor() as cursor, self.assertRaises(Exception):  # noqa: B017
            cursor.execute("DELETE FROM billing_subscriptionevent")

    def test_a_plan_without_months_cannot_be_renewed_as_a_package(self):
        with self.assertRaises(services.BillingError):
            services.renew(self.client_row, Plan.objects.get(code="custom"), self.actor)


class ProvisionTests(TestCase):
    def setUp(self):
        self.operator = make_member(make_business("Platform"), Role.OWNER, username="operator")

    def test_a_new_store_gets_an_owner_a_temporary_password_and_a_trial(self):
        client, password = services.provision_client(
            store_name="Willy Wonka",
            owner_username="willy-wonka",
            owner_name="Willy",
            phone="+993 65 000000",
            language="tk",
            actor=self.operator,
        )
        owner = Membership.objects.get(business=client.business, role=Role.OWNER).user
        self.assertTrue(owner.must_change_password)
        self.assertTrue(owner.check_password(password))
        self.assertEqual(owner.email, "")
        self.assertEqual(client.business.locations.get().name, "Willy Wonka")
        self.assertEqual(client.business.default_language, "tk")
        self.assertTrue(client.is_trial)
        self.assertEqual(
            list(client.events.order_by("created_at").values_list("kind", flat=True)),
            ["created", "trial"],
        )
        self.assertEqual(status_of(client.business).state, ACTIVE)

    def test_a_new_store_can_start_with_a_paid_package(self):
        monthly = Plan.objects.get(code="monthly")
        client, _ = services.provision_client(
            store_name="Cash Shop",
            owner_username="cash-shop",
            plan=monthly,
            amount=Decimal("100"),
            method="cash",
            actor=self.operator,
        )
        self.assertFalse(client.is_trial)
        self.assertEqual(client.plan, monthly)
        self.assertEqual(client.events.get(kind="renew").amount, Decimal("100"))

    def test_nothing_is_left_behind_when_creation_fails(self):
        services.provision_client(store_name="One", owner_username="dup-name", actor=self.operator)
        with self.assertRaises(Exception):  # noqa: B017  the login is taken
            services.provision_client(
                store_name="Two", owner_username="dup-name", actor=self.operator
            )
        self.assertFalse(Business.objects.filter(name="Two").exists())

    def test_suggested_logins(self):
        self.assertEqual(services.suggest_login("Willy Wonka"), "willy-wonka")
        self.assertEqual(services.suggest_login("Авто Запчасти"), "avto-zapchasti")
        self.assertEqual(services.suggest_login("Awto Merkezi"), "awto-merkezi")
        self.assertEqual(services.suggest_login("A"), "axx")
        services.provision_client(store_name="X", owner_username="willy-wonka", actor=self.operator)
        self.assertEqual(services.suggest_login("Willy Wonka"), "willy-wonka-2")

    def test_resetting_an_owner_password_signs_them_out_and_forces_a_change(self):
        client, first = services.provision_client(
            store_name="Shop", owner_username="shop-owner", actor=self.operator
        )
        second = services.reset_owner_password(client, self.operator)
        owner = Membership.objects.get(business=client.business, role=Role.OWNER).user
        self.assertNotEqual(first, second)
        self.assertTrue(owner.check_password(second))
        self.assertTrue(owner.must_change_password)
        event = client.events.get(kind="password_reset")
        self.assertNotIn(second, event.note)
