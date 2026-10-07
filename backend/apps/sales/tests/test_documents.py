import io
import uuid
from decimal import Decimal

from pypdf import PdfReader

from apps.businesses.models import Role
from apps.catalog.models import Product
from apps.common.testing import APITestCase
from apps.inventory.tests.support import World, ledger_differences, make_product
from apps.sales.documents import LABELS, money, quantity
from apps.sales.models import Sale

D = Decimal
TURKMEN = "Ýüpek Ätiýaçlyk Çeper Şäher Ňokat Öýjük Žaňňyr"
RUSSIAN = "Тормозные колодки передние"


def pdf_text(response) -> str:
    reader = PdfReader(io.BytesIO(response.content))
    return "\n".join(page.extract_text() for page in reader.pages)


class DocumentCase(APITestCase):
    def setUp(self):
        super().setUp()
        self.w = World()
        self.owner = self.w.api[Role.OWNER]
        self.sales = self.w.api[Role.SALES]
        business = self.w.a
        business.address = "Aşgabat, Garaşsyzlyk şaýoly 1"
        business.phone = "+993 12 000000"
        business.tax_number = "REG-12345"
        business.save()
        self.rus = make_product(self.w.a, "RU-1", RUSSIAN, self.w.unit, "85.50")
        self.tkm = make_product(self.w.a, "TK-1", TURKMEN, self.w.unit, "12.25")
        Product.objects.filter(pk=self.rus.pk).update(warranty_months=6)
        for product in (self.rus, self.tkm):
            self.w.stock(product, self.w.store, 200, "37.77")  # the cost must never be printed
        self.sale = self.make_sale()

    def tearDown(self):
        self.assertEqual(ledger_differences(), [])
        super().tearDown()

    def make_sale(self, lines=None, **extra):
        lines = lines or [
            {"product": str(self.rus.pk), "quantity": "2", "discount": "10.00"},
            {"product": str(self.tkm.pk), "quantity": "3"},
        ]
        response = self.sales.post(
            f"{self.w.base}/sales/",
            {
                "location": str(self.w.store.pk),
                "lines": lines,
                "payments": [{"method": "cash", "amount": "250.00"}],
                "note": "Gift wrap",
                **extra,
            },
            format="json",
            HTTP_IDEMPOTENCY_KEY=str(uuid.uuid4()),
        )
        self.assertEqual(response.status_code, 201, response.content)
        return response.json()

    def document(self, kind="receipt", lang=None, client=None, sale=None):
        query = f"?kind={kind}" + (f"&lang={lang}" if lang else "")
        sale = sale or self.sale
        return (client or self.sales).get(f"{self.w.base}/sales/{sale['id']}/document/{query}")


