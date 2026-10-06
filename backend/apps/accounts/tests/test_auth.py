import re
from datetime import timedelta
from unittest import mock

from django.core import mail
from django.utils import timezone
from rest_framework.test import APIClient
from rest_framework.throttling import SimpleRateThrottle

from apps.accounts.models import PasswordResetCode, User
from apps.common.testing import PASSWORD, APITestCase, make_user

LOGIN = "/api/v1/auth/login/"
REFRESH = "/api/v1/auth/refresh/"
LOGOUT = "/api/v1/auth/logout/"
CHANGE = "/api/v1/auth/password/change/"
RESET_REQUEST = "/api/v1/auth/password/reset/request/"
RESET_CONFIRM = "/api/v1/auth/password/reset/confirm/"
ME = "/api/v1/me/"


def login(username="aman", password=PASSWORD):
    return APIClient().post(LOGIN, {"username": username, "password": password}, format="json")


def bearer(access):
    client = APIClient()
    client.credentials(HTTP_AUTHORIZATION=f"Bearer {access}")
    return client


class LoginTests(APITestCase):
    def setUp(self):
        super().setUp()
        self.user = make_user("aman", full_name="Aman Ataýew", preferred_language="tk")

    def test_login_returns_tokens_and_profile(self):
        response = login()
        self.assertEqual(response.status_code, 200)
        data = response.json()
        self.assertTrue(data["access"] and data["refresh"])
        self.assertEqual(data["user"]["username"], "aman")
        self.assertEqual(data["user"]["preferred_language"], "tk")
        self.assertNotIn("password", data["user"])

    def test_username_is_case_insensitive(self):
        self.assertEqual(login("AMAN").status_code, 200)

    def test_bad_credentials_look_identical_for_every_cause(self):
        inactive = make_user("gone")
        inactive.is_active = False
        inactive.save()
        responses = [login("aman", "wrong"), login("nobody", PASSWORD), login("gone", PASSWORD)]
        for response in responses:
            self.assertEqual(response.status_code, 401)
            self.assertEqual(response.json()["error"]["code"], "invalid_credentials")
        self.assertEqual(len({r.json()["error"]["message"] for r in responses}), 1)

    def test_access_token_authenticates_requests(self):
        access = login().json()["access"]
        response = bearer(access).get(ME)
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()["user"]["username"], "aman")
        self.assertEqual(response.json()["memberships"], [])

    def test_garbage_token_is_rejected_with_a_code(self):
        response = bearer("not-a-token").get(ME)
        self.assertEqual(response.status_code, 401)
        self.assertEqual(response.json()["error"]["code"], "invalid_token")

    def test_deactivated_user_loses_access_immediately(self):
        access = login().json()["access"]
        self.user.is_active = False
        self.user.save()
        self.assertEqual(bearer(access).get(ME).status_code, 401)

    def test_login_is_throttled_per_username_and_address(self):
        with mock.patch.dict(SimpleRateThrottle.THROTTLE_RATES, {"login_identity": "3/min"}):
            codes = [login("aman", "wrong").status_code for _ in range(5)]
            blocked = login("aman", "wrong")
        self.assertEqual(codes, [401, 401, 401, 429, 429])
        self.assertEqual(blocked.json()["error"]["code"], "rate_limited")
        self.assertIn("Retry-After", blocked)

    def test_throttle_does_not_lock_out_other_usernames(self):
        make_user("other")
        with mock.patch.dict(SimpleRateThrottle.THROTTLE_RATES, {"login_identity": "2/min"}):
            for _ in range(3):
                login("aman", "wrong")
            self.assertEqual(login("other", PASSWORD).status_code, 200)

    def test_forged_forwarded_for_header_does_not_evade_the_ip_throttle(self):
        with mock.patch.dict(SimpleRateThrottle.THROTTLE_RATES, {"login_ip": "3/min"}):
            codes = []
            for index in range(5):
                client = APIClient()
                response = client.post(
                    LOGIN,
                    {"username": f"u{index}", "password": "x"},
                    format="json",
                    HTTP_X_FORWARDED_FOR=f"10.0.0.{index}",
                )
                codes.append(response.status_code)
        self.assertEqual(codes[:3], [401, 401, 401])
        self.assertEqual(codes[3:], [429, 429])


