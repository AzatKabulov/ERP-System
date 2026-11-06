"""One sweep over every URL that names a business: a person who belongs to one business must
get 404 (never 403, never data) from every other business's address, with every method, and an
anonymous caller must get 401. New routes are covered the moment they exist."""

import re
import uuid

from django.urls import get_resolver
from rest_framework.test import APIClient

from apps.businesses.models import Role
from apps.common.testing import APITestCase, client_for, make_business, make_member

METHODS = ("get", "post", "put", "patch", "delete")
PARAMETER = re.compile(r"<(?:(\w+):)?(\w+)>")


def _business_routes():
    """Every route with <business_id>, as a template and the route's own text."""
    found = []

    def walk(patterns, prefix=""):
        for p in patterns:
            route = prefix + str(p.pattern)
            if hasattr(p, "url_patterns"):
                walk(p.url_patterns, route)
            elif "<uuid:business_id>" in route:
                found.append(route)

    walk(get_resolver().url_patterns)
    return found


def _fill(route, business_id):
    def value(match):
        converter, name = match.groups()
        if name == "business_id":
            return str(business_id)
        return {"int": "1", "uuid": str(uuid.uuid4())}.get(converter, "x")

    return "/" + PARAMETER.sub(value, route)


class EveryBusinessRouteTests(APITestCase):
    def setUp(self):
        super().setUp()
        self.mine = make_business("Mine")
        self.theirs = make_business("Theirs")
        self.me = make_member(self.mine, Role.OWNER, username="owner-mine")
        make_member(self.theirs, Role.OWNER, username="owner-theirs")
        self.routes = _business_routes()

    def test_there_are_routes_to_check(self):
        self.assertGreater(len(self.routes), 80)

    def test_another_business_is_a_404_for_every_route_and_method(self):
        client = client_for(self.me)
        for route in self.routes:
            url = _fill(route, self.theirs.pk)
            for method in METHODS:
                with self.subTest(method=method, url=url):
                    response = getattr(client, method)(url, {}, format="json")
                    self.assertEqual(response.status_code, 404, response.content[:200])

    def test_an_unknown_business_is_a_404_too(self):
        client = client_for(self.me)
        for route in self.routes:
            url = _fill(route, uuid.uuid4())
            with self.subTest(url=url):
                self.assertEqual(client.get(url).status_code, 404)

    def test_a_closed_business_is_a_404_even_for_its_own_owner(self):
        self.mine.is_active = False
        self.mine.save()
        client = client_for(self.me)
        for route in self.routes:
            url = _fill(route, self.mine.pk)
            with self.subTest(url=url):
                self.assertEqual(client.get(url).status_code, 404)

    def test_nobody_signed_out_gets_anything(self):
        client = APIClient()
        for route in self.routes:
            url = _fill(route, self.mine.pk)
            for method in METHODS:
                with self.subTest(method=method, url=url):
                    response = getattr(client, method)(url, {}, format="json")
                    self.assertEqual(response.status_code, 401, response.content[:200])
