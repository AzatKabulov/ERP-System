"""Opening, noting and closing warranty claims.

Opening checks the warranty of the sale line the claim is about. An expired or absent warranty
is accepted only by someone with `warranty.override`, who must say why. Closing picks one
outcome:

* repair      - nothing moves.
* rejected    - nothing moves; a note says why.
* replacement - one stock posting: a sellable unit leaves (`warranty_out`) and the defective one
                comes in as damaged (`warranty_in`) at what the sold unit cost.
* refund      - a customer return of the sale (the goods come back damaged, the customer is
                refunded what they paid), linked to the claim.

Callers wrap `close_claim` in `run_idempotent`; the claim row is locked, so two attempts to close
one claim can never both succeed.
"""

from decimal import ROUND_HALF_UP, Decimal

from django.db import transaction
from django.db.models import Sum
from django.shortcuts import get_object_or_404
from django.utils import timezone
from rest_framework import exceptions

from apps.audit import services as audit
from apps.businesses.access import require_location
from apps.businesses.permissions import has_permission
from apps.catalog.models import Unit
from apps.catalog.services import check_quantity_precision
from apps.common.errors import ApiError
from apps.inventory import services as inventory
from apps.inventory.models import Condition, MovementType, StockMovement
from apps.purchasing.services import next_number
from apps.sales import returns
from apps.sales.models import Sale, SaleLine, SaleReturn, SaleReturnLine

from .entitlement import warranty_until
from .models import WarrantyClaim, WarrantyEvent

ZERO = Decimal("0")
CENT = Decimal("0.01")
Outcome = WarrantyClaim.Outcome


def _required(field: str, message: str) -> ApiError:
    return ApiError(
        "validation_error", message, fields={field: [{"code": "required", "message": "Required"}]}
    )


def _check_entitlement(business, sale, line, override: bool) -> bool:
    """Whether the claim is out of warranty. Refuses (409) unless an override was given."""
    until = warranty_until(business, sale, line)
    if until is None:
        problem = ApiError(
            "no_warranty", "This product was sold without a warranty", status_code=409
        )
    elif business.local_today() > until:
        problem = ApiError(
            "warranty_expired",
            "The warranty has expired",
            status_code=409,
            params={"until": until.isoformat()},
        )
    else:
        return False
    if not override:
        raise problem
    return True


def open_claim(business, actor, membership, data: dict) -> WarrantyClaim:
    """`data`: {"sale_line" (id), "quantity", "problem", "override", "override_note"}."""
    override = bool(data.get("override"))
    note = (data.get("override_note") or "").strip()
    if override:
        if not has_permission(membership.role, "warranty.override"):
            raise exceptions.PermissionDenied()
        if not note:
            raise _required("override_note", "A reason is required to accept this claim")
    with transaction.atomic():
        line = (
            SaleLine.objects.select_related("product")
            .filter(pk=data["sale_line"], sale__business=business)
            .first()
        )
        if line is None:
            raise ApiError(
                "validation_error",
                "This sale line does not exist",
                fields={"sale_line": [{"code": "does_not_exist", "message": "Does not exist"}]},
            )
        # Locked like a return is, so a claim and a return of the same sale take turns.
        sale = Sale.objects.select_for_update().get(pk=line.sale_id)
        require_location(membership, sale.location_id)
        quantity = data["quantity"]
        check_quantity_precision(quantity, Unit(decimal_places=line.unit_decimals))
        returned = (
            SaleReturnLine.objects.filter(sale_line=line).aggregate(t=Sum("quantity"))["t"] or ZERO
        )
        claimable = line.quantity - returned
        if quantity > claimable:
            raise ApiError(
                "over_claim",
                "More than was sold and not yet returned",
                status_code=409,
                params={"claimable": str(claimable)},
            )
        out_of_warranty = _check_entitlement(business, sale, line, override)
        claim = WarrantyClaim(
            business=business,
            sale=sale,
            sale_line=line,
            product=line.product,
            sku=line.sku,
            name=line.name,
            quantity=quantity,
            customer_name=sale.customer_name,
            customer_phone=sale.customer_phone,
            problem=data["problem"],
            out_of_warranty=out_of_warranty,
            opened_by=actor,
        )
        claim.number = next_number(business, "warranty")
        claim.save(force_insert=True)
        WarrantyEvent.objects.create(
            claim=claim,
            kind=WarrantyEvent.Kind.OPENED,
            note=note if out_of_warranty else "",
            actor=actor,
        )
        audit.record(
            "warranty.opened",
            actor=actor,
            business=business,
            obj=claim,
            metadata={
                "number": claim.number,
                "sale": sale.number,
                "quantity": quantity,
                "out_of_warranty": out_of_warranty,
                "override_note": note if out_of_warranty else "",
            },
        )
    return claim


def _lock(business, membership, claim_id) -> WarrantyClaim:
    claim = get_object_or_404(
        WarrantyClaim.objects.select_for_update(of=("self",)).select_related("sale"),
        pk=claim_id,
        business=business,
    )
    require_location(membership, claim.sale.location_id)
    return claim


def _closed() -> ApiError:
    return ApiError("claim_closed", "This claim is already closed", status_code=409)


def add_note(business, actor, membership, claim_id, note: str) -> WarrantyClaim:
    with transaction.atomic():
        claim = _lock(business, membership, claim_id)
        if claim.status != WarrantyClaim.Status.OPEN:
            raise _closed()
        WarrantyEvent.objects.create(
            claim=claim, kind=WarrantyEvent.Kind.NOTE, note=note.strip(), actor=actor
        )
        audit.record(
            "warranty.noted",
            actor=actor,
            business=business,
            obj=claim,
            metadata={"number": claim.number},
        )
    return claim


