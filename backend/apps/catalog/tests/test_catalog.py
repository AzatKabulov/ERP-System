from decimal import Decimal

from django.db import DatabaseError, transaction

from apps.audit.models import AuditEvent
from apps.businesses.models import ExchangeRate, Role
from apps.catalog.models import Barcode, Brand, Category, Product, Unit
from apps.common.testing import APITestCase, client_for, make_business, make_member


def unit(business, name="Piece", symbol="pc", places=0):
    return Unit.objects.create(business=business, name=name, symbol=symbol, decimal_places=places)


class CatalogCase(APITestCase):
    def setUp(self):
        super().setUp()
        self.a = make_business("Shop A", locations=("A Store", "A Warehouse"))
        self.b = make_business("Shop B", locations=("B Store",))
        self.store, self.warehouse = self.a.locations.order_by("name")
        self.users = {
            role: make_member(
                self.a,
                role,
                username=f"a-{role}",
                locations=[self.store] if role in (Role.SALES, Role.WAREHOUSE) else None,
            )
            for role in (Role.OWNER, Role.MANAGER, Role.SALES, Role.WAREHOUSE)
        }
        self.b_owner = make_member(self.b, Role.OWNER, username="b-owner")
        self.owner = client_for(self.users[Role.OWNER])
        self.piece = unit(self.a)
        self.litre = unit(self.a, "Litre", "l", 2)
        self.base = f"/api/v1/businesses/{self.a.pk}"

    def product(self, **overrides):
        payload = {
            "sku": "FLT-001",
            "name": "Oil filter",
            "unit": str(self.piece.pk),
            "price_amount": "85.00",
            "price_currency": "TMT",
            **overrides,
        }
        response = self.owner.post(f"{self.base}/products/", payload, format="json")
        self.assertEqual(response.status_code, 201, response.content)
        return response.json()


