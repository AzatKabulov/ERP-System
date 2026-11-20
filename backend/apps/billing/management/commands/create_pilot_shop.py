"""Create an isolated empty pilot shop without publishing or logging its password."""

import getpass
import os

from django.contrib.auth.password_validation import validate_password
from django.core.exceptions import ValidationError
from django.core.management.base import BaseCommand, CommandError
from django.db import transaction

from apps.accounts.models import User, normalize_username
from apps.accounts.services import set_password
from apps.billing.services import provision_client


class Command(BaseCommand):
    help = "Create an empty pilot shop. Password: ERP_PILOT_PASSWORD or a private prompt."

    def add_arguments(self, parser):
        parser.add_argument("--username", required=True)
        parser.add_argument("--shop-name", required=True)
        parser.add_argument("--owner-name", default="")
        parser.add_argument("--language", choices=["ru", "tk"], default="ru")
        parser.add_argument("--days", type=int, default=7)

    @transaction.atomic
    def handle(self, *args, **options):
        username = normalize_username(options["username"])
        if not 1 <= options["days"] <= 365:
            raise CommandError("Trial days must be between 1 and 365.")
        if User.objects.filter(username=username).exists():
            raise CommandError("Username already exists; no existing account or shop was changed.")
        password = os.environ.get("ERP_PILOT_PASSWORD") or getpass.getpass("Pilot password: ")
        try:
            validate_password(password, User(username=username))
            client, _temporary = provision_client(
                store_name=options["shop_name"],
                owner_username=username,
                owner_name=options["owner_name"],
                language=options["language"],
                trial_days=options["days"],
                note="Owner-authorized isolated shop pilot",
            )
            owner = User.objects.get(username=username)
            set_password(owner, password)
        except ValidationError as exc:
            raise CommandError("; ".join(exc.messages)) from exc
        self.stdout.write(
            self.style.SUCCESS(
                f"Created empty pilot shop for {username}; "
                f"trial ends {client.paid_until.isoformat()}."
            )
        )