class ReceiptTests(DocumentCase):
    def test_a_receipt_is_a_pdf_with_the_sale_on_it(self):
        response = self.document()
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response["Content-Type"], "application/pdf")
        self.assertTrue(response.content.startswith(b"%PDF"))
        self.assertIn("S-000001", response["Content-Disposition"])
        text = pdf_text(response)
        for expected in (
            "Shop A",
            "Aşgabat, Garaşsyzlyk şaýoly 1",
            "REG-12345",
            "S-000001",
            "a-sales",
        ):
            self.assertIn(expected, text)
        self.assertIn(
            money(D("197.75")).replace(" ", " "), text.replace(" ", " ")
        )  # 171 - 10 + 36.75
        self.assertIn("Gift wrap", text)

    def test_an_80_mm_roll(self):
        reader = PdfReader(io.BytesIO(self.document().content))
        width = float(reader.pages[0].mediabox.width)
        self.assertAlmostEqual(width, 80 / 25.4 * 72, delta=0.5)
        self.assertEqual(len(reader.pages), 1)

    def test_russian_and_turkmen_wording_and_letters(self):
        ru = pdf_text(self.document(lang="ru"))
        tk = pdf_text(self.document(lang="tk"))
        for word in (
            LABELS["ru"]["receipt"],
            LABELS["ru"]["total"],
            LABELS["ru"]["cashier"],
            RUSSIAN,
        ):
            self.assertIn(word, ru)
        for word in (LABELS["tk"]["receipt"], LABELS["tk"]["total"], LABELS["tk"]["cashier"]):
            self.assertIn(word, tk)
            self.assertNotIn(word, ru)
        self.assertIn(TURKMEN.split()[0], tk)
        self.assertIn("Ýüpek Ätiýaçlyk Çeper", " ".join(tk.split()))
        self.assertIn("6 мес.", ru)
        self.assertIn("Kepillik: 6 aý", tk)

    def test_every_turkmen_letter_survives_in_a_product_name(self):
        letters = "ÄÇŇÖŞÜÝŽ äçňöşüýž"
        product = make_product(self.w.a, "LET-1", letters, self.w.unit, "1.00")
        self.w.stock(product, self.w.store, 5, "0.10")
        sale = self.make_sale(lines=[{"product": str(product.pk), "quantity": "1"}])
        for kind in ("receipt", "invoice"):
            text = pdf_text(self.document(kind=kind, lang="tk", sale=sale))
            for letter in letters.replace(" ", ""):
                self.assertIn(letter, text, f"{letter} missing from the {kind}")

    def test_the_language_defaults_to_the_business_document_language(self):
        self.w.a.document_language = "tk"
        self.w.a.save()
        default = pdf_text(self.document(lang=None))
        self.assertIn(LABELS["tk"]["total"], default)
        override = pdf_text(self.document(lang="ru"))
        self.assertIn(LABELS["ru"]["total"], override)

    def test_the_font_is_embedded(self):
        for kind in ("receipt", "invoice"):
            reader = PdfReader(io.BytesIO(self.document(kind=kind).content))
            fonts = reader.pages[0]["/Resources"]["/Font"]
            self.assertTrue(fonts)
            for ref in fonts.values():
                font = ref.get_object()
                descriptor = font.get("/FontDescriptor")
                self.assertIsNotNone(
                    descriptor, f"{kind}: a font without a descriptor (not embedded)"
                )
                descriptor = descriptor.get_object()
                self.assertIn("DejaVu", str(descriptor.get("/FontName")))
                self.assertTrue(
                    any(key in descriptor for key in ("/FontFile", "/FontFile2", "/FontFile3")),
                    f"{kind}: {descriptor.get('/FontName')} is not embedded",
                )

    def test_costs_never_appear_in_a_document(self):
        for kind in ("receipt", "invoice"):
            text = pdf_text(self.document(kind=kind, client=self.owner))
            self.assertNotIn("37,77", text)
            self.assertNotIn("37.77", text)


class InvoiceTests(DocumentCase):
    def test_an_invoice_is_an_a4_document_with_a_table(self):
        response = self.document(kind="invoice", lang="ru")
        reader = PdfReader(io.BytesIO(response.content))
        box = reader.pages[0].mediabox
        self.assertEqual((round(float(box.width)), round(float(box.height))), (595, 842))
        text = pdf_text(response)
        for expected in (
            "Накладная S-000001",
            "Товар",
            "Кол-во",
            "Скидка",
            "Итого",
            RUSSIAN,
            "RU-1",
            "Оплата",
            "Наличные",
        ):
            self.assertIn(expected, text)

    def test_a_long_invoice_runs_onto_more_pages_and_loses_nothing(self):
        products = [
            make_product(
                self.w.a,
                f"BULK-{i:03d}",
                f"Part number {i:03d} with a rather long descriptive name",
                self.w.unit,
                "1.00",
            )
            for i in range(70)
        ]
        for product in products:
            self.w.stock(product, self.w.store, 5, "0.50")
        response = self.sales.post(
            f"{self.w.base}/sales/",
            {
                "location": str(self.w.store.pk),
                "lines": [{"product": str(p.pk), "quantity": "1"} for p in products],
                "payments": [{"method": "card", "amount": "70.00"}],
            },
            format="json",
            HTTP_IDEMPOTENCY_KEY=str(uuid.uuid4()),
        )
        self.assertEqual(response.status_code, 201, response.content)
        sale = response.json()
        invoice = self.document(kind="invoice", sale=sale)
        reader = PdfReader(io.BytesIO(invoice.content))
        self.assertGreater(len(reader.pages), 1)
        text = pdf_text(invoice)
        for i in (0, 35, 69):
            self.assertIn(f"BULK-{i:03d}", text)
        self.assertIn(money(D("70")).replace(" ", " "), text.replace(" ", " "))

    def test_the_customer_is_named_on_the_invoice(self):
        from apps.sales.models import Customer

        customer = Customer.objects.create(business=self.w.a, name="Ýusup Ataýew", phone="+993 65")
        sale = self.make_sale(customer=str(customer.pk))
        text = pdf_text(self.document(kind="invoice", lang="tk", sale=sale))
        self.assertIn("Ýusup Ataýew", text)
        self.assertIn("Alyjy", text)


