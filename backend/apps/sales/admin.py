from django.contrib import admin

from .models import (
    Customer,
    ReturnInspection,
    Sale,
    SaleLine,
    SaleReturn,
    SaleReturnLine,
)

admin.site.register(Customer)


class ReadOnlyAdmin(admin.ModelAdmin):
    """Sales are history: created by the sale command, never edited or deleted by hand."""

    def has_add_permission(self, request):
        return False

    def has_change_permission(self, request, obj=None):
        return False

    def has_delete_permission(self, request, obj=None):
        return False


for model in (Sale, SaleLine, SaleReturn, SaleReturnLine, ReturnInspection):
    admin.site.register(model, ReadOnlyAdmin)
