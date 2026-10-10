from decimal import ROUND_HALF_UP, Decimal

from .models import Business, ExchangeRate

CENT = Decimal("0.01")


def current_rate(business: Business, currency: str = "USD") -> ExchangeRate | None:
    """The most recent rate entered for this business, or None if there is none yet."""
    return (
        ExchangeRate.objects.filter(business=business, currency=currency)
        .order_by("-created_at", "-id")
        .first()
    )


def to_tmt(amount: Decimal, currency: str, rate: ExchangeRate | None) -> Decimal | None:
    """Convert a stated price to TMT, rounding half up to 2 decimals (decision D3).
    Returns None for a USD price when no rate has been entered."""
    if currency == "TMT":
        return amount.quantize(CENT, rounding=ROUND_HALF_UP)
    if rate is None:
        return None
    return (amount * rate.rate).quantize(CENT, rounding=ROUND_HALF_UP)
