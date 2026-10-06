from django.contrib import admin

from .models import AuditEvent


@admin.register(AuditEvent)
class AuditEventAdmin(admin.ModelAdmin):
    """Read-only: history is never edited through the admin."""

    list_display = ("created_at", "action", "actor", "business", "object_type", "object_id")
    list_filter = ("action",)
    search_fields = ("action", "object_id", "request_id")

    def has_add_permission(self, request):
        return False

    def has_change_permission(self, request, obj=None):
        return False

    def has_delete_permission(self, request, obj=None):
        return False