class RefreshAndLogoutTests(APITestCase):
    def setUp(self):
        super().setUp()
        make_user("aman")
        self.tokens = login().json()

    def test_refresh_rotates_and_rejects_the_old_token(self):
        first = APIClient().post(REFRESH, {"refresh": self.tokens["refresh"]}, format="json")
        self.assertEqual(first.status_code, 200)
        self.assertNotEqual(first.json()["refresh"], self.tokens["refresh"])
        self.assertEqual(bearer(first.json()["access"]).get(ME).status_code, 200)
        reuse = APIClient().post(REFRESH, {"refresh": self.tokens["refresh"]}, format="json")
        self.assertEqual(reuse.status_code, 401)
        self.assertEqual(reuse.json()["error"]["code"], "invalid_token")
        # the newly issued token still works
        again = APIClient().post(REFRESH, {"refresh": first.json()["refresh"]}, format="json")
        self.assertEqual(again.status_code, 200)

    def test_an_access_token_cannot_be_used_as_a_refresh_token(self):
        response = APIClient().post(REFRESH, {"refresh": self.tokens["access"]}, format="json")
        self.assertEqual(response.status_code, 401)

    def test_logout_revokes_the_refresh_token_and_always_answers_204(self):
        self.assertEqual(
            APIClient()
            .post(LOGOUT, {"refresh": self.tokens["refresh"]}, format="json")
            .status_code,
            204,
        )
        self.assertEqual(
            APIClient()
            .post(REFRESH, {"refresh": self.tokens["refresh"]}, format="json")
            .status_code,
            401,
        )
        self.assertEqual(
            APIClient().post(LOGOUT, {"refresh": "junk"}, format="json").status_code, 204
        )
        self.assertEqual(APIClient().post(LOGOUT, {}, format="json").status_code, 204)

    def test_deactivated_user_cannot_refresh(self):
        User.objects.filter(username="aman").update(is_active=False)
        response = APIClient().post(REFRESH, {"refresh": self.tokens["refresh"]}, format="json")
        self.assertEqual(response.status_code, 401)


class PasswordChangeTests(APITestCase):
    def setUp(self):
        super().setUp()
        make_user("aman")
        self.tokens = login().json()

    def change(self, old=PASSWORD, new="a-brand-new-passphrase-7", access=None):
        return bearer(access or self.tokens["access"]).post(
            CHANGE, {"old_password": old, "new_password": new}, format="json"
        )

    def test_change_revokes_every_other_session_but_keeps_this_one(self):
        other_device = login().json()
        response = self.change()
        self.assertEqual(response.status_code, 200)
        fresh = response.json()
        self.assertEqual(bearer(fresh["access"]).get(ME).status_code, 200)
        # old refresh tokens are dead...
        for tokens in (self.tokens, other_device):
            r = APIClient().post(REFRESH, {"refresh": tokens["refresh"]}, format="json")
            self.assertEqual(r.status_code, 401)
        # ...and so are old access tokens, immediately and not only at expiry
        stale = bearer(other_device["access"]).get(ME)
        self.assertEqual(stale.status_code, 401)
        self.assertEqual(stale.json()["error"]["code"], "session_revoked")
        self.assertEqual(login("aman", "a-brand-new-passphrase-7").status_code, 200)
        self.assertEqual(login("aman", PASSWORD).status_code, 401)

    def test_wrong_old_password_is_rejected_with_a_field_code(self):
        response = self.change(old="nope")
        self.assertEqual(response.status_code, 400)
        error = response.json()["error"]
        self.assertEqual(error["code"], "invalid_old_password")
        self.assertIn("old_password", error["fields"])

    def test_weak_passwords_report_validator_codes(self):
        short = self.change(new="short1")
        self.assertEqual(short.status_code, 400)
        codes = {e["code"] for e in short.json()["error"]["fields"]["new_password"]}
        self.assertIn("password_too_short", codes)
        common = self.change(new="password123")
        self.assertIn(
            "password_too_common",
            {e["code"] for e in common.json()["error"]["fields"]["new_password"]},
        )
        self.assertEqual(login("aman", PASSWORD).status_code, 200)  # unchanged

    def test_requires_authentication(self):
        r = APIClient().post(CHANGE, {"old_password": "a", "new_password": "b"}, format="json")
        self.assertEqual(r.status_code, 401)


def sent_code():
    body = mail.outbox[-1].body
    match = re.search(r"\b[A-HJ-NP-Z2-9]{8}\b", body)
    assert match, body
    return match.group(0)


