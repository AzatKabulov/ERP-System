from django.contrib import admin

from .models import Business, Location, Membership


@admin.register(Business)
class BusinessAdmin(admin.ModelAdmin):
    list_display = ("name", "currency", "is_active", "created_at")
    search_fields = ("name",)


@admin.register(Location)
class LocationAdmin(admin.ModelAdmin):
    list_display = ("name", "business", "kind", "is_active")
    list_filter = ("kind", "is_active")
    search_fields = ("name", "business__name")


@admin.register(Membership)
class MembershipAdmin(admin.ModelAdmin):
    list_display = ("user", "business", "role", "is_active")
    list_filter = ("role", "is_active")
    search_fields = ("user__username", "business__name")
    filter_horizontal = ("locations",)
