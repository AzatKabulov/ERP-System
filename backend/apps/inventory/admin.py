from django.contrib import admin

from .models import CostLayer, StockBalance, StockMovement


class ReadOnlyAdmin(admin.ModelAdmin):
    """Stock is changed only through the inventory service, never by hand in the admin."""

    def has_add_permission(self, request):
        return False

    def has_change_permission(self, request, obj=None):
        return False

    def has_delete_permission(self, request, obj=None):
        return False


admin.site.register(StockBalance, ReadOnlyAdmin)
admin.site.register(CostLayer, ReadOnlyAdmin)
admin.site.register(StockMovement, ReadOnlyAdmin)
