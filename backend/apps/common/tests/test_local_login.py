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