class PasswordRecoveryTests(APITestCase):
    NEW = "recovered-passphrase-42"

    def setUp(self):
        super().setUp()
        self.user = make_user("aman", email="aman@example.test", full_name="Aman")

    def request(self, identifier="aman"):
        return APIClient().post(RESET_REQUEST, {"identifier": identifier}, format="json")

    def confirm(self, code, identifier="aman", new=None):
        return APIClient().post(
            RESET_CONFIRM,
            {"identifier": identifier, "code": code, "new_password": new or self.NEW},
            format="json",
        )

    def test_full_flow_by_username_or_email(self):
        for identifier in ("aman", "AMAN@example.test"):
            mail.outbox.clear()
            response = self.request(identifier)
            self.assertEqual(response.status_code, 202)
            self.assertEqual(len(mail.outbox), 1)
            self.assertEqual(mail.outbox[0].to, ["aman@example.test"])
        old_tokens = login().json()
        code = sent_code()
        self.assertEqual(self.confirm(code.lower()).status_code, 200)  # case/space tolerant
        self.assertEqual(login("aman", self.NEW).status_code, 200)
        self.assertEqual(
            APIClient()
            .post(REFRESH, {"refresh": old_tokens["refresh"]}, format="json")
            .status_code,
            401,
        )

    def test_code_is_single_use(self):
        self.request()
        code = sent_code()
        self.assertEqual(self.confirm(code).status_code, 200)
        again = self.confirm(code, new="another-passphrase-99")
        self.assertEqual(again.status_code, 400)
        self.assertEqual(again.json()["error"]["code"], "invalid_reset_code")

    def test_a_newer_code_invalidates_the_older_one(self):
        self.request()
        old = sent_code()
        self.request()
        new = sent_code()
        self.assertNotEqual(old, new)
        self.assertEqual(self.confirm(old).status_code, 400)
        self.assertEqual(self.confirm(new).status_code, 200)

    def test_expired_code_is_rejected(self):
        self.request()
        code = sent_code()
        PasswordResetCode.objects.update(expires_at=timezone.now() - timedelta(seconds=1))
        self.assertEqual(self.confirm(code).status_code, 400)

    def test_wrong_guesses_exhaust_the_code_even_for_the_right_one(self):
        self.request()
        code = sent_code()
        for _ in range(5):
            self.assertEqual(self.confirm("AAAAAAAA").status_code, 400)
        self.assertEqual(self.confirm(code).status_code, 400)
        self.assertEqual(login("aman", self.NEW).status_code, 401)

    def test_unknown_account_gets_the_same_answer_and_no_email(self):
        response = self.request("nobody-here")
        self.assertEqual(response.status_code, 202)
        self.assertEqual(response.json(), {"status": "accepted"})
        self.assertEqual(self.request("ghost@example.test").status_code, 202)
        self.assertEqual(len(mail.outbox), 0)
        denied = self.confirm("ABCDEFGH", identifier="nobody-here")
        self.assertEqual(denied.json()["error"]["code"], "invalid_reset_code")

    def test_inactive_account_gets_no_email(self):
        User.objects.filter(pk=self.user.pk).update(is_active=False)
        self.assertEqual(self.request().status_code, 202)
        self.assertEqual(len(mail.outbox), 0)

    def test_a_weak_new_password_does_not_burn_a_correct_code(self):
        self.request()
        code = sent_code()
        weak = self.confirm(code, new="short1")
        self.assertEqual(weak.status_code, 400)
        self.assertIn("new_password", weak.json()["error"]["fields"])
        self.assertEqual(self.confirm(code).status_code, 200)

    def test_email_is_written_in_the_users_language(self):
        User.objects.filter(pk=self.user.pk).update(preferred_language="tk")
        self.request()
        self.assertIn("Paroly dikeltmek kody", mail.outbox[-1].subject)
        User.objects.filter(pk=self.user.pk).update(preferred_language="ru")
        self.request()
        self.assertIn("Код восстановления пароля", mail.outbox[-1].subject)

    def test_code_is_stored_only_as_a_hash(self):
        self.request()
        code = sent_code()
        stored = PasswordResetCode.objects.get()
        self.assertNotIn(code, stored.code_hash)
        self.assertEqual(len(stored.code_hash), 64)

    def test_requests_are_rate_limited_per_account(self):
        with mock.patch.dict(
            SimpleRateThrottle.THROTTLE_RATES, {"reset_request_identity": "2/hour"}
        ):
            codes = [self.request().status_code for _ in range(3)]
        self.assertEqual(codes, [202, 202, 429])

    def test_mail_failure_does_not_reveal_anything(self):
        with mock.patch("apps.accounts.services.send_code_email", side_effect=OSError("smtp down")):
            self.assertEqual(self.request().status_code, 202)
