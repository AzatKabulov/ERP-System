"""Shared helpers for backend tests (PostgreSQL only)."""

from django.core.cache import cache
from rest_framework.test import APIClient
from rest_framework.test import APITestCase as DRFAPITestCase
from rest_framework.test import APITransactionTestCase as DRFAPITransactionTestCase

from apps.accounts.models import User
from apps.businesses.models import Business, Location, Membership, Role

PASSWORD = "correct-horse-battery-1"


def make_user(username="user1", email=None, password=PASSWORD, **extra) -> User:
    return User.objects.create_user(
        username, email or f"{username}@example.test", password, **extra
    )


def make_business(name="Test Shop", locations=("Main store",)) -> Business:
    business = Business.objects.create(name=name)
    for location in locations:
        Location.objects.create(business=business, name=location)
    return business


def make_member(
    business, role=Role.OWNER, username=None, locations=None, all_locations=False, **user_extra
) -> User:
    """Create a user with a membership. `locations` are Location objects for restricted roles."""
    username = username or f"{role}-{User.objects.count()}"
    user = make_user(username, **user_extra)
    membership = Membership.objects.create(
        user=user, business=business, role=role, all_locations=all_locations
    )
    if locations:
        membership.locations.set(locations)
    return user


def client_for(user=None) -> APIClient:
    client = APIClient()
    if user is not None:
        client.force_authenticate(user)
    return client


class APITestCase(DRFAPITestCase):
    def setUp(self):
        super().setUp()
        cache.clear()  # throttle counters live in the cache


class APITransactionTestCase(DRFAPITransactionTestCase):
    """For tests that need real commits (concurrency)."""

    def setUp(self):
        super().setUp()
        cache.clear()