class ProductBasicsTests(CatalogCase):
    def test_create_returns_everything_with_decimal_strings(self):
        data = self.product(
            category=str(Category.objects.create(business=self.a, name="Filters").pk),
            brand=str(Brand.objects.create(business=self.a, name="Bosch").pk),
            default_purchase_cost="54.00",
            warranty_months=12,
            warranty_terms="Return with the receipt",
            barcodes=["400001", "400002"],
        )
        self.assertEqual(data["price"], {"amount": "85.00", "currency": "TMT"})
        self.assertEqual(data["price_tmt"], "85.00")
        self.assertFalse(data["price_rate_missing"])
        self.assertEqual(data["default_purchase_cost"], "54.00")
        self.assertEqual(
            (data["warranty_months"], data["warranty_terms"]), (12, "Return with the receipt")
        )
        self.assertEqual(data["barcodes"], ["400001", "400002"])
        self.assertEqual(data["unit"]["symbol"], "pc")
        self.assertEqual(data["category"]["name"], "Filters")
        self.assertTrue(data["is_active"])

    def test_sku_is_unique_per_business_ignoring_case_and_spaces(self):
        self.product()
        clash = self.owner.post(
            f"{self.base}/products/",
            {"sku": " flt-001 ", "name": "Other", "unit": str(self.piece.pk), "price_amount": "1"},
            format="json",
        )
        self.assertEqual(clash.status_code, 400)
        self.assertEqual(clash.json()["error"]["fields"]["sku"][0]["code"], "sku_taken")
        # the same SKU is fine in another business
        b_unit = unit(self.b)
        other = client_for(self.b_owner).post(
            f"/api/v1/businesses/{self.b.pk}/products/",
            {"sku": "FLT-001", "name": "Oil filter", "unit": str(b_unit.pk), "price_amount": "5"},
            format="json",
        )
        self.assertEqual(other.status_code, 201)

    def test_barcodes_are_unique_per_business_and_several_are_allowed(self):
        self.product(barcodes=["111", "222"])
        clash = self.owner.post(
            f"{self.base}/products/",
            {
                "sku": "X1",
                "name": "X",
                "unit": str(self.piece.pk),
                "price_amount": "1",
                "barcodes": ["222", "333"],
            },
            format="json",
        )
        self.assertEqual(clash.status_code, 400)
        self.assertEqual(clash.json()["error"]["fields"]["barcodes"][0]["code"], "barcode_taken")
        self.assertFalse(Product.objects.filter(sku="X1").exists())  # nothing half-created
        b_unit = unit(self.b)
        other = client_for(self.b_owner).post(
            f"/api/v1/businesses/{self.b.pk}/products/",
            {
                "sku": "Z",
                "name": "Z",
                "unit": str(b_unit.pk),
                "price_amount": "1",
                "barcodes": ["222"],
            },
            format="json",
        )
        self.assertEqual(other.status_code, 201)

    def test_barcodes_can_be_replaced_on_update(self):
        data = self.product(barcodes=["111", "222"])
        url = f"{self.base}/products/{data['id']}/"
        updated = self.owner.patch(url, {"barcodes": ["222", "333"]}, format="json").json()
        self.assertEqual(sorted(updated["barcodes"]), ["222", "333"])
        self.assertEqual(Barcode.objects.filter(code="111").count(), 0)

    def test_references_must_belong_to_the_same_business(self):
        foreign_unit = unit(self.b, "Piece B")
        foreign_brand = Brand.objects.create(business=self.b, name="Foreign")
        for field, value in (("unit", foreign_unit.pk), ("brand", foreign_brand.pk)):
            payload = {
                "sku": f"S-{field}",
                "name": "N",
                "unit": str(self.piece.pk),
                "price_amount": "1",
            }
            payload[field] = str(value)
            response = self.owner.post(f"{self.base}/products/", payload, format="json")
            self.assertEqual(response.status_code, 400, field)
            self.assertIn(field, response.json()["error"]["fields"])

    def test_inactive_references_cannot_be_chosen_for_new_products(self):
        Unit.objects.filter(pk=self.litre.pk).update(is_active=False)
        response = self.owner.post(
            f"{self.base}/products/",
            {"sku": "L1", "name": "Oil", "unit": str(self.litre.pk), "price_amount": "1"},
            format="json",
        )
        self.assertEqual(
            response.json()["error"]["fields"]["unit"][0]["code"], "inactive_reference"
        )

    def test_validation_of_money_and_warranty(self):
        base = {"sku": "V1", "name": "V", "unit": str(self.piece.pk)}
        cases = [
            ({"price_amount": "-1"}, "price_amount"),
            ({"price_amount": "1.005"}, "price_amount"),
            ({"price_amount": "abc"}, "price_amount"),
            ({"price_amount": "1", "price_currency": "EUR"}, "price_currency"),
            ({"price_amount": "1", "warranty_months": 121}, "warranty_months"),
            ({"price_amount": "1", "warranty_months": -1}, "warranty_months"),
            ({"price_amount": "1", "default_purchase_cost": "-5"}, "default_purchase_cost"),
        ]
        for extra, field in cases:
            with self.subTest(extra=extra):
                response = self.owner.post(
                    f"{self.base}/products/", {**base, **extra}, format="json"
                )
                self.assertEqual(response.status_code, 400)
                self.assertIn(field, response.json()["error"]["fields"])

    def test_archive_hides_a_product_from_the_default_list_but_keeps_it(self):
        data = self.product(barcodes=["999"])
        url = f"{self.base}/products/{data['id']}/"
        self.assertEqual(
            self.owner.patch(url, {"is_active": False}, format="json").status_code, 200
        )
        listing = self.owner.get(f"{self.base}/products/").json()
        self.assertEqual(listing["count"], 0)
        archived = self.owner.get(f"{self.base}/products/?active=0").json()
        self.assertEqual(archived["count"], 1)
        self.assertEqual(self.owner.get(f"{self.base}/products/?active=all").json()["count"], 1)
        self.assertEqual(self.owner.get(url).status_code, 200)
        lookup = self.owner.get(f"{self.base}/barcodes/lookup/?code=999")
        self.assertEqual(lookup.status_code, 404)  # an archived product is not sold
        self.owner.patch(url, {"is_active": True}, format="json")
        self.assertEqual(self.owner.get(f"{self.base}/barcodes/lookup/?code=999").status_code, 200)
        actions = list(AuditEvent.objects.filter(business=self.a).values_list("action", flat=True))
        self.assertIn("product.archived", actions)
        self.assertIn("product.restored", actions)

    def test_every_change_is_audited(self):
        data = self.product()
        self.owner.patch(f"{self.base}/products/{data['id']}/", {"name": "Renamed"}, format="json")
        actions = AuditEvent.objects.filter(business=self.a).values_list("action", flat=True)
        self.assertIn("product.created", actions)
        self.assertIn("product.updated", actions)

    def test_unit_decimals_are_exposed_so_the_app_can_validate_quantities(self):
        data = self.product(unit=str(self.litre.pk))
        self.assertEqual(data["unit"]["decimal_places"], 2)


