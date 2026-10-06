from django.contrib import admin

from .models import Delivery, DeliveryLine, PurchaseOrder, PurchaseOrderLine, Supplier

admin.site.register(Supplier)


class ReadOnlyAdmin(admin.ModelAdmin):
    """Orders and deliveries are changed through the app, which keeps stock in step."""

    def has_add_permission(self, request):
        return False

    def has_change_permission(self, request, obj=None):
        return False

    def has_delete_permission(self, request, obj=None):
        return False


for model in (PurchaseOrder, PurchaseOrderLine, Delivery, DeliveryLine):
    admin.site.register(model, ReadOnlyAdmin)
