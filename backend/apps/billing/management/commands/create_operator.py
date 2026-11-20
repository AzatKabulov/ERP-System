"""Create a password-authenticated platform operator; never promote shop accounts."""

import getpass
import os

from django.contrib.auth.password_validation import validate_password
from django.core.exceptions import ValidationError
from django.core.management.base import BaseCommand, CommandError
from django.db import transaction

from apps.accounts.models import User
from apps.accounts.services import set_password


class Command(BaseCommand):
    help = (
        "Create a platform operator with username/password, or explicitly reset an existing "
        "operator's password. Read ERP_OPERATOR_PASSWORD or prompt; never print credentials."
    )

    def add_arguments(self, parser):
        parser.add_argument("username")
        parser.add_argument("--email", default="")
        parser.add_argument("--reset-password", action="store_true")

    @transaction.atomic
    def handle(self, *args, **opts):
        username = opts["username"].strip().lower()
        user = User.objects.select_for_update().filter(username=username).first()
        if user is not None:
            if not user.is_staff:
                raise CommandError("Store accounts cannot become platform operators.")
            if not opts["reset_password"]:
                raise CommandError("Operator exists; use --reset-password explicitly.")
        password = os.environ.get("ERP_OPERATOR_PASSWORD") or getpass.getpass("Operator password: ")
        try:
            validate_password(password, user)
            if user is None:
                User.objects.create_superuser(username, opts["email"], password)
            else:
                set_password(user, password)
        except ValidationError as exc:
            raise CommandError("; ".join(exc.messages)) from exc
        self.stdout.write(self.style.SUCCESS(f"Operator {username} is ready for password sign-in."))
