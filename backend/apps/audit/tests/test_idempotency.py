import threading
import uuid
from concurrent.futures import ThreadPoolExecutor

from django.db import connections
from django.test import override_settings

from apps.audit.models import AuditEvent, IdempotencyRecord
from apps.businesses.models import Role
from apps.common.testing import (
    APITestCase,
    APITransactionTestCase,
    client_for,
    make_business,
    make_member,
)

URLS = "apps.audit.tests.urls"


def post(api, business, key, body=None, **kwargs):
    headers = {"HTTP_IDEMPOTENCY_KEY": str(key)} if key else {}
    return api.post(
        f"/api/v1/businesses/{business.pk}/demo/",
        body if body is not None else {"n": 1},
        format="json",
        **headers,
        **kwargs,
    )


def effects():
    return AuditEvent.objects.filter(action="test.side_effect").count()


@override_settings(ROOT_URLCONF=URLS)
class IdempotencyTests(APITestCase):
    def setUp(self):
        super().setUp()
        self.business = make_business()
        self.user = make_member(self.business, Role.WAREHOUSE, username="ware1")
        self.api = client_for(self.user)

    def test_first_call_acts_and_a_retry_replays_the_same_outcome(self):
        key = uuid.uuid4()
        first = post(self.api, self.business, key)
        second = post(self.api, self.business, key)
        self.assertEqual((first.status_code, second.status_code), (201, 201))
        self.assertEqual(first.json(), second.json())
        self.assertNotIn("Idempotent-Replay", first)
        self.assertEqual(second["Idempotent-Replay"], "true")
        self.assertEqual(effects(), 1)
        self.assertEqual(IdempotencyRecord.objects.count(), 1)

    def test_decimal_strings_survive_the_stored_replay(self):
        key = uuid.uuid4()
        post(self.api, self.business, key)
        self.assertEqual(post(self.api, self.business, key).json()["amount"], "12.50")

    def test_same_key_with_a_different_request_is_rejected(self):
        key = uuid.uuid4()
        post(self.api, self.business, key, {"n": 1})
        clash = post(self.api, self.business, key, {"n": 2})
        self.assertEqual(clash.status_code, 422)
        self.assertEqual(clash.json()["error"]["code"], "idempotency_key_reused")
        self.assertEqual(effects(), 1)

    def test_key_order_in_the_body_does_not_matter(self):
        key = uuid.uuid4()
        post(self.api, self.business, key, {"n": 1, "x": 2})
        again = post(self.api, self.business, key, {"x": 2, "n": 1})
        self.assertEqual(again.status_code, 201)
        self.assertEqual(effects(), 1)

    def test_a_failed_attempt_rolls_back_and_frees_the_key(self):
        key = uuid.uuid4()
        failed = post(self.api, self.business, key, {"n": 1, "fail": True})
        self.assertEqual(failed.status_code, 409)
        self.assertEqual(effects(), 0)  # the side effect was rolled back with the work
        self.assertEqual(IdempotencyRecord.objects.count(), 0)
        retry = post(self.api, self.business, key, {"n": 1})
        self.assertEqual(retry.status_code, 201)
        self.assertEqual(effects(), 1)

    def test_the_key_is_required_and_must_be_a_uuid(self):
        missing = post(self.api, self.business, None)
        self.assertEqual(missing.status_code, 400)
        self.assertEqual(missing.json()["error"]["code"], "idempotency_key_required")
        bad = self.api.post(
            f"/api/v1/businesses/{self.business.pk}/demo/",
            {},
            format="json",
            HTTP_IDEMPOTENCY_KEY="not-a-uuid",
        )
        self.assertEqual(bad.json()["error"]["code"], "idempotency_key_invalid")
        self.assertEqual(effects(), 0)

    def test_keys_are_scoped_to_user_and_business(self):
        key = uuid.uuid4()
        post(self.api, self.business, key)
        other_user = make_member(self.business, Role.OWNER, username="owner1")
        post(client_for(other_user), self.business, key)
        other_business = make_business("Other")
        outsider = make_member(other_business, Role.OWNER, username="owner2")
        post(client_for(outsider), other_business, key)
        self.assertEqual(effects(), 3)

    def test_operation_status_reports_the_stored_outcome_to_its_owner_only(self):
        key = uuid.uuid4()
        url = f"/api/v1/businesses/{self.business.pk}/operations/demo/{key}/"
        unknown = self.api.get(url)
        self.assertEqual(
            (unknown.status_code, unknown.json()["error"]["code"]), (404, "operation_not_found")
        )
        post(self.api, self.business, key)
        known = self.api.get(url).json()
        self.assertEqual(known["status"], "completed")
        self.assertEqual(known["response_status"], 201)
        self.assertEqual(known["response"]["n"], 1)
        colleague = client_for(make_member(self.business, Role.MANAGER, username="mgr1"))
        self.assertEqual(colleague.get(url).status_code, 404)  # not their operation
        wrong_action = f"/api/v1/businesses/{self.business.pk}/operations/other/{key}/"
        self.assertEqual(self.api.get(wrong_action).status_code, 404)


@override_settings(ROOT_URLCONF=URLS)
class IdempotencyConcurrencyTests(APITransactionTestCase):
    """Real commits and real threads against PostgreSQL."""

    def setUp(self):
        super().setUp()
        self.business = make_business()
        self.user = make_member(self.business, Role.WAREHOUSE, username="ware1")

    def run_parallel(self, calls):
        barrier = threading.Barrier(len(calls))

        def worker(call):
            try:
                barrier.wait(timeout=10)
                return call()
            finally:
                connections.close_all()

        with ThreadPoolExecutor(max_workers=len(calls)) as pool:
            return list(pool.map(worker, calls))

    def test_eight_simultaneous_duplicates_produce_exactly_one_effect(self):
        key = uuid.uuid4()
        calls = [
            lambda: post(client_for(self.user), self.business, key, {"n": 7, "sleep": 0.3})
            for _ in range(8)
        ]
        responses = self.run_parallel(calls)
        self.assertEqual({r.status_code for r in responses}, {201})
        self.assertTrue(
            all(r.json() == responses[0].json() for r in responses)
        )  # same data (JSONB reorders keys)
        replays = [r for r in responses if r.get("Idempotent-Replay") == "true"]
        self.assertEqual(len(replays), 7)
        self.assertEqual(effects(), 1)
        self.assertEqual(IdempotencyRecord.objects.count(), 1)

    def test_different_keys_run_independently(self):
        calls = [
            lambda i=i: post(
                client_for(self.user), self.business, uuid.uuid4(), {"n": i, "sleep": 0.1}
            )
            for i in range(4)
        ]
        responses = self.run_parallel(calls)
        self.assertEqual({r.status_code for r in responses}, {201})
        self.assertEqual(effects(), 4)

    def test_concurrent_same_key_different_payload_only_one_wins(self):
        key = uuid.uuid4()
        calls = [
            lambda: post(client_for(self.user), self.business, key, {"n": 1, "sleep": 0.2}),
            lambda: post(client_for(self.user), self.business, key, {"n": 2, "sleep": 0.2}),
        ]
        statuses = sorted(r.status_code for r in self.run_parallel(calls))
        self.assertEqual(statuses, [201, 422])
        self.assertEqual(effects(), 1)
