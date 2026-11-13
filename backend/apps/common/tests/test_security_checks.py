from django.test import SimpleTestCase, override_settings

from apps.common.security_checks import test_login_disabled_in_production


class TestLoginDeploymentChecks(SimpleTestCase):
    @override_settings(DJANGO_ENV="production", PUBLIC_TEST_LOGIN=True)
    def test_production_passwordless_login_is_a_deployment_error(self):
        self.assertEqual([e.id for e in test_login_disabled_in_production(None)], ["erp.E001"])

    @override_settings(DJANGO_ENV="production", PUBLIC_TEST_LOGIN=False)
    def test_normal_production_is_allowed(self):
        self.assertEqual(test_login_disabled_in_production(None), [])

    @override_settings(DJANGO_ENV="development", PUBLIC_TEST_LOGIN=True)
    def test_explicit_development_testing_remains_available(self):
        self.assertEqual(test_login_disabled_in_production(None), [])