class SearchTests(CatalogCase):
    def setUp(self):
        super().setUp()
        brembo = Brand.objects.create(business=self.a, name="Brembo")
        brakes = Category.objects.create(business=self.a, name="Тормоза")
        self.product(
            sku="BRK-014",
            name="Тормозные колодки",
            brand=str(brembo.pk),
            category=str(brakes.pk),
            barcodes=["400002"],
        )
        self.product(sku="TKM-1", name="ÝÜPEK ÇAKMAK ŞÄHER", barcodes=["400100"])
        self.product(sku="OIL-030", name="Моторное масло 5W-30", barcodes=["400003"])

    def names(self, q):
        data = self.owner.get(f"{self.base}/products/", {"q": q}).json()
        return sorted(p["name"] for p in data["results"])

    def test_cyrillic_search_ignores_case(self):
        self.assertEqual(self.names("тормозные"), ["Тормозные колодки"])
        self.assertEqual(self.names("ТОРМОЗНЫЕ КОЛОДКИ"), ["Тормозные колодки"])
        self.assertEqual(self.names("масло"), ["Моторное масло 5W-30"])

    def test_turkmen_letters_search_ignores_case_without_transliteration(self):
        for q in ("ýüpek", "ÝÜPEK", "çakmak", "şäher", "ÇAKMAK Şäher"):
            with self.subTest(q=q):
                self.assertEqual(self.names(q), ["ÝÜPEK ÇAKMAK ŞÄHER"])
        self.assertEqual(self.names("yupek"), [])  # no transliteration

    def test_search_by_sku_barcode_brand_and_category(self):
        self.assertEqual(self.names("brk-014"), ["Тормозные колодки"])
        self.assertEqual(self.names("400100"), ["ÝÜPEK ÇAKMAK ŞÄHER"])
        self.assertEqual(self.names("Brembo"), ["Тормозные колодки"])
        self.assertEqual(self.names("тормоза"), ["Тормозные колодки"])

    def test_every_word_must_match(self):
        self.assertEqual(self.names("моторное 5w-30"), ["Моторное масло 5W-30"])
        self.assertEqual(self.names("моторное колодки"), [])

    def test_special_characters_are_taken_literally(self):
        self.assertEqual(self.names("%"), [])
        self.assertEqual(self.names("_"), [])

    def test_search_follows_renames_of_brand_and_category(self):
        brand = Brand.objects.get(name="Brembo")
        self.owner.patch(f"{self.base}/brands/{brand.pk}/", {"name": "Ferodo"}, format="json")
        self.assertEqual(self.names("brembo"), [])
        self.assertEqual(self.names("ferodo"), ["Тормозные колодки"])

    def test_search_is_limited_to_the_business(self):
        other = client_for(self.b_owner).get(
            f"/api/v1/businesses/{self.b.pk}/products/", {"q": "тормозные"}
        )
        self.assertEqual(other.json()["count"], 0)

    def test_pagination(self):
        for i in range(5):
            self.product(sku=f"P-{i}", name=f"Part {i}")
        page = self.owner.get(f"{self.base}/products/", {"limit": 3, "q": "part"}).json()
        self.assertEqual((page["count"], len(page["results"])), (5, 3))
        self.assertIsNotNone(page["next"])


class BarcodeLookupTests(CatalogCase):
    def test_lookup_finds_the_product_and_changes_nothing(self):
        data = self.product(barcodes=["5901234123457"])
        before = AuditEvent.objects.count()
        found = self.owner.get(f"{self.base}/barcodes/lookup/?code=%205901234123457%20")
        self.assertEqual(found.status_code, 200)
        self.assertEqual(found.json()["id"], data["id"])
        self.assertEqual(AuditEvent.objects.count(), before)

    def test_unknown_blank_and_foreign_codes_are_not_found(self):
        self.product(barcodes=["111"])
        b_unit = unit(self.b)
        client_for(self.b_owner).post(
            f"/api/v1/businesses/{self.b.pk}/products/",
            {
                "sku": "B1",
                "name": "B",
                "unit": str(b_unit.pk),
                "price_amount": "1",
                "barcodes": ["777"],
            },
            format="json",
        )
        for code in ("000", "", "777"):
            with self.subTest(code=code):
                response = self.owner.get(f"{self.base}/barcodes/lookup/?code={code}")
                self.assertEqual(response.status_code, 404)
                self.assertEqual(response.json()["error"]["code"], "barcode_not_found")


