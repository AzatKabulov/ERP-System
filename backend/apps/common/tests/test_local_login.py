import importlib.util
from pathlib import Path

from django.conf import settings
from django.test import override_settings

from apps.businesses.models import Membership, Role
from apps.common.testing import APITestCase, make_business, make_member

spec = importlib.util.spec_from_file_location(
    "test_login_urls", Path(settings.BASE_DIR).parent / "scripts/local/local_urls.py"
)
local_urls = importlib.util.module_from_spec(spec)
spec.loader.exec_module(local_urls)


@override_settings(
    ROOT_URLCONF=local_urls,
    LOCAL_TEST_LOGIN_ENABLED=True,
    DJANGO_ENV="development",
    ALLOWED_HOSTS=["localhost", "example.com", "testserver"],
)
class LocalLoginTests(APITestCase):
    def setUp(self):
        super().setUp()
        self.business = make_business("Sample Auto Parts (test data)")
        self.users = {role: make_member(self.business, role, username=role) for role in Role.values}

    def test_each_role_uses_real_permissions_and_session_versioned_tokens(self):
        for role in Role.values:
            response = self.client.post(
                "/api/v1/local-test-login/", {"role": role}, format="json", HTTP_HOST="localhost"
            )
            self.assertEqual(response.status_code, 200, response.content)
            token = response.json()["access"]
            self.client.credentials(HTTP_AUTHORIZATION="Bearer " + token)
            profile = self.client.get("/api/v1/me/", HTTP_HOST="localhost").json()
            self.assertEqual(profile["memberships"][0]["role"], role)
        self.client.credentials()

    def test_health_advertises_only_active_sample_members(self):
        self.users[Role.MANAGER].is_active = False
        self.users[Role.MANAGER].save()
        response = self.client.get("/api/v1/health/", HTTP_HOST="localhost")
        self.assertNotIn("manager", response.json()["test_login_roles"])

    def test_arbitrary_usernames_and_non_sample_business_are_refused(self):
        self.assertEqual(
            self.client.post(
                "/api/v1/local-test-login/", {"role": "admin"}, format="json", HTTP_HOST="localhost"
            ).status_code,
            400,
        )
        self.business.name = "Real shop"
        self.business.save()
        self.assertEqual(
            self.client.post(
                "/api/v1/local-test-login/", {"role": "owner"}, format="json", HTTP_HOST="localhost"
            ).status_code,
            404,
        )

    def test_disabled_member_is_not_given_tokens(self):
        Membership.objects.filter(user=self.users[Role.OWNER]).update(is_active=False)
        self.assertEqual(
            self.client.post(
                "/api/v1/local-test-login/", {"role": "owner"}, format="json", HTTP_HOST="localhost"
            ).status_code,
            404,
        )

    def test_a_request_that_came_through_a_proxy_or_tunnel_is_refused(self):
        # A tunnel or proxy on this computer connects from 127.0.0.1 and may keep the Host
        # "localhost": only its own headers show that the request came from the internet.
        for header in (
            "HTTP_X_FORWARDED_FOR",
            "HTTP_X_FORWARDED_HOST",
            "HTTP_FORWARDED",
            "HTTP_X_REAL_IP",
            "HTTP_CF_CONNECTING_IP",
            "HTTP_CF_RAY",
        ):
            with self.subTest(header):
                extra = {header: "203.0.113.7", "HTTP_HOST": "localhost"}
                refused = self.client.post(
                    "/api/v1/local-test-login/", {"role": "owner"}, format="json", **extra
                )
                self.assertEqual(refused.status_code, 404)
                health = self.client.get("/api/v1/health/", **extra)
                self.assertEqual(health.json()["test_login_roles"], [])
        # the same request without the header still works
        direct = self.client.post(
            "/api/v1/local-test-login/", {"role": "owner"}, format="json", HTTP_HOST="localhost"
        )
        self.assertEqual(direct.status_code, 200)

    def test_disabled_flag_public_host_and_production_are_refused(self):
        for overrides in ({"LOCAL_TEST_LOGIN_ENABLED": False}, {"DJANGO_ENV": "production"}):
            with self.settings(**overrides):
                self.assertEqual(
                    self.client.post(
                        "/api/v1/local-test-login/",
                        {"role": "owner"},
                        format="json",
                        HTTP_HOST="localhost",
                    ).status_code,
                    404,
                )
        self.assertEqual(
            self.client.post(
                "/api/v1/local-test-login/",
                {"role": "owner"},
                format="json",
                HTTP_HOST="example.com",
            ).status_code,
            404,
        )
        with self.settings(ROOT_URLCONF="config.urls"):
            self.assertEqual(
                self.client.post(
                    "/api/v1/local-test-login/",
                    {"role": "owner"},
                    format="json",
                    HTTP_HOST="localhost",
                ).status_code,
                404,
            )


@override_settings(
    ROOT_URLCONF=local_urls,
    LOCAL_TEST_LOGIN_ENABLED=False,
    DJANGO_ENV="production",
    ALLOWED_HOSTS=["erp.example.test", "testserver"],
)
class PublicTestLoginSwitchTests(APITestCase):
    """The testing switch (ERP_PUBLIC_TEST_LOGIN): off by default, and when on it works from the
    internet, behind a proxy, in production mode."""

    def setUp(self):
        super().setUp()
        business = make_business("Real Name Shop")
        make_member(business, Role.OWNER, username="owner")
        from apps.accounts.models import User

        User.objects.create_superuser("boss", "", "operator-password-1")
        self.call = lambda role: self.client.post(
            "/api/v1/local-test-login/",
            {"role": role},
            format="json",
            HTTP_HOST="erp.example.test",
            HTTP_X_FORWARDED_FOR="203.0.113.9",
        )

    def test_off_by_default(self):
        self.assertEqual(self.call("owner").status_code, 404)
        self.assertEqual(self.call("platform").status_code, 404)

    @override_settings(PUBLIC_TEST_LOGIN=True)
    def test_on_it_signs_in_a_shop_role_and_the_platform_owner_without_a_password(self):
        self.assertEqual(self.call("owner").status_code, 200)
        platform = self.call("platform")
        self.assertEqual(platform.status_code, 200)
        self.client.credentials(HTTP_AUTHORIZATION="Bearer " + platform.json()["access"])
        me = self.client.get("/api/v1/me/", HTTP_HOST="erp.example.test").json()
        self.assertTrue(me["user"]["is_platform_operator"])
        health = self.client.get("/api/v1/health/", HTTP_HOST="erp.example.test").json()
        self.assertIn("platform", health["test_login_roles"])
