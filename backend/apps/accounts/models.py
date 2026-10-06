from django.contrib.auth.models import AbstractBaseUser, BaseUserManager, PermissionsMixin
from django.core.validators import RegexValidator
from django.db import models
from django.db.models.functions import Lower

from apps.common.models import UUIDModel

USERNAME_VALIDATOR = RegexValidator(
    r"^[a-z0-9][a-z0-9._-]{2,63}$",
    "Use 3-64 lowercase letters, digits, dots, dashes or underscores.",
)


def normalize_username(value: str) -> str:
    return value.strip().lower()


class UserManager(BaseUserManager):
    use_in_migrations = True

    def get_by_natural_key(self, username):
        return self.get(username=normalize_username(username))

    def _create(self, username, email, password, **extra):
        if not username or not email:
            raise ValueError("username and email are required")
        user = self.model(
            username=normalize_username(username),
            email=self.normalize_email(email.strip()),
            **extra,
        )
        user.full_clean(exclude=["password"])
        if password:
            user.set_password(password)
        else:
            user.set_unusable_password()
        user.save(using=self._db)
        return user

    def create_user(self, username, email, password=None, **extra):
        extra.setdefault("is_staff", False)
        extra.setdefault("is_superuser", False)
        return self._create(username, email, password, **extra)

    def create_superuser(self, username, email, password=None, **extra):
        extra.setdefault("is_staff", True)
        extra.setdefault("is_superuser", True)
        return self._create(username, email, password, **extra)


class User(UUIDModel, AbstractBaseUser, PermissionsMixin):
    """A person who can sign in. Access to business data comes only from memberships."""

    LANGUAGES = [("ru", "Русский"), ("tk", "Türkmençe")]

    # Always stored lowercase (save() and the check constraint), so plain uniqueness is
    # case-insensitive and Django's USERNAME_FIELD requirement is met.
    username = models.CharField(max_length=64, unique=True, validators=[USERNAME_VALIDATOR])
    email = models.EmailField()
    full_name = models.CharField(max_length=200, blank=True)
    preferred_language = models.CharField(max_length=2, choices=LANGUAGES, default="ru")
    is_active = models.BooleanField(default=True)
    is_staff = models.BooleanField(default=False, help_text="Operators who may use Django admin.")
    date_joined = models.DateTimeField(auto_now_add=True)
    password_changed_at = models.DateTimeField(null=True, blank=True)
    # Bumped whenever sessions must die (password change/reset). Tokens carry the value they
    # were issued with, so revocation is exact and does not depend on clock resolution.
    session_version = models.PositiveIntegerField(default=0)

    USERNAME_FIELD = "username"
    REQUIRED_FIELDS = ["email"]
    objects = UserManager()

    class Meta:
        constraints = [
            models.CheckConstraint(
                condition=models.Q(username=Lower("username")), name="accounts_user_username_lower"
            ),
            models.UniqueConstraint(Lower("email"), name="accounts_user_email_ci_unique"),
        ]

    def save(self, *args, **kwargs):
        self.username = normalize_username(self.username)
        super().save(*args, **kwargs)

    def __str__(self) -> str:
        return self.username

    def get_full_name(self) -> str:
        return self.full_name or self.username


class PasswordResetCode(UUIDModel):
    """A one-time recovery code. Only a keyed hash is stored, never the code itself."""

    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name="reset_codes")
    code_hash = models.CharField(max_length=64)
    created_at = models.DateTimeField(auto_now_add=True)
    expires_at = models.DateTimeField()
    attempts = models.PositiveSmallIntegerField(default=0)
    used_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        indexes = [models.Index(fields=["user", "-created_at"])]