def _replace(business, actor, claim, sale, line) -> None:
    """One posting for the swap: the new unit leaves sellable stock, the defective one arrives
    in the damaged pile, valued at what the sold unit cost (average over the sold line)."""
    unit_cost = (line.cost_total / line.quantity).quantize(CENT, rounding=ROUND_HALF_UP)
    inventory.post(
        business,
        actor,
        [
            inventory.Line(
                product=line.product,
                location=sale.location,
                quantity=-claim.quantity,
                movement_type=MovementType.WARRANTY_OUT,
                condition=Condition.SELLABLE,
            ),
            inventory.Line(
                product=line.product,
                location=sale.location,
                quantity=claim.quantity,
                unit_cost=unit_cost,
                movement_type=MovementType.WARRANTY_IN,
                condition=Condition.DAMAGED,
            ),
        ],
        document_type="warranty",
        document_id=claim.pk,
        reason=f"Warranty {claim}",
    )


def close_claim(business, actor, membership, claim_id, outcome: str, note: str) -> WarrantyClaim:
    note = (note or "").strip()
    if outcome == Outcome.REJECTED and not note:
        raise _required("note", "Say why the claim is rejected")
    with transaction.atomic():
        if outcome in (Outcome.REPLACEMENT, Outcome.REFUND):
            # Queue behind the business's other multi-step stock postings (see inventory).
            inventory.lock_business_stock(business)
        claim = _lock(business, membership, claim_id)
        if claim.status != WarrantyClaim.Status.OPEN:
            raise _closed()
        sale = Sale.objects.select_related("location").get(pk=claim.sale_id)
        line = SaleLine.objects.select_related("product__unit").get(pk=claim.sale_line_id)
        if outcome == Outcome.REPLACEMENT:
            _replace(business, actor, claim, sale, line)
        elif outcome == Outcome.REFUND:
            made = returns.create_return(
                business,
                actor,
                membership,
                claim.sale_id,
                {
                    "lines": [
                        {
                            "sale_line": line.pk,
                            "quantity": claim.quantity,
                            "condition": "damaged",
                        }
                    ],
                    "reason": f"Warranty {claim}",
                    "note": note,
                },
                warranty_claim_id=claim.pk,
                ignore_window=True,
            )
            claim.return_id = made.pk
        claim.status = WarrantyClaim.Status.CLOSED
        claim.outcome = outcome
        claim.closed_by = actor
        claim.closed_at = timezone.now()
        claim.resolution_note = note
        claim.save()
        WarrantyEvent.objects.create(
            claim=claim, kind=WarrantyEvent.Kind.CLOSED, note=note, outcome=outcome, actor=actor
        )
        audit.record(
            "warranty.closed",
            actor=actor,
            business=business,
            obj=claim,
            metadata={"number": claim.number, "outcome": outcome, "return": claim.return_id},
        )
    return claim


def reconcile(business=None) -> list[str]:
    """Claim-level checks: a closed claim has an outcome and a time, a refund has its return, a
    replacement has its two movements (and nothing else has any), and no claim is for more than
    was sold."""
    scope = {"business": business} if business is not None else {}
    differences: list[str] = []
    moved = {
        (r["document_id"], r["movement_type"]): r["total"]
        for r in StockMovement.objects.filter(document_type="warranty", **scope)
        .values("document_id", "movement_type")
        .annotate(total=Sum("quantity"))
    }
    claims = list(WarrantyClaim.objects.filter(**scope).select_related("sale_line"))
    linked = {
        r["pk"]: r
        for r in SaleReturn.objects.filter(warranty_claim_id__isnull=False, **scope)
        .values("pk", "warranty_claim_id", "sale_id")
        .annotate(quantity=Sum("lines__quantity"))
    }
    for claim in claims:
        label = f"W-{claim.number:04d}"
        closed = claim.status == WarrantyClaim.Status.CLOSED
        if closed and (claim.outcome is None or claim.closed_at is None):
            differences.append(f"{label}: closed without an outcome or a time")
        if not closed and (claim.outcome is not None or claim.closed_at is not None):
            differences.append(f"{label}: open but has an outcome or a closing time")
        if claim.quantity > claim.sale_line.quantity:
            differences.append(
                f"{label}: claims {claim.quantity} of {claim.sale_line.quantity} sold"
            )
        is_refund = claim.outcome == Outcome.REFUND
        if is_refund:
            made = linked.get(claim.return_id)
            if claim.return_id is None or made is None:
                differences.append(f"{label}: refund without a return")
            elif made["warranty_claim_id"] != claim.pk or made["sale_id"] != claim.sale_id:
                differences.append(f"{label}: its return belongs to another claim or sale")
            elif made["quantity"] != claim.quantity:
                differences.append(
                    f"{label}: claims {claim.quantity} but the return took {made['quantity']}"
                )
        elif claim.return_id is not None:
            differences.append(f"{label}: has a return but the outcome is {claim.outcome}")
        out = moved.get((claim.pk, MovementType.WARRANTY_OUT), ZERO) or ZERO
        into = moved.get((claim.pk, MovementType.WARRANTY_IN), ZERO) or ZERO
        expected_out, expected_in = (
            (-claim.quantity, claim.quantity)
            if claim.outcome == Outcome.REPLACEMENT
            else (ZERO, ZERO)
        )
        if (out, into) != (expected_out, expected_in):
            differences.append(
                f"{label}: warranty_out={out} warranty_in={into}, expected "
                f"{expected_out} and {expected_in}"
            )
    by_claim = {claim.pk: claim for claim in claims}
    for return_id, made in linked.items():
        claim = by_claim.get(made["warranty_claim_id"])
        if claim is None or claim.return_id != return_id:
            differences.append(f"return {return_id}: points at a claim that does not point back")
    return differences
