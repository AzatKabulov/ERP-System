import base64
import getpass
import os

from django.contrib.auth.password_validation import validate_password
from django.core.exceptions import ValidationError
from django.core.management.base import BaseCommand, CommandError
from django_otp.plugins.otp_totp.models import TOTPDevice

from apps.accounts.models import User


class Command(BaseCommand):
    help = (
        "Create an operator: a person who may sign in to the owner console (our back office), "
        "or give an existing operator a new authenticator key. The password comes from the "
        "ERP_OPERATOR_PASSWORD environment variable or a prompt; it is never an argument. "
        "Prints the key to enter in an authenticator app (Google Authenticator, Microsoft "
        "Authenticator, Aegis...). An account that works in a store can never be made an operator."
    )

    def add_arguments(self, parser):
        parser.add_argument("username")
        parser.add_argument("--email", default="")
        parser.add_argument(
            "--new-key",
            action="store_true",
            help="Replace the authenticator key of an existing operator (a lost phone).",
        )

    def handle(self, *args, **opts):
        username = opts["username"].strip().lower()
        user = User.objects.filter(username=username).first()
        if user is None:
            password = os.environ.get("ERP_OPERATOR_PASSWORD") or getpass.getpass(
                "Operator password: "
            )
            try:
                validate_password(password)
            except ValidationError as exc:
                raise CommandError("; ".join(exc.messages)) from exc
            user = User.objects.create_superuser(username, opts["email"], password)
            self.stdout.write(self.style.SUCCESS(f"Created operator {username}"))
        elif not user.is_staff:
            raise CommandError(
                f"{username} is a store account. Operators are separate people with their own "
                "logins: create a new one."
            )
        elif not opts["new_key"] and TOTPDevice.objects.filter(user=user, confirmed=True).exists():
            raise CommandError(f"{username} already has an authenticator key (use --new-key).")
        TOTPDevice.objects.filter(user=user).delete()
        device = TOTPDevice.objects.create(user=user, name="authenticator", confirmed=True)
        key = base64.b32encode(bytes.fromhex(device.key)).decode().rstrip("=")
        self.stdout.write("\nAdd this to your authenticator app (enter the key by hand):")
        self.stdout.write(f"  account: {username}")
        self.stdout.write(f"  key:     {key}")
        self.stdout.write("  type:    time-based (TOTP), 6 digits, 30 seconds")
        self.stdout.write(f"  or open: {device.config_url}\n")