class PermissionAndCostTests(CatalogCase):
    def setUp(self):
        super().setUp()
        self.product(default_purchase_cost="54.00", barcodes=["111"])

    def listing(self, role):
        return client_for(self.users[role]).get(f"{self.base}/products/")

    def test_cost_is_removed_on_the_server_for_roles_without_cost_access(self):
        for role, sees in (
            (Role.OWNER, True),
            (Role.MANAGER, True),
            (Role.SALES, False),
            (Role.WAREHOUSE, False),
        ):
            with self.subTest(role=role):
                response = self.listing(role)
                self.assertEqual(response.status_code, 200)
                item = response.json()["results"][0]
                self.assertEqual("default_purchase_cost" in item, sees)
                self.assertNotIn("54.00", str(response.json()) if not sees else "")
                pid = item["id"]
                detail = client_for(self.users[role]).get(f"{self.base}/products/{pid}/").json()
                self.assertEqual("default_purchase_cost" in detail, sees)
                lookup = (
                    client_for(self.users[role])
                    .get(f"{self.base}/barcodes/lookup/?code=111")
                    .json()
                )
                self.assertEqual("default_purchase_cost" in lookup, sees)

    def test_only_owner_and_manager_may_change_the_catalog(self):
        payload = {"sku": "N1", "name": "N", "unit": str(self.piece.pk), "price_amount": "1"}
        for role in (Role.SALES, Role.WAREHOUSE):
            api = client_for(self.users[role])
            self.assertEqual(
                api.post(f"{self.base}/products/", payload, format="json").status_code, 403
            )
            self.assertEqual(
                api.post(f"{self.base}/brands/", {"name": "X"}, format="json").status_code, 403
            )
        manager = client_for(self.users[Role.MANAGER])
        self.assertEqual(
            manager.post(f"{self.base}/products/", payload, format="json").status_code, 201
        )

    def test_no_user_of_another_business_can_reach_this_catalog(self):
        data = self.owner.get(f"{self.base}/products/").json()["results"][0]
        other = client_for(self.b_owner)
        for url in (
            f"{self.base}/products/",
            f"{self.base}/products/{data['id']}/",
            f"{self.base}/barcodes/lookup/?code=111",
            f"{self.base}/units/",
            f"{self.base}/categories/",
            f"{self.base}/brands/",
            f"{self.base}/products/{data['id']}/reorder-settings/",
            f"{self.base}/exchange-rates/",
        ):
            with self.subTest(url=url):
                self.assertEqual(other.get(url).status_code, 404)

    def test_unauthenticated_requests_are_rejected(self):
        self.assertEqual(client_for().get(f"{self.base}/products/").status_code, 401)


