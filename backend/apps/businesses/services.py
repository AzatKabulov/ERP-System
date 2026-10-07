from django.db import IntegrityError, transaction

from apps.accounts import services as account_services
from apps.accounts.models import User
from apps.audit import services as audit
from apps.catalog import services as catalog_services
from apps.common.errors import ApiError
from apps.expenses import services as expense_services

from .models import Business, Location, Membership, Role


def _ensure_owner_remains(business: Business, exclude: Membership | None = None) -> None:
    owners = Membership.objects.select_for_update().filter(
        business=business, role=Role.OWNER, is_active=True
    )
    if exclude is not None:
        owners = owners.exclude(pk=exclude.pk)
    if not owners.exists():
        raise ApiError(
            "last_owner", "A business must keep at least one active owner", status_code=409
        )


@transaction.atomic
def create_business(*, name: str, owner: User, location_name: str = "") -> Business:
    business = Business.objects.create(name=name)
    Membership.objects.create(user=owner, business=business, role=Role.OWNER, all_locations=True)
    if location_name:
        Location.objects.create(business=business, name=location_name)
    catalog_services.create_default_units(business)
    expense_services.create_default_categories(business)
    audit.record("business.created", actor=owner, business=business, obj=business)
    return business


def create_staff(business, actor, *, data) -> Membership:
    password = data.get("password")
    try:
        with transaction.atomic():
            user = User.objects.create_user(
                data["username"],
                data["email"],
                password,
                full_name=data["full_name"],
                preferred_language=data["preferred_language"],
            )
            membership = Membership.objects.create(
                user=user,
                business=business,
                role=data["role"],
                all_locations=data["all_locations"],
            )
            membership.locations.set(data["locations"])
            audit.record(
                "staff.created",
                actor=actor,
                business=business,
                obj=membership,
                metadata={"role": data["role"], "username": user.username},
            )
            if not password:
                # Sent only after the account is committed.
                transaction.on_commit(
                    lambda: account_services.send_code(user, "welcome", business.name)
                )
    except IntegrityError as exc:  # a concurrent request took the username/email
        raise ApiError("conflict", "Username or email already in use", status_code=409) from exc
    return membership


@transaction.atomic
def update_staff(business, actor, membership: Membership, data) -> Membership:
    membership = Membership.objects.select_for_update().get(pk=membership.pk)
    new_role = data.get("role", membership.role)
    new_active = data.get("is_active", membership.is_active)
    loses_owner = (
        membership.role == Role.OWNER
        and membership.is_active
        and (new_role != Role.OWNER or not new_active)
    )
    if loses_owner:
        _ensure_owner_remains(business, exclude=membership)
    for field in ("role", "all_locations", "is_active"):
        if field in data:
            setattr(membership, field, data[field])
    membership.save()
    if "locations" in data:
        membership.locations.set(data["locations"])
    audit.record(
        "staff.updated",
        actor=actor,
        business=business,
        obj=membership,
        metadata={k: (v if k != "locations" else [str(x.pk) for x in v]) for k, v in data.items()},
    )
    return membership
