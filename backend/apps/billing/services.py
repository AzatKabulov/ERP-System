"""Every change to a client goes through here: it locks the client, changes it and writes the
SubscriptionEvent in one transaction, so the history can never disagree with the state."""

import calendar
import re
import zoneinfo
from datetime import date, datetime, time, timedelta
from decimal import Decimal

from django.conf import settings
from django.core.exceptions import ValidationError as DjangoValidationError
from django.db import transaction
from django.utils import timezone

from apps.accounts import services as account_services
from apps.accounts.models import User
from apps.businesses import services as business_services
from apps.businesses.models import Business, Membership, Role

from .models import Client, Plan, SubscriptionEvent
from .status import local_date

K = SubscriptionEvent.Kind


class BillingError(ValueError):
    """A request the console may show to the person using it (wrong input, missing reason)."""


def add_months(day: date, months: int) -> date:
    """Calendar months: 3 June + 1 month = 3 July; 31 January + 1 month = 28 February."""
    index = day.month - 1 + months
    year, month = day.year + index // 12, index % 12 + 1
    return date(year, month, min(day.day, calendar.monthrange(year, month)[1]))


def end_of_day(business: Business, day: date) -> datetime:
    """The last moment of `day` on the store's own calendar."""
    zone = zoneinfo.ZoneInfo(business.timezone)
    return datetime.combine(day, time(23, 59, 59), tzinfo=zone)


def _base_date(client: Client, now: datetime) -> date:
    """Where new time starts: after the current end if it hasn't passed, otherwise today. A store
    that renews late does not get the days it was already using for free, and one that renews
    early does not lose the days it had left."""
    if client.paid_until and now <= client.paid_until:
        return local_date(client.business, client.paid_until)
    return local_date(client.business, now)


def _need(note: str, what: str) -> str:
    note = (note or "").strip()
    if not note:
        raise BillingError(f"A reason is required for: {what}.")
    return note


def _lock(client: Client) -> Client:
    return Client.objects.select_for_update().select_related("business").get(pk=client.pk)


def _sync(original: Client, locked: Client) -> None:
    """The caller's object is a different instance from the locked one the change was made on:
    bring it up to date so it never shows the old state."""
    for field in ("paid_until", "plan_id", "is_trial", "override", "updated_at"):
        setattr(original, field, getattr(locked, field))


def _event(client: Client, kind: str, actor, **fields) -> SubscriptionEvent:
    return SubscriptionEvent.objects.create(client=client, kind=kind, actor=actor, **fields)


def preview_months(client: Client, months: int, now: datetime | None = None) -> date:
    now = now or timezone.now()
    return add_months(_base_date(client, now), months)


def preview_days(client: Client, days: int, now: datetime | None = None) -> date:
    now = now or timezone.now()
    return _base_date(client, now) + timedelta(days=days)


def _payment(amount, currency, method, reference) -> dict:
    if amount in (None, ""):
        return {}
    amount = Decimal(str(amount))
    if amount < 0:
        raise BillingError("An amount cannot be negative.")
    return {
        "amount": amount,
        "currency": (currency or "").upper(),
        "method": method or "",
        "reference": (reference or "").strip(),
    }


@transaction.atomic
def renew(
    client: Client,
    plan: Plan,
    actor,
    *,
    amount=None,
    currency="",
    method="",
    reference="",
    note="",
    now: datetime | None = None,
) -> SubscriptionEvent:
    """A package was paid for (usually cash): add its months."""
    if plan.months is None:
        raise BillingError("This plan has no fixed length: use custom days.")
    original, client = client, _lock(client)
    now = now or timezone.now()
    new_until = end_of_day(client.business, add_months(_base_date(client, now), plan.months))
    event = _event(
        client,
        K.RENEW,
        actor,
        plan=plan,
        months=plan.months,
        old_until=client.paid_until,
        new_until=new_until,
        note=(note or "").strip(),
        **_payment(
            plan.price if amount is None else amount, currency or plan.currency, method, reference
        ),
    )
    client.paid_until, client.plan, client.is_trial = new_until, plan, False
    client.save(update_fields=["paid_until", "plan", "is_trial", "updated_at"])
    _sync(original, client)
    return event


