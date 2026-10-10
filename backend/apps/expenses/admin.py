from django.contrib import admin

from .models import Expense, ExpenseCategory


class ReadOnlyAdmin(admin.ModelAdmin):
    """Expenses are entered and corrected through the API, where every change is audited."""

    def has_add_permission(self, request):
        return False

    def has_change_permission(self, request, obj=None):
        return False

    def has_delete_permission(self, request, obj=None):
        return False


for model in (ExpenseCategory, Expense):
    admin.site.register(model, ReadOnlyAdmin)
