from django.db import connection
from django.test import SimpleTestCase
from django.urls import get_resolver
from rest_framework.test import APIClient

from apps.businesses.access import BusinessScopedMixin
from apps.businesses.models import Business, Role
from apps.businesses.permissions import MATRIX, has_permission
from apps.common.testing import APITestCase, client_for, make_business, make_member

TURKMEN = "Şäher Ätiýaçlyk Ýüpek Çäkli Žeňil Öý Ülke"
RUSSIAN = "Тормозные колодки Ёлка"


def _business_route_views():
    """Every view class whose URL contains <business_id>."""
    found = []

    def walk(patterns, prefix=""):
        for p in patterns:
            route = prefix + str(p.pattern)
            if hasattr(p, "url_patterns"):
                walk(p.url_patterns, route)
            elif "business_id" in route:
                view = getattr(p.callback, "cls", None) or getattr(p.callback, "view_class", None)
                found.append((route, view))

    walk(get_resolver().url_patterns)
    return found


class HealthAndErrorsTests(APITestCase):
    def test_health_reports_ok_and_echoes_request_id(self):
        response = APIClient().get("/api/v1/health/", HTTP_X_REQUEST_ID="trace-12345678")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json(), {"status": "ok"})
        self.assertEqual(response["X-Request-ID"], "trace-12345678")

    def test_malformed_request_id_is_replaced(self):
        response = APIClient().get("/api/v1/health/", HTTP_X_REQUEST_ID="bad id!")
        self.assertRegex(response["X-Request-ID"], r"^[0-9a-f]{32}$")

    def test_errors_use_one_envelope_without_leaking_internals(self):
        response = APIClient().get("/api/v1/me/")
        self.assertEqual(response.status_code, 401)
        error = response.json()["error"]
        self.assertEqual(error["code"], "not_authenticated")
        self.assertIn("request_id", error)

    def test_unknown_api_url_is_json_404(self):
        response = APIClient().get("/api/v1/nothing-here/")
        self.assertEqual(response.status_code, 404)
        self.assertEqual(response.json()["error"]["code"], "not_found")

    def test_validation_errors_carry_field_codes(self):
        response = APIClient().post("/api/v1/auth/login/", {}, format="json")
        self.assertEqual(response.status_code, 400)
        error = response.json()["error"]
        self.assertEqual(error["code"], "validation_error")
        self.assertEqual(error["fields"]["username"][0]["code"], "required")


class UnicodeTests(APITestCase):
    def test_turkmen_and_russian_text_round_trip_unchanged(self):
        business = make_business(TURKMEN, locations=(RUSSIAN,))
        owner = make_member(business, Role.OWNER)
        api = client_for(owner)
        self.assertEqual(api.get(f"/api/v1/businesses/{business.pk}/").json()["name"], TURKMEN)
        locations = api.get(f"/api/v1/businesses/{business.pk}/locations/").json()["results"]
        self.assertEqual(locations[0]["name"], RUSSIAN)
        response = api.patch(
            f"/api/v1/businesses/{business.pk}/", {"name": TURKMEN.upper()}, format="json"
        )
        self.assertEqual(response.json()["name"], TURKMEN.upper())
        business.refresh_from_db()
        self.assertEqual(business.name, TURKMEN.upper())

    def test_database_is_utf8(self):
        with connection.cursor() as cursor:
            cursor.execute("SHOW server_encoding")
            self.assertEqual(cursor.fetchone()[0], "UTF8")


class AccessGuardTests(SimpleTestCase):
    def test_every_business_route_uses_business_scoping(self):
        """A new /businesses/<id>/... endpoint without the access mixin fails this test."""
        routes = _business_route_views()
        self.assertGreater(len(routes), 3)
        for route, view in routes:
            with self.subTest(route=route):
                self.assertTrue(
                    issubclass(view, BusinessScopedMixin),
                    f"{view} is under {route} but does not use BusinessScopedMixin",
                )

    def test_every_declared_permission_exists_in_the_matrix(self):
        for route, view in _business_route_views():
            declared = set()
            if view.required_permission:
                declared.add(view.required_permission)
            declared.update((view.permission_by_method or {}).values())
            self.assertTrue(declared, f"{route} declares no permission (it would always be denied)")
            for code in declared:
                with self.subTest(route=route, code=code):
                    self.assertIn(code, MATRIX)

    def test_matrix_is_consistent(self):
        valid = set(Role.values)
        for code, roles in MATRIX.items():
            with self.subTest(code=code):
                self.assertTrue(roles, f"{code} is granted to nobody")
                self.assertTrue(set(roles) <= valid)
        for code in MATRIX:
            self.assertTrue(
                has_permission(Role.OWNER, code) or code.endswith(".cost.view") is False
            )
        # the owner may do everything a manager may
        for code, roles in MATRIX.items():
            if Role.MANAGER in roles:
                self.assertIn(Role.OWNER, roles, code)

    def test_business_is_a_model_with_no_usd_currency_yet(self):
        self.assertEqual([c for c, _ in Business.CURRENCIES], ["TMT"])
