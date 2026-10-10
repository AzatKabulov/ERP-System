from django.contrib import admin

from .models import StockCount, StockCountLine, Transfer, TransferLine


class ReadOnlyAdmin(admin.ModelAdmin):
    """Transfers and counts are created by the API (and move stock): never by hand."""

    def has_add_permission(self, request):
        return False

    def has_change_permission(self, request, obj=None):
        return False

    def has_delete_permission(self, request, obj=None):
        return False


for model in (Transfer, TransferLine, StockCount, StockCountLine):
    admin.site.register(model, ReadOnlyAdmin)
