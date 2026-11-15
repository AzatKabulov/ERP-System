import io
import json
import tempfile
from pathlib import Path

from django.core.management import call_command
from django.core.management.base import CommandError
from django.test import SimpleTestCase


class PartReferenceImportTests(SimpleTestCase):
    def test_public_references_preserve_unicode_without_touching_a_database(self):
        with tempfile.TemporaryDirectory() as folder:
            source = Path(folder) / "input.csv"
            output = Path(folder) / "parts.json"
            source.write_text(
                "article;brand;name\nMH044089;Fuso;Подшипник Ää Ňň\n", encoding="utf-8"
            )
            call_command(
                "import_part_references", str(source), output=str(output), stdout=io.StringIO()
            )
            self.assertEqual(json.loads(output.read_text())[0]["name"], "Подшипник Ää Ňň")

    def test_prices_and_shop_records_are_not_accepted_as_public_reference_data(self):
        with tempfile.TemporaryDirectory() as folder:
            source = Path(folder) / "input.csv"
            output = Path(folder) / "parts.json"
            source.write_text("article,brand,name,price\nME996364,Fuso,Thermostat,10\n")
            with self.assertRaises(CommandError):
                call_command("import_part_references", str(source), output=str(output))
            self.assertFalse(output.exists())

    def test_invalid_input_does_not_replace_existing_catalog(self):
        with tempfile.TemporaryDirectory() as folder:
            source = Path(folder) / "input.csv"
            output = Path(folder) / "parts.json"
            output.write_text("[]\n")
            source.write_text(
                "article,brand,name\nME996364,Fuso,Thermostat\nME996364,Fuso,Duplicate\n"
            )
            with self.assertRaises(CommandError):
                call_command(
                    "import_part_references", str(source), output=str(output), replace=True
                )
            self.assertEqual(output.read_text(), "[]\n")
