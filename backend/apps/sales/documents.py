"""The receipt: one simple 80 mm PDF.

Text is set in DejaVu Sans (bundled in assets/fonts, embedded in every file) because it covers
Russian and Turkmen letters. The language is the business's document language unless the request
names one. A receipt never shows costs. It is deliberately plain: no tax, no legal format (the
owner decided on 2026-10-07 that none is needed). The Turkmen wording is provisional (a
fluent-speaker review is planned, PLAN.md D14)."""

import io
from decimal import Decimal
from functools import lru_cache
from zoneinfo import ZoneInfo

from django.conf import settings
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.pdfgen import canvas

NBSP = " "
REGULAR = "DejaVuSans"
BOLD = "DejaVuSans-Bold"

LABELS = {
    "ru": {
        "receipt": "Чек",
        "cashier": "Кассир",
        "location": "Точка",
        "customer": "Покупатель",
        "total": "Итого",
        "payment": "Оплата",
        "cash": "Наличные",
        "card": "Карта",
        "warranty": "Гарантия: {n} мес.",
        "phone": "Тел.",
        "thanks": "Спасибо за покупку!",
        "note": "Примечание",
    },
    "tk": {
        "receipt": "Çek",
        "cashier": "Kassir",
        "location": "Nokat",
        "customer": "Alyjy",
        "total": "Jemi",
        "payment": "Töleg",
        "cash": "Nagt",
        "card": "Kart",
        "warranty": "Kepillik: {n} aý",
        "phone": "Tel.",
        "thanks": "Satyn alanyňyz üçin sagboluň!",
        "note": "Bellik",
    },
}


@lru_cache(maxsize=1)
def _register_fonts() -> None:
    folder = settings.BASE_DIR / "assets" / "fonts"
    pdfmetrics.registerFont(TTFont(REGULAR, str(folder / "DejaVuSans.ttf")))
    pdfmetrics.registerFont(TTFont(BOLD, str(folder / "DejaVuSans-Bold.ttf")))


def money(value: Decimal) -> str:
    """'1 234,50 TMT' (decimal comma, no-break spaces), the same look as the app."""
    sign = "−" if value < 0 else ""
    whole, _, cents = f"{abs(value):.2f}".partition(".")
    groups = f"{int(whole):,}".replace(",", NBSP)
    return f"{sign}{groups},{cents}{NBSP}TMT"


def quantity(value: Decimal, unit_decimals: int) -> str:
    """At least `unit_decimals` decimals and no needless trailing zeros ('2', '2,5', '2,50')."""
    whole, _, fraction = f"{value:.3f}".partition(".")
    while len(fraction) > unit_decimals and fraction.endswith("0"):
        fraction = fraction[:-1]
    return f"{int(whole):,}".replace(",", NBSP) + (f",{fraction}" if fraction else "")


def number(sale) -> str:
    return f"S-{sale.number:06d}"


