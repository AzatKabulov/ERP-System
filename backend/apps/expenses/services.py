"""Recording, correcting and voiding expenses. Every change is audited; a voided expense is
never edited again and never deleted."""

from decimal import Decimal

from django.db import transaction
from django.db.models import Count, Sum
from django.shortcuts import get_object_or_404
from django.utils import timezone

from apps.audit import services as audit
from apps.businesses.access import require_location
from apps.common.errors import ApiError

from .models import Expense, ExpenseCategory

CENT = Decimal("0.01")

# Starting suggestions for a new business (shop data, editable; owner decision 2026-10-07).
DEFAULT_CATEGORIES = ["Аренда", "Зарплата", "Коммунальные услуги", "Транспорт", "Прочее"]

# What a correction may change, and which of those point at other records.
FIELDS = ("category", "location", "amount", "spent_on", "description", "attachment")
REFERENCES = ("category", "location", "attachment")


def create_default_categories(business) -> None:
    for name in DEFAULT_CATEGORIES:
        ExpenseCategory.objects.get_or_create(business=business, name=name)


@transaction.atomic
def save_category(business, actor, data: dict, instance: ExpenseCategory | None = None):
    if instance is None:
        instance = ExpenseCategory(business=business)
        action = "expense_category.created"
    else:
        action = "expense_category.updated"
    for field in ("name", "is_active"):
        if field in data:
            setattr(instance, field, data[field])
    instance.save()
    audit.record(
        action,
        actor=actor,
        business=business,
        obj=instance,
        metadata={"name": instance.name, "is_active": instance.is_active},
    )
    return instance


@transaction.atomic
def create_expense(business, actor, membership, data: dict) -> Expense:
    require_location(membership, data["location"].pk)
    expense = Expense.objects.create(
        business=business,
        category=data["category"],
        location=data["location"],
        amount=data["amount"],
        spent_on=data["spent_on"],
        description=data.get("description", ""),
        attachment=data.get("attachment"),
        created_by=actor,
    )
    audit.record(
        "expense.created",
        actor=actor,
        business=business,
        obj=expense,
        metadata={
            "amount": expense.amount,
            "spent_on": expense.spent_on,
            "category": expense.category_id,
            "location": expense.location_id,
            "attachment": expense.attachment_id,
        },
    )
    return expense


def _lock(business, membership, expense_id) -> Expense:
    expense = get_object_or_404(
        Expense.objects.select_for_update(), pk=expense_id, business=business
    )
    require_location(membership, expense.location_id)
    return expense


def _value(expense: Expense, field: str):
    """A field as it is written to the audit trail: references by id, money to the cent."""
    if field in REFERENCES:
        return getattr(expense, f"{field}_id")
    value = getattr(expense, field)
    return value.quantize(CENT) if field == "amount" else value


def update_expense(business, actor, membership, expense_id, data: dict) -> Expense:
    """Apply a correction. The row is locked so a correction and a void cannot interleave; the
    audit event carries the old and the new value of everything that actually changed."""
    with transaction.atomic():
        expense = _lock(business, membership, expense_id)
        if expense.is_voided:
            raise ApiError("expense_void", "A voided expense cannot be changed", status_code=409)
        if "location" in data:
            require_location(membership, data["location"].pk)
        changes: dict = {}
        for field in FIELDS:
            if field not in data:
                continue
            old = _value(expense, field)
            setattr(expense, field, data[field])
            new = _value(expense, field)
            if old != new:
                changes[field] = {"old": old, "new": new}
        if changes:
            expense.save()
            audit.record(
                "expense.updated",
                actor=actor,
                business=business,
                obj=expense,
                metadata={"changes": changes},
            )
    return expense


def void_expense(business, actor, membership, expense_id, reason: str) -> Expense:
    with transaction.atomic():
        expense = _lock(business, membership, expense_id)
        if expense.is_voided:
            raise ApiError("already_void", "This expense is already void", status_code=409)
        expense.voided_at = timezone.now()
        expense.voided_by = actor
        expense.void_reason = reason.strip()
        expense.save(update_fields=["voided_at", "voided_by", "void_reason", "updated_at"])
        audit.record(
            "expense.voided",
            actor=actor,
            business=business,
            obj=expense,
            metadata={"amount": expense.amount, "reason": expense.void_reason},
        )
    return expense


def summarize(expenses) -> dict:
    """Totals of the live (not voided) expenses in `expenses`, overall and per category."""
    rows = sorted(
        expenses.filter(voided_at__isnull=True)
        .order_by()
        .values("category_id", "category__name")
        .annotate(total=Sum("amount"), count=Count("id")),
        key=lambda r: (-r["total"], r["category__name"]),  # the biggest spending first
    )
    return {
        "total": str(sum((r["total"] for r in rows), Decimal(0)).quantize(CENT)),
        "count": sum(r["count"] for r in rows),
        "by_category": [
            {
                "category": {"id": str(r["category_id"]), "name": r["category__name"]},
                "total": str(r["total"].quantize(CENT)),
                "count": r["count"],
            }
            for r in rows
        ],
    }
