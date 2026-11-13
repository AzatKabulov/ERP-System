"""Deployment checks for development-only authentication shortcuts."""

from django.conf import settings
from django.core.checks import Error, Tags, register


@register(Tags.security, deploy=True)
def test_login_disabled_in_production(app_configs, **kwargs):
    if settings.DJANGO_ENV != "development" and getattr(settings, "PUBLIC_TEST_LOGIN", False):
        return [
            Error(
                "Password-free test login must be disabled outside development.",
                hint="Set ERP_PUBLIC_TEST_LOGIN=false. Use ordinary password and OTP sign-in.",
                id="erp.E001",
            )
        ]
    return []