@transaction.atomic
def extend_days(
    client: Client,
    days: int,
    actor,
    *,
    note: str,
    amount=None,
    currency="",
    method="",
    reference="",
    now: datetime | None = None,
) -> SubscriptionEvent:
    """A custom number of days ("they'll pay next week", "they paid for 45 days"). Always with a
    reason. If money was received the client stops being a trial."""
    if not isinstance(days, int) or not 1 <= days <= 3650:
        raise BillingError("Days must be a whole number from 1 to 3650.")
    note = _need(note, "custom days")
    original, client = client, _lock(client)
    now = now or timezone.now()
    new_until = end_of_day(client.business, _base_date(client, now) + timedelta(days=days))
    paid = _payment(amount, currency, method, reference)
    event = _event(
        client,
        K.EXTEND,
        actor,
        days=days,
        old_until=client.paid_until,
        new_until=new_until,
        note=note,
        **paid,
    )
    client.paid_until = new_until
    if paid and paid["amount"] > 0:
        client.is_trial = False
    client.save(update_fields=["paid_until", "is_trial", "updated_at"])
    _sync(original, client)
    return event


@transaction.atomic
def correct_end(client: Client, new_end: date, actor, *, note: str) -> SubscriptionEvent:
    """Set the end date exactly (also earlier than now): for fixing a mistake."""
    note = _need(note, "correcting the end date")
    original, client = client, _lock(client)
    new_until = end_of_day(client.business, new_end)
    event = _event(
        client, K.CORRECTION, actor, old_until=client.paid_until, new_until=new_until, note=note
    )
    client.paid_until = new_until
    client.save(update_fields=["paid_until", "updated_at"])
    _sync(original, client)
    return event


@transaction.atomic
def start_trial(
    client: Client, actor, *, days: int | None = None, now: datetime | None = None
) -> SubscriptionEvent:
    original, client = client, _lock(client)
    now = now or timezone.now()
    days = settings.SUBSCRIPTION_TRIAL_DAYS if days is None else days
    new_until = end_of_day(client.business, local_date(client.business, now) + timedelta(days=days))
    event = _event(
        client, K.TRIAL, actor, days=days, old_until=client.paid_until, new_until=new_until
    )
    client.paid_until, client.is_trial, client.plan = new_until, True, None
    client.save(update_fields=["paid_until", "is_trial", "plan", "updated_at"])
    _sync(original, client)
    return event


@transaction.atomic
def suspend(client: Client, actor, *, note: str) -> SubscriptionEvent:
    note = _need(note, "suspending a client")
    original, client = client, _lock(client)
    event = _event(client, K.SUSPEND, actor, old_until=client.paid_until, note=note)
    client.override = Client.Override.SUSPENDED
    client.save(update_fields=["override", "updated_at"])
    _sync(original, client)
    return event


@transaction.atomic
def resume(client: Client, actor, *, note: str = "") -> SubscriptionEvent:
    original, client = client, _lock(client)
    event = _event(client, K.RESUME, actor, old_until=client.paid_until, note=(note or "").strip())
    client.override = Client.Override.NONE
    client.save(update_fields=["override", "updated_at"])
    _sync(original, client)
    return event


@transaction.atomic
def set_free(client: Client, on: bool, actor, *, note: str) -> SubscriptionEvent:
    note = _need(note, "free access")
    original, client = client, _lock(client)
    event = _event(client, K.FREE_ON if on else K.FREE_OFF, actor, note=note)
    client.override = Client.Override.FREE if on else Client.Override.NONE
    client.save(update_fields=["override", "updated_at"])
    _sync(original, client)
    return event


