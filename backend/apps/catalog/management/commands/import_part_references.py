"""Operator import of public supplier identifiers, never a shop's stock or prices."""

import csv
import json
import os
import tempfile
from pathlib import Path

from django.core.management.base import BaseCommand, CommandError

from apps.catalog.part_lookup import identify, key


class Command(BaseCommand):
    help = "Validate a supplier article/name/brand CSV and write a public lookup JSON file."

    def add_arguments(self, parser):
        parser.add_argument("csv_file")
        parser.add_argument("--output", required=True)
        parser.add_argument("--replace", action="store_true")

    def handle(self, *args, **options):
        source = Path(options["csv_file"])
        output = Path(options["output"])
        if output.exists() and not options["replace"]:
            raise CommandError("Output exists; use --replace to intentionally replace it.")
        if source.stat().st_size > 10_000_000:
            raise CommandError("CSV exceeds 10 MB.")
        with source.open(encoding="utf-8-sig", newline="") as handle:
            sample = handle.read(4096)
            handle.seek(0)
            delimiter = ";" if sample.count(";") > sample.count(",") else ","
            reader = csv.DictReader(handle, delimiter=delimiter)
            fields = {"article", "brand", "name", "code_aliases", "brand_aliases"}
            if (
                not {"article", "brand", "name"} <= set(reader.fieldnames or [])
                or set(reader.fieldnames or []) - fields
            ):
                raise CommandError(
                    "Columns: article,brand,name; optional code_aliases,brand_aliases. "
                    "No prices or business data."
                )
            rows, seen = [], set()
            for number, row in enumerate(reader, 2):
                if len(rows) >= 50000:
                    raise CommandError("Too many reference rows.")
                article, brand, name = (
                    str(row.get(f) or "").strip() for f in ("article", "brand", "name")
                )
                parsed, _ = identify(article, brand)
                identity = (key(article), key(brand))
                if not parsed or not name or len(name) > 255 or len(brand) > 64 or identity in seen:
                    raise CommandError(f"Invalid or duplicate reference at row {number}.")
                record = {"article": article, "brand": brand, "name": name}
                for field in ("code_aliases", "brand_aliases"):
                    aliases = [v.strip() for v in (row.get(field) or "").split("|") if v.strip()]
                    if len(aliases) > 20 or any(len(v) > 64 for v in aliases):
                        raise CommandError(f"Invalid aliases at row {number}.")
                    if aliases:
                        record[field] = aliases
                rows.append(record)
                seen.add(identity)
        output.parent.mkdir(parents=True, exist_ok=True)
        fd, temporary = tempfile.mkstemp(dir=output.parent, prefix=".parts-", suffix=".json")
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as handle:
                json.dump(rows, handle, ensure_ascii=False, indent=2)
                handle.write("\n")
            os.replace(temporary, output)
        finally:
            Path(temporary).unlink(missing_ok=True)
        self.stdout.write(
            f"Validated {len(rows)} public references. No products, stock or prices changed."
        )
