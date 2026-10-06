from django.test import SimpleTestCase
from drf_spectacular.generators import SchemaGenerator


class OpenAPISchemaTests(SimpleTestCase):
    def test_schema_generates_and_lists_the_public_endpoints(self):
        schema = SchemaGenerator().get_schema(request=None, public=True)
        paths = set(schema["paths"])
        for expected in (
            "/api/v1/auth/login/",
            "/api/v1/me/",
            "/api/v1/businesses/{business_id}/locations/",
            "/api/v1/businesses/{business_id}/staff/",
        ):
            self.assertIn(expected, paths)