class DocumentAccessTests(DocumentCase):
    def test_who_may_download(self):
        self.assertEqual(self.document(client=self.owner).status_code, 200)
        self.assertEqual(self.document(client=self.w.api[Role.MANAGER]).status_code, 200)
        self.assertEqual(self.document(client=self.w.api[Role.WAREHOUSE]).status_code, 403)
        self.assertEqual(self.document(client=self.w.b_api).status_code, 404)
        from rest_framework.test import APIClient

        anonymous = APIClient().get(f"{self.w.base}/sales/{self.sale['id']}/document/")
        self.assertEqual(anonymous.status_code, 401)

    def test_a_salesperson_cannot_fetch_another_locations_sale(self):
        self.w.stock(self.rus, self.w.warehouse, 5, "37.77")
        other = self.owner.post(
            f"{self.w.base}/sales/",
            {
                "location": str(self.w.warehouse.pk),
                "lines": [{"product": str(self.rus.pk), "quantity": "1"}],
                "payments": [{"method": "cash", "amount": "85.50"}],
            },
            format="json",
            HTTP_IDEMPOTENCY_KEY=str(uuid.uuid4()),
        ).json()
        self.assertEqual(self.document(sale=other).status_code, 404)
        self.assertEqual(self.document(sale=other, client=self.owner).status_code, 200)

    def test_bad_parameters_and_other_businesses_ids(self):
        for query in ("?kind=bill", "?lang=de", "?kind=receipt&lang=en"):
            response = self.sales.get(f"{self.w.base}/sales/{self.sale['id']}/document/{query}")
            self.assertEqual(response.status_code, 400, query)
        wrong = f"/api/v1/businesses/{self.w.b.pk}/sales/{self.sale['id']}/document/"
        self.assertEqual(self.w.b_api.get(wrong).status_code, 404)

    def test_a_browser_style_accept_header_does_not_get_a_406(self):
        response = self.sales.get(
            f"{self.w.base}/sales/{self.sale['id']}/document/", HTTP_ACCEPT="application/pdf"
        )
        self.assertEqual(response.status_code, 200)
        self.assertEqual(Sale.objects.count(), 1)


class FormattingTests(APITestCase):
    def test_money_and_quantity_look_like_the_app(self):
        self.assertEqual(money(D("1234.5")), "1 234,50 TMT")
        self.assertEqual(money(D("0.05")), "0,05 TMT")
        self.assertEqual(money(D("-3")), "−3,00 TMT")
        self.assertEqual(quantity(D("24"), 0), "24")
        self.assertEqual(quantity(D("2.5"), 0), "2,5")
        self.assertEqual(quantity(D("2.5"), 2), "2,50")
        self.assertEqual(quantity(D("1000"), 0), "1 000")


class BusinessDetailsTests(APITestCase):
    def test_the_owner_edits_the_details_printed_on_documents(self):
        w = World()
        url = f"{w.base}/"
        response = w.api[Role.OWNER].patch(
            url,
            {"address": "Aşgabat", "phone": "+993 12", "tax_number": "REG-1"},
            format="json",
        )
        self.assertEqual(response.status_code, 200, response.content)
        self.assertEqual(
            (response.json()["address"], response.json()["phone"], response.json()["tax_number"]),
            ("Aşgabat", "+993 12", "REG-1"),
        )
        self.assertEqual(
            w.api[Role.MANAGER].patch(url, {"phone": "x"}, format="json").status_code, 403
        )
        self.assertEqual(w.api[Role.SALES].get(url).json()["address"], "Aşgabat")
