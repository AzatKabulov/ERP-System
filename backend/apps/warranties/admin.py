from django.contrib import admin

from .models import WarrantyClaim, WarrantyEvent


class ReadOnlyAdmin(admin.ModelAdmin):
    """Claims move stock and refunds: they are opened and resolved through the API only."""

    def has_add_permission(self, request):
        return False

    def has_change_permission(self, request, obj=None):
        return False

    def has_delete_permission(self, request, obj=None):
        return False


for model in (WarrantyClaim, WarrantyEvent):
    admin.site.register(model, ReadOnlyAdmin)