class PriceConversionTests(CatalogCase):
    def rate(self, value, user=None):
        return client_for(user or self.users[Role.MANAGER]).post(
            f"{self.base}/exchange-rates/", {"currency": "USD", "rate": value}, format="json"
        )

    def usd_product(self, amount="10.00"):
        self.sku_counter = getattr(self, "sku_counter", 0) + 1
        return self.product(
            sku=f"U-{self.sku_counter}",
            name=f"USD {amount}",
            price_amount=amount,
            price_currency="USD",
        )

    def test_a_usd_price_without_a_rate_is_flagged_not_guessed(self):
        data = self.usd_product()
        self.assertEqual(data["price"], {"amount": "10.00", "currency": "USD"})
        self.assertIsNone(data["price_tmt"])
        self.assertTrue(data["price_rate_missing"])

    def test_the_latest_rate_converts_and_rounds_half_up(self):
        self.assertEqual(self.rate("3.500000").status_code, 201)
        self.assertEqual(self.owner.get(f"{self.base}/products/").json()["results"], [])
        data = self.usd_product("10.00")
        self.assertEqual(data["price_tmt"], "35.00")
        self.assertFalse(data["price_rate_missing"])
        self.rate("3.505000")
        cases = {"0.01": "0.04", "1.00": "3.51", "10.00": "35.05", "0.50": "1.75"}
        for amount, expected in cases.items():
            with self.subTest(amount=amount):
                item = self.usd_product(amount)
                self.assertEqual(item["price_tmt"], expected)
        # 1.234567 USD at 3.505 = 4.327... ; check a true half: 0.14 * 3.5 = 0.49 exactly
        self.rate("3.500000")
        half = self.usd_product("0.15")  # 0.525 -> rounds UP to 0.53, not banker's 0.52
        self.assertEqual(half["price_tmt"], "0.53")

    def test_tmt_prices_are_never_converted(self):
        self.rate("3.5")
        self.assertEqual(self.product(price_amount="85.00")["price_tmt"], "85.00")

    def test_rates_are_history_and_never_edited(self):
        self.rate("3.40")
        self.rate("3.50")
        history = self.owner.get(f"{self.base}/exchange-rates/").json()["results"]
        self.assertEqual([r["rate"] for r in history], ["3.500000", "3.400000"])  # newest first
        self.assertEqual(history[0]["set_by"], "a-manager")
        for sql_action in (
            lambda: ExchangeRate.objects.all().update(rate=Decimal("9")),
            lambda: ExchangeRate.objects.all().delete(),
        ):
            with self.assertRaises(DatabaseError), transaction.atomic():
                sql_action()
        self.assertEqual(ExchangeRate.objects.count(), 2)

    def test_invalid_rates_are_refused(self):
        for bad in ("0", "-1", "abc", "1000001", "1.2345678"):
            with self.subTest(rate=bad):
                self.assertEqual(self.rate(bad).status_code, 400)
        self.assertEqual(
            client_for(self.users[Role.MANAGER])
            .post(f"{self.base}/exchange-rates/", {"currency": "EUR", "rate": "3"}, format="json")
            .status_code,
            400,
        )
        self.assertEqual(ExchangeRate.objects.count(), 0)

    def test_who_may_set_and_see_rates(self):
        self.assertEqual(self.rate("3.5", self.users[Role.OWNER]).status_code, 201)
        self.assertEqual(self.rate("3.5", self.users[Role.SALES]).status_code, 403)
        self.assertEqual(self.rate("3.5", self.users[Role.WAREHOUSE]).status_code, 403)
        for role in (Role.SALES, Role.WAREHOUSE):
            self.assertEqual(
                client_for(self.users[role]).get(f"{self.base}/exchange-rates/").status_code, 200
            )

    def test_rates_are_per_business(self):
        self.rate("3.5")
        b_unit = unit(self.b)
        other = (
            client_for(self.b_owner)
            .post(
                f"/api/v1/businesses/{self.b.pk}/products/",
                {
                    "sku": "B1",
                    "name": "B",
                    "unit": str(b_unit.pk),
                    "price_amount": "10",
                    "price_currency": "USD",
                },
                format="json",
            )
            .json()
        )
        self.assertTrue(other["price_rate_missing"])  # business A's rate does not apply to B

    def test_rate_entry_is_audited(self):
        self.rate("3.5")
        self.assertTrue(
            AuditEvent.objects.filter(action="exchange_rate.created", business=self.a).exists()
        )


class ReferenceDataTests(CatalogCase):
    def test_names_are_unique_per_business_ignoring_case(self):
        for kind, extra in (
            ("categories", {}),
            ("brands", {}),
            ("units", {"symbol": "x", "decimal_places": 0}),
        ):
            with self.subTest(kind=kind):
                ok = self.owner.post(
                    f"{self.base}/{kind}/", {"name": "Same", **extra}, format="json"
                )
                self.assertEqual(ok.status_code, 201, ok.content)
                clash = self.owner.post(
                    f"{self.base}/{kind}/", {"name": "SAME", **extra}, format="json"
                )
                self.assertEqual(clash.json()["error"]["fields"]["name"][0]["code"], "name_taken")

    def test_unit_precision_cannot_change_once_products_use_it(self):
        self.product()
        response = self.owner.patch(
            f"{self.base}/units/{self.piece.pk}/", {"decimal_places": 2}, format="json"
        )
        self.assertEqual(
            (response.status_code, response.json()["error"]["code"]), (409, "unit_in_use")
        )
        self.piece.refresh_from_db()
        self.assertEqual(self.piece.decimal_places, 0)
        # an unused unit can still change, and renaming a used one is fine
        self.assertEqual(
            self.owner.patch(
                f"{self.base}/units/{self.litre.pk}/", {"decimal_places": 3}, format="json"
            ).status_code,
            200,
        )
        self.assertEqual(
            self.owner.patch(
                f"{self.base}/units/{self.piece.pk}/", {"name": "Item"}, format="json"
            ).status_code,
            200,
        )

    def test_unit_precision_is_limited_to_three_decimals(self):
        bad = self.owner.post(
            f"{self.base}/units/",
            {"name": "Bad", "symbol": "b", "decimal_places": 4},
            format="json",
        )
        self.assertEqual(bad.status_code, 400)

    def test_default_units_are_created_with_a_business(self):
        from apps.businesses.models import Business
        from apps.catalog import services as catalog_services

        ru = Business.objects.create(name="RU", default_language="ru")
        tk = Business.objects.create(name="TK", default_language="tk")
        for business in (ru, tk):
            catalog_services.create_default_units(business)
            catalog_services.create_default_units(business)  # idempotent
        self.assertEqual(ru.units.count(), 4)
        self.assertEqual(
            sorted(ru.units.values_list("symbol", flat=True)), ["кг", "компл", "л", "шт"]
        )
        self.assertIn("Sany", tk.units.values_list("name", flat=True))


