import getpass
import os

from django.contrib.auth.password_validation import validate_password
from django.core.exceptions import ValidationError
from django.core.management.base import BaseCommand, CommandError

from apps.accounts.models import User
from apps.businesses import services


class Command(BaseCommand):
    help = (
        "Create a business with its first owner (operator tool). The password is read from the "
        "ERP_OWNER_PASSWORD environment variable or prompted for; it is never a command-line "
        "argument."
    )

    def add_arguments(self, parser):
        parser.add_argument("--name", required=True)
        parser.add_argument("--owner-username", required=True)
        parser.add_argument("--owner-email", required=True)
        parser.add_argument("--owner-full-name", default="")
        parser.add_argument(
            "--location", default="", help="Name of a first location, e.g. 'Main store'"
        )
        parser.add_argument("--language", choices=["ru", "tk"], default="ru")

    def handle(self, *args, **opts):
        password = os.environ.get("ERP_OWNER_PASSWORD") or getpass.getpass("Owner password: ")
        try:
            validate_password(password)
        except ValidationError as exc:
            raise CommandError("; ".join(exc.messages)) from exc
        owner = User.objects.create_user(
            opts["owner_username"],
            opts["owner_email"],
            password,
            full_name=opts["owner_full_name"],
            preferred_language=opts["language"],
        )
        business = services.create_business(
            name=opts["name"], owner=owner, location_name=opts["location"]
        )
        self.stdout.write(
            self.style.SUCCESS(f"Created business {business.pk} with owner {owner.username}")
        )
