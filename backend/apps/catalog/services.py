from decimal import Decimal

from django.db import IntegrityError, transaction

from apps.audit import services as audit
from apps.common.errors import ApiError

from .models import Barcode, Brand, Category, Product, ReorderSetting, Unit

DEFAULT_UNITS = {
    # Names are shop data, not interface text; these are only starting suggestions.
    # Turkmen wording is provisional (PLAN.md D14).
    "ru": [("Штука", "шт", 0), ("Литр", "л", 2), ("Килограмм", "кг", 3), ("Комплект", "компл", 0)],
    "tk": [("Sany", "sany", 0), ("Litr", "l", 2), ("Kilogram", "kg", 3), ("Toplum", "top", 0)],
}


def create_default_units(business) -> None:
    for name, symbol, places in DEFAULT_UNITS.get(business.default_language, DEFAULT_UNITS["ru"]):
        Unit.objects.get_or_create(
            business=business, name=name, defaults={"symbol": symbol, "decimal_places": places}
        )


def normalize_code(code: str) -> str:
    return code.strip()


def build_search_key(product: Product, codes: list[str]) -> str:
    parts = [product.name, product.sku, *codes]
    if product.brand_id:
        parts.append(product.brand.name)
    if product.category_id:
        parts.append(product.category.name)
    return " ".join(p.casefold() for p in parts if p)


def rebuild_search_key(product: Product) -> None:
    codes = list(product.barcodes.values_list("code", flat=True))
    key = build_search_key(product, codes)
    if key != product.search_key:
        Product.objects.filter(pk=product.pk).update(search_key=key)
        product.search_key = key


def _set_barcodes(product: Product, codes: list[str]) -> None:
    codes = list(dict.fromkeys(normalize_code(c) for c in codes if normalize_code(c)))
    clash = (
        Barcode.objects.filter(business=product.business, code__in=codes)
        .exclude(product=product)
        .values_list("code", flat=True)
    )
    taken = list(clash)
    if taken:
        raise ApiError(
            "validation_error",
            "Barcode already used by another product",
            fields={
                "barcodes": [{"code": "barcode_taken", "message": ", ".join(taken)}],
            },
        )
    product.barcodes.exclude(code__in=codes).delete()
    existing = set(product.barcodes.values_list("code", flat=True))
    Barcode.objects.bulk_create(
        [
            Barcode(business=product.business, product=product, code=c)
            for c in codes
            if c not in existing
        ]
    )


def _clean_scalar_fields(data: dict) -> dict:
    out = dict(data)
    for key in ("name", "sku"):
        if key in out and isinstance(out[key], str):
            out[key] = out[key].strip()
    return out


def create_product(business, actor, data: dict) -> Product:
    data = _clean_scalar_fields(data)
    codes = data.pop("barcodes", [])
    try:
        with transaction.atomic():
            product = Product.objects.create(business=business, **data)
            _set_barcodes(product, codes)
            rebuild_search_key(product)
            audit.record(
                "product.created",
                actor=actor,
                business=business,
                obj=product,
                metadata={"sku": product.sku, "name": product.name},
            )
    except IntegrityError as exc:  # SKU taken by a concurrent request
        raise ApiError(
            "validation_error",
            "SKU already used",
            fields={"sku": [{"code": "sku_taken", "message": "taken"}]},
        ) from exc
    return product


def update_product(business, actor, product: Product, data: dict) -> Product:
    data = _clean_scalar_fields(data)
    codes = data.pop("barcodes", None)
    changed = [k for k in data] + (["barcodes"] if codes is not None else [])
    try:
        with transaction.atomic():
            product = Product.objects.select_for_update().get(pk=product.pk)
            was_active = product.is_active
            for field, value in data.items():
                setattr(product, field, value)
            product.save()
            if codes is not None:
                _set_barcodes(product, codes)
            rebuild_search_key(product)
            action = "product.updated"
            if "is_active" in data and data["is_active"] != was_active:
                action = "product.archived" if not data["is_active"] else "product.restored"
            audit.record(
                action, actor=actor, business=business, obj=product, metadata={"fields": changed}
            )
    except IntegrityError as exc:
        raise ApiError(
            "validation_error",
            "SKU already used",
            fields={"sku": [{"code": "sku_taken", "message": "taken"}]},
        ) from exc
    return product


def rename_reference(instance, name: str) -> None:
    """Brands and categories feed product search keys, so a rename refreshes them."""
    instance.name = name
    instance.save()
    for product in instance.products.select_related("brand", "category"):
        rebuild_search_key(product)


def decimal_places(value: Decimal) -> int:
    exponent = value.normalize().as_tuple().exponent
    return max(0, -exponent) if isinstance(exponent, int) else 0


def check_quantity_precision(value: Decimal, unit: Unit, field: str = "quantity") -> None:
    """A quantity may not have more decimals than its unit allows (pieces are whole)."""
    if decimal_places(value) > unit.decimal_places:
        raise ApiError(
            "validation_error",
            "Too many decimal places for this unit",
            fields={field: [{"code": "quantity_precision", "message": str(unit.decimal_places)}]},
            params={"decimal_places": unit.decimal_places},
        )


@transaction.atomic
def replace_reorder_settings(
    business, actor, product: Product, rows: list[dict]
) -> list[ReorderSetting]:
    seen = set()
    for row in rows:
        if row["location"].pk in seen:
            raise ApiError(
                "validation_error",
                "Duplicate location",
                fields={"settings": [{"code": "duplicate_location", "message": "dup"}]},
            )
        seen.add(row["location"].pk)
        check_quantity_precision(row["minimum"], product.unit, "minimum")
        check_quantity_precision(row["target"], product.unit, "target")
    product.reorder_settings.all().delete()
    created = ReorderSetting.objects.bulk_create(
        [
            ReorderSetting(
                business=business,
                product=product,
                location=r["location"],
                minimum=r["minimum"],
                target=r["target"],
            )
            for r in rows
        ]
    )
    audit.record(
        "reorder.updated", actor=actor, business=business, obj=product, metadata={"rows": len(rows)}
    )
    return created


__all__ = [
    "Brand",
    "Category",
    "create_default_units",
    "create_product",
    "update_product",
    "rebuild_search_key",
    "rename_reference",
    "replace_reorder_settings",
    "check_quantity_precision",
]
