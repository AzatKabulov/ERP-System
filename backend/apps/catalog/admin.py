from django.contrib import admin

from .models import Barcode, Brand, Category, Product, ReorderSetting, Unit

for model in (Unit, Category, Brand, Barcode, ReorderSetting):
    admin.site.register(model)


@admin.register(Product)
class ProductAdmin(admin.ModelAdmin):
    list_display = ("sku", "name", "business", "price_amount", "price_currency", "is_active")
    search_fields = ("sku", "name")
    list_filter = ("is_active", "price_currency")
    readonly_fields = ("search_key",)
