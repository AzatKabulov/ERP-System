import logging
import re
import secrets
from datetime import timedelta

from django.contrib.auth import password_validation
from django.db import transaction
from django.utils import timezone
from django.utils.crypto import constant_time_compare, salted_hmac
from rest_framework_simplejwt.token_blacklist.models import BlacklistedToken, OutstandingToken
from rest_framework_simplejwt.tokens import RefreshToken

from .emails import send_code_email
from .models import PasswordResetCode, User

logger = logging.getLogger(__name__)

CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"  # no 0/O/1/I: easy to read aloud and type
CODE_LENGTH = 8
CODE_MINUTES = 30
CODE_MAX_ATTEMPTS = 5


def _hash(user: User, code: str) -> str:
    return salted_hmac(
        "erp.accounts.reset-code", f"{user.pk}:{code}", algorithm="sha256"
    ).hexdigest()


def normalize_code(raw: str) -> str:
    return re.sub(r"[\s-]", "", raw or "").upper()


def issue_code(user: User) -> str:
    """Create a fresh code and invalidate any earlier unused ones."""
    now = timezone.now()
    code = "".join(secrets.choice(CODE_ALPHABET) for _ in range(CODE_LENGTH))
    with transaction.atomic():
        PasswordResetCode.objects.filter(user=user, used_at__isnull=True).update(used_at=now)
        PasswordResetCode.objects.create(
            user=user, code_hash=_hash(user, code), expires_at=now + timedelta(minutes=CODE_MINUTES)
        )
    return code


def send_code(user: User, kind: str, business_name: str = "") -> None:
    """Email a fresh code. A delivery failure is logged, never shown to the caller, so the
    response cannot reveal whether an account exists."""
    code = issue_code(user)
    try:
        send_code_email(user, kind, code, CODE_MINUTES, business_name)
    except Exception:
        logger.exception("Could not send %s email to user %s", kind, user.pk)


def revoke_sessions(user: User) -> None:
    """Blacklist every outstanding refresh token; access tokens die via password_changed_at."""
    live = OutstandingToken.objects.filter(user=user, blacklistedtoken__isnull=True)
    BlacklistedToken.objects.bulk_create(
        [BlacklistedToken(token=t) for t in live], ignore_conflicts=True
    )


def set_password(user: User, new_password: str) -> None:
    """Validate and set a new password, revoking all existing sessions."""
    password_validation.validate_password(new_password, user)
    user.set_password(new_password)
    user.password_changed_at = timezone.now()
    user.session_version += 1  # every access token issued so far stops working at once
    user.save(update_fields=["password", "password_changed_at", "session_version"])
    revoke_sessions(user)


def issue_tokens(user: User) -> dict:
    refresh = RefreshToken.for_user(user)
    refresh["sv"] = user.session_version  # copied onto the access token as well
    return {"access": str(refresh.access_token), "refresh": str(refresh)}


def find_user(identifier: str) -> User | None:
    identifier = (identifier or "").strip()
    if not identifier:
        return None
    field = "email__iexact" if "@" in identifier else "username"
    value = identifier if "@" in identifier else identifier.lower()
    return User.objects.filter(is_active=True, **{field: value}).first()


def consume_code(user: User, raw_code: str, new_password: str) -> bool:
    """Check a recovery code and, if it is right, set the new password in the same
    transaction. A wrong guess counts against the attempt limit; an invalid new password
    does not burn a correct code. Returns False for any invalid/expired/exhausted code."""
    now = timezone.now()
    with transaction.atomic():
        entry = (
            PasswordResetCode.objects.select_for_update()
            .filter(user=user, used_at__isnull=True, expires_at__gt=now)
            .order_by("-created_at")
            .first()
        )
        if entry is None or entry.attempts >= CODE_MAX_ATTEMPTS:
            return False
        if not constant_time_compare(entry.code_hash, _hash(user, normalize_code(raw_code))):
            entry.attempts += 1
            entry.save(update_fields=["attempts"])
            return False
        set_password(user, new_password)  # may raise ValidationError and roll everything back
        entry.used_at = now
        entry.save(update_fields=["used_at"])
        return True