class _Writer:
    """Places text from the top of a page downward, wrapping long lines. The receipt roll is laid
    out twice: once to measure its height, once for real."""

    def __init__(self, pdf: canvas.Canvas, width: float, height: float, margin: float):
        self.pdf, self.width, self.height = pdf, width, height
        self.margin = margin
        self.y = margin  # distance from the top edge

    @property
    def inner(self) -> float:
        return self.width - 2 * self.margin

    def space(self, points: float) -> None:
        self.y += points

    def _font(self, size: float, bold: bool) -> str:
        font = BOLD if bold else REGULAR
        self.pdf.setFont(font, size)
        return font

    def line(self, text: str, size: float = 8, bold: bool = False, align: str = "left") -> None:
        self._font(size, bold)
        baseline = self.height - self.y - size
        if align == "center":
            self.pdf.drawCentredString(self.width / 2, baseline, text)
        elif align == "right":
            self.pdf.drawRightString(self.width - self.margin, baseline, text)
        else:
            self.pdf.drawString(self.margin, baseline, text)
        self.y += size * 1.4

    def wrap(self, text: str, size: float, bold: bool, width: float) -> list[str]:
        font = BOLD if bold else REGULAR
        lines: list[str] = []
        for paragraph in str(text).splitlines() or [""]:
            current = ""
            for word in paragraph.split(" "):
                candidate = f"{current} {word}".strip() if current else word
                if pdfmetrics.stringWidth(candidate, font, size) <= width:
                    current = candidate
                    continue
                if current:
                    lines.append(current)
                while pdfmetrics.stringWidth(word, font, size) > width and len(word) > 1:
                    cut = len(word)
                    while cut > 1 and pdfmetrics.stringWidth(word[:cut], font, size) > width:
                        cut -= 1
                    lines.append(word[:cut])
                    word = word[cut:]
                current = word
            lines.append(current)
        return lines

    def paragraph(self, text: str, size: float = 8, bold: bool = False, align: str = "left"):
        for part in self.wrap(text, size, bold, self.inner):
            self.line(part, size, bold, align)

    def pair(self, left: str, right: str, size: float = 8, bold: bool = False) -> None:
        """`left` at the left margin and `right` flush right on the same line."""
        self._font(size, bold)
        baseline = self.height - self.y - size
        self.pdf.drawString(self.margin, baseline, left)
        self.pdf.drawRightString(self.width - self.margin, baseline, right)
        self.y += size * 1.4

    def rule(self) -> None:
        y = self.height - self.y - 2
        self.pdf.setLineWidth(0.5)
        self.pdf.line(self.margin, y, self.width - self.margin, y)
        self.y += 6


def _business_lines(business, t: dict) -> list[str]:
    lines = []
    if business.address:
        lines.append(business.address)
    if business.phone:
        lines.append(f"{t['phone']}: {business.phone}")
    return lines


def _when(sale) -> str:
    local = sale.created_at.astimezone(ZoneInfo(sale.business.timezone))
    return local.strftime("%d.%m.%Y %H:%M")


def _receipt(w: _Writer, sale, t: dict) -> None:
    business = sale.business
    w.paragraph(business.name, 11, True, "center")
    for text in _business_lines(business, t):
        w.paragraph(text, 8, False, "center")
    w.space(4)
    w.rule()
    w.pair(f"{t['receipt']} {number(sale)}", _when(sale), 8, True)
    w.paragraph(f"{t['cashier']}: {sale.cashier.full_name or sale.cashier.username}", 8)
    w.paragraph(f"{t['location']}: {sale.location.name}", 8)
    if sale.customer_name:
        w.paragraph(f"{t['customer']}: {sale.customer_name}", 8)
    w.rule()
    for line in sale.lines.all():
        w.paragraph(line.name, 8, True)
        w.pair(
            f"{quantity(line.quantity, line.unit_decimals)} {line.unit_symbol} × "
            f"{money(line.unit_price)}",
            money(line.line_total),
            8,
        )
        if line.warranty_months:
            w.line(f"  {t['warranty'].format(n=line.warranty_months)}", 7)
        w.space(2)
    w.rule()
    w.pair(t["total"], money(sale.total), 11, True)
    w.pair(t["payment"], t[sale.payment_method], 8)
    if sale.note:
        w.space(4)
        w.paragraph(f"{t['note']}: {sale.note}", 7)
    w.space(8)
    w.paragraph(t["thanks"], 8, False, "center")


def render_receipt(sale, *, lang: str = "ru") -> bytes:
    """The receipt PDF for `sale` (with business, location, cashier and lines loaded)."""
    _register_fonts()
    t = LABELS[lang]
    width = 80 / 25.4 * 72  # an 80 mm receipt roll
    measure = _Writer(canvas.Canvas(io.BytesIO(), pagesize=(width, 4000)), width, 4000, 10)
    _receipt(measure, sale, t)
    height = measure.y + 10
    out = io.BytesIO()
    pdf = canvas.Canvas(out, pagesize=(width, height), pageCompression=1, initialFontName=REGULAR)
    _receipt(_Writer(pdf, width, height, 10), sale, t)
    pdf.setTitle(f"{t['receipt']} {number(sale)}")
    pdf.setAuthor(sale.business.name)
    pdf.save()
    return out.getvalue()