class ReorderSettingsTests(CatalogCase):
    def setUp(self):
        super().setUp()
        self.p = self.product(unit=str(self.piece.pk))
        self.url = f"{self.base}/products/{self.p['id']}/reorder-settings/"

    def put(self, rows, api=None):
        return (api or self.owner).put(self.url, {"settings": rows}, format="json")

    def test_set_and_read_per_location_levels(self):
        rows = [
            {"location": str(self.store.pk), "minimum": "8", "target": "30"},
            {"location": str(self.warehouse.pk), "minimum": "20", "target": "100"},
        ]
        self.assertEqual(self.put(rows).status_code, 200)
        data = self.owner.get(self.url).json()["settings"]
        self.assertEqual(
            [(r["location_name"], r["minimum"], r["target"]) for r in data],
            [("A Store", "8.000", "30.000"), ("A Warehouse", "20.000", "100.000")],
        )
        # the list is replaced, not appended to
        self.put(rows[:1])
        self.assertEqual(len(self.owner.get(self.url).json()["settings"]), 1)

    def test_validation(self):
        loc = str(self.store.pk)
        bad = [
            [{"location": loc, "minimum": "10", "target": "5"}],  # target below minimum
            [{"location": loc, "minimum": "-1", "target": "5"}],
            [{"location": loc, "minimum": "1.5", "target": "5"}],  # pieces are whole
            [
                {"location": loc, "minimum": "1", "target": "5"},
                {"location": loc, "minimum": "2", "target": "6"},
            ],
            [
                {"location": str(self.b.locations.get().pk), "minimum": "1", "target": "5"}
            ],  # foreign location
        ]
        for rows in bad:
            with self.subTest(rows=rows):
                self.assertEqual(self.put(rows).status_code, 400)
        self.assertEqual(len(self.owner.get(self.url).json()["settings"]), 0)

    def test_fractional_levels_are_fine_for_a_litre_unit(self):
        litre_product = self.product(sku="OIL-1", name="Oil", unit=str(self.litre.pk))
        url = f"{self.base}/products/{litre_product['id']}/reorder-settings/"
        ok = self.owner.put(
            url,
            {"settings": [{"location": str(self.store.pk), "minimum": "2.5", "target": "10"}]},
            format="json",
        )
        self.assertEqual(ok.status_code, 200)
        too_fine = self.owner.put(
            url,
            {"settings": [{"location": str(self.store.pk), "minimum": "2.555", "target": "10"}]},
            format="json",
        )
        self.assertEqual(too_fine.status_code, 400)

    def test_roles(self):
        rows = [{"location": str(self.store.pk), "minimum": "1", "target": "2"}]
        self.assertEqual(self.put(rows, client_for(self.users[Role.SALES])).status_code, 403)
        self.put(rows)
        sales = client_for(self.users[Role.SALES])
        self.assertEqual(sales.get(self.url).status_code, 200)
        # restricted roles only see their own locations' levels
        self.put([*rows, {"location": str(self.warehouse.pk), "minimum": "5", "target": "9"}])
        self.assertEqual(
            [r["location_name"] for r in sales.get(self.url).json()["settings"]], ["A Store"]
        )
