import os
import secrets

from django.conf import settings
from django.contrib.auth.password_validation import validate_password
from django.core.exceptions import ValidationError
from django.core.management.base import BaseCommand, CommandError

from apps.accounts.models import User
from apps.businesses import services
from apps.businesses.models import Location, Membership, Role

SAMPLE_NAME = "Sample Auto Parts (test data)"


class Command(BaseCommand):
    help = (
        "Create a SAMPLE business with one user per role, for development and staging tests "
        "only. Refuses to run when DJANGO_ENV=production. Password: ERP_SAMPLE_PASSWORD, or a "
        "random one printed once."
    )

    def handle(self, *args, **opts):
        if settings.DJANGO_ENV == "production":
            raise CommandError("Sample data is never created in production.")
        from apps.businesses.models import Business

        if Business.objects.filter(name=SAMPLE_NAME).exists():
            raise CommandError("The sample business already exists.")
        password = os.environ.get("ERP_SAMPLE_PASSWORD") or secrets.token_urlsafe(14)
        try:
            validate_password(password)
        except ValidationError as exc:
            raise CommandError("; ".join(exc.messages)) from exc

        owner = User.objects.create_user(
            "owner", "owner@sample.test", password, full_name="Sample Owner"
        )
        business = services.create_business(
            name=SAMPLE_NAME, owner=owner, location_name="Main store"
        )
        store = business.locations.get()
        warehouse = Location.objects.create(
            business=business, name="Warehouse", kind=Location.Kind.WAREHOUSE
        )
        for username, role, locations in (
            ("manager", Role.MANAGER, []),
            ("sales", Role.SALES, [store]),
            ("warehouse", Role.WAREHOUSE, [warehouse]),
        ):
            user = User.objects.create_user(
                username, f"{username}@sample.test", password, full_name=f"Sample {role}"
            )
            membership = Membership.objects.create(user=user, business=business, role=role)
            membership.locations.set(locations)
        self.stdout.write(
            self.style.SUCCESS(
                f"Sample business {business.pk} created. Users: owner, manager, sales, warehouse."
            )
        )
        if not os.environ.get("ERP_SAMPLE_PASSWORD"):
            self.stdout.write(f"Password for all four users (shown once): {password}")