def _owner_membership(business: Business) -> Membership:
    owner = (
        Membership.objects.select_related("user")
        .filter(business=business, role=Role.OWNER, is_active=True, user__is_active=True)
        .order_by("created_at")
        .first()
    )
    if owner is None:
        raise BillingError("This store has no active owner.")
    return owner


def _fresh_temporary_password(user: User, temporary=True) -> str:
    for _ in range(10):
        password = account_services.generate_temporary_password()
        try:
            account_services.set_password(user, password, temporary=temporary)
        except DjangoValidationError:
            continue
        return password
    raise BillingError("Could not generate an acceptable password; try again.")


@transaction.atomic
def reset_owner_password(client: Client, actor) -> str:
    """The owner is locked out and no email reached them: a new temporary password, shown once
    to the person at the console, who must choose their own at the next sign-in. Everyone signed
    in as that owner is signed out."""
    client = _lock(client)
    owner = _owner_membership(client.business).user
    password = _fresh_temporary_password(owner)
    _event(client, K.PASSWORD_RESET, actor, note=f"Owner: {owner.username}")
    return password


_RUSSIAN = "абвгдежзийклмнопрстуфхцчшщыэюя"
_LATIN = "a b v g d e zh z i y k l m n o p r s t u f h c ch sh sch y e yu ya".split()
_TRANSLIT = {
    **dict(zip(_RUSSIAN, _LATIN, strict=True)),
    # the hard and soft signs vanish; Turkmen letters lose their marks
    **{"ё": "e", "ъ": "", "ь": "", "ä": "a", "ç": "c", "ž": "z", "ň": "n"},
    **{"ö": "o", "ş": "s", "ü": "u", "ý": "y"},
}


def suggest_login(store_name: str) -> str:
    """A readable, free login for a new store's owner: 'Willy Wonka' -> 'willy-wonka'."""
    text = "".join(_TRANSLIT.get(c, c) for c in store_name.lower())
    base = re.sub(r"[^a-z0-9]+", "-", text).strip("-")[:40] or "store"
    base = base.ljust(3, "x")
    candidate, n = base, 1
    while User.objects.filter(username=candidate).exists():
        n += 1
        candidate = f"{base}-{n}"
    return candidate


@transaction.atomic
def provision_client(
    *,
    store_name: str,
    owner_username: str,
    owner_name: str = "",
    owner_email: str = "",
    phone: str = "",
    language: str = "ru",
    plan: Plan | None = None,
    amount=None,
    currency="",
    method="",
    reference="",
    note="",
    actor=None,
) -> tuple[Client, str]:
    """Create a store, its owner with a temporary password (shown once, to be changed at first
    sign-in) and its subscription: a free trial, or a package already paid."""
    store_name = store_name.strip()
    if not store_name:
        raise BillingError("The store needs a name.")
    owner = User.objects.create_user(
        owner_username,
        owner_email.strip(),
        None,
        full_name=owner_name.strip(),
        preferred_language=language,
    )
    password = _fresh_temporary_password(owner)
    business = business_services.create_business(
        name=store_name, owner=owner, location_name=store_name
    )
    business.default_language = business.document_language = language
    business.phone = phone.strip()
    business.setup_status = (
        business.Setup.PENDING
    )  # the owner is asked about the shop at first sign-in
    business.save(
        update_fields=[
            "default_language",
            "document_language",
            "phone",
            "setup_status",
            "updated_at",
        ]
    )
    client = Client.objects.create(
        business=business,
        contact_name=owner_name.strip(),
        contact_phone=phone.strip(),
        contact_email=owner_email.strip(),
    )
    _event(client, K.CREATED, actor, note=(note or "").strip())
    if plan is None:
        start_trial(client, actor)
    else:
        renew(
            client,
            plan,
            actor,
            amount=amount,
            currency=currency,
            method=method,
            reference=reference,
            note=note,
        )
    return client, password
