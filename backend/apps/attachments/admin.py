from django.contrib import admin

from .models import Attachment


class ReadOnlyAdmin(admin.ModelAdmin):
    """Files arrive through the API (with a signature check); never by hand."""

    def has_add_permission(self, request):
        return False

    def has_change_permission(self, request, obj=None):
        return False

    def has_delete_permission(self, request, obj=None):
        return False


admin.site.register(Attachment, ReadOnlyAdmin)
