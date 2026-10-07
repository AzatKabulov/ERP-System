"""Receipts and invoices as PDFs.

Text is set in DejaVu Sans (bundled in assets/fonts, embedded in every file) because it covers
Russian and Turkmen letters. The document language is chosen per request and is independent of
the interface language. Documents never show costs. The Turkmen wording is provisional (a
fluent-speaker review is planned, PLAN.md D14); the legal wording of an invoice is open (D4)."""

import io
from decimal import Decimal
from functools import lru_cache
from zoneinfo import ZoneInfo

from django.conf import settings
from reportlab.lib.pagesizes import A4
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.pdfgen import canvas

NBSP = " "
REGULAR = "DejaVuSans"
BOLD = "DejaVuSans-Bold"

LABELS = {
    "ru": {
        "receipt": "Чек",
        "invoice": "Накладная",
        "date": "Дата",
        "cashier": "Кассир",
        "location": "Точка",
        "customer": "Покупатель",
        "item": "Товар",
        "qty": "Кол-во",
        "price": "Цена",
        "discount": "Скидка",
        "sum": "Сумма",
        "total": "Итого",
        "paid": "Оплачено",
        "change": "Сдача",
        "cash": "Наличные",
        "card": "Карта",
        "transfer": "Перевод",
        "warranty": "Гарантия: {n} мес.",
        "phone": "Тел.",
        "tax": "Рег. №",
        "thanks": "Спасибо за покупку!",
        "payments": "Оплата",
        "note": "Примечание",
    },
    "tk": {
        "receipt": "Çek",
        "invoice": "Nakladnoý",
        "date": "Senesi",
        "cashier": "Kassir",
        "location": "Nokat",
        "customer": "Alyjy",
        "item": "Haryt",
        "qty": "Sany",
        "price": "Bahasy",
        "discount": "Arzanladyş",
        "sum": "Möçberi",
        "total": "Jemi",
        "paid": "Tölendi",
        "change": "Yzyna berlen",
        "cash": "Nagt",
        "card": "Kart",
        "transfer": "Geçirim",
        "warranty": "Kepillik: {n} aý",
        "phone": "Tel.",
        "tax": "Hasaba alyş №",
        "thanks": "Satyn alanyňyz üçin sagboluň!",
        "payments": "Töleg",
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
    """Places text from the top of a page downward, wrapping long lines and (for A4) breaking
    onto a new page. The receipt roll is laid out twice: once to measure its height, once for
    real."""

    def __init__(self, pdf: canvas.Canvas, width: float, height: float, margin: float, paginate):
        self.pdf, self.width, self.height = pdf, width, height
        self.margin, self.paginate = margin, paginate
        self.y = margin  # distance from the top edge

    @property
    def inner(self) -> float:
        return self.width - 2 * self.margin

    def ensure(self, needed: float) -> None:
        if self.paginate and self.y + needed > self.height - self.margin:
            self.pdf.showPage()
            self.y = self.margin

    def space(self, points: float) -> None:
        self.y += points

    def _font(self, size: float, bold: bool) -> str:
        font = BOLD if bold else REGULAR
        self.pdf.setFont(font, size)
        return font

    def line(self, text: str, size: float = 8, bold: bool = False, align: str = "left") -> None:
        self.ensure(size * 1.4)
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
        self.ensure(size * 1.4)
        self._font(size, bold)
        baseline = self.height - self.y - size
        self.pdf.drawString(self.margin, baseline, left)
        self.pdf.drawRightString(self.width - self.margin, baseline, right)
        self.y += size * 1.4

    def rule(self) -> None:
        self.ensure(6)
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
    if business.tax_number:
        lines.append(f"{t['tax']}: {business.tax_number}")
    return lines


def _when(sale) -> str:
    local = sale.created_at.astimezone(ZoneInfo(sale.business.timezone))
    return local.strftime("%d.%m.%Y %H:%M")


def _payment_rows(sale, t: dict) -> list[tuple[str, str]]:
    return [(t[p.method], money(p.amount)) for p in sale.payments.all()]


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
            money(line.gross),
            8,
        )
        if line.discount:
            w.pair(f"  {t['discount']}", f"−{money(line.discount)}", 8)
        if line.warranty_months:
            w.line(f"  {t['warranty'].format(n=line.warranty_months)}", 7)
        w.space(2)
    w.rule()
    w.pair(t["total"], money(sale.total), 11, True)
    for label, amount in _payment_rows(sale, t):
        w.pair(label, amount, 8)
    if sale.change_given:
        w.pair(t["change"], money(sale.change_given), 8)
    if sale.note:
        w.space(4)
        w.paragraph(f"{t['note']}: {sale.note}", 7)
    w.space(8)
    w.paragraph(t["thanks"], 8, False, "center")


def _invoice(w: _Writer, sale, t: dict) -> None:
    business = sale.business
    w.line(business.name, 14, True)
    for text in _business_lines(business, t):
        w.paragraph(text, 9)
    w.space(8)
    w.line(f"{t['invoice']} {number(sale)}", 16, True)
    w.line(f"{t['date']}: {_when(sale)}", 9)
    w.line(f"{t['location']}: {sale.location.name}", 9)
    w.line(f"{t['cashier']}: {sale.cashier.full_name or sale.cashier.username}", 9)
    if sale.customer_name:
        customer = sale.customer_name + (f", {sale.customer_phone}" if sale.customer_phone else "")
        w.paragraph(f"{t['customer']}: {customer}", 9)
    w.space(8)

    left, right = w.margin, w.width - w.margin
    columns = {  # right edges of the numeric columns, and the width left for the name
        "qty": right - 215,
        "price": right - 140,
        "discount": right - 70,
        "sum": right,
    }
    name_width = columns["qty"] - left - 40 - 24

    def header() -> None:
        w.ensure(30)
        w.rule()
        baseline = w.height - w.y - 9
        w.pdf.setFont(BOLD, 9)
        w.pdf.drawString(left, baseline, "№")
        w.pdf.drawString(left + 24, baseline, t["item"])
        for key in ("qty", "price", "discount", "sum"):
            w.pdf.drawRightString(columns[key], baseline, t[key])
        w.y += 14
        w.rule()

    header()
    for index, line in enumerate(sale.lines.all(), start=1):
        name_lines = w.wrap(f"{line.name} ({line.sku})", 9, False, name_width)
        extra = [t["warranty"].format(n=line.warranty_months)] if line.warranty_months else []
        w.ensure(12 * (len(name_lines) + len(extra)) + 4)
        top = w.y
        baseline = w.height - top - 9
        w.pdf.setFont(REGULAR, 9)
        w.pdf.drawString(left, baseline, str(index))
        w.pdf.drawRightString(
            columns["qty"],
            baseline,
            f"{quantity(line.quantity, line.unit_decimals)} {line.unit_symbol}",
        )
        w.pdf.drawRightString(columns["price"], baseline, money(line.unit_price))
        w.pdf.drawRightString(
            columns["discount"], baseline, money(line.discount) if line.discount else "—"
        )
        w.pdf.drawRightString(columns["sum"], baseline, money(line.line_total))
        for text in name_lines:
            w.pdf.setFont(REGULAR, 9)
            w.pdf.drawString(left + 24, w.height - w.y - 9, text)
            w.y += 12
        for text in extra:
            w.pdf.setFont(REGULAR, 8)
            w.pdf.drawString(left + 24, w.height - w.y - 8, text)
            w.y += 11
        w.y += 3
    w.rule()
    w.pair(t["total"], money(sale.total), 12, True)
    w.space(6)
    w.line(t["payments"], 9, True)
    for label, amount in _payment_rows(sale, t):
        w.pair(label, amount, 9)
    if sale.change_given:
        w.pair(t["change"], money(sale.change_given), 9)
    if sale.note:
        w.space(6)
        w.paragraph(f"{t['note']}: {sale.note}", 8)


def render_document(sale, *, kind: str = "receipt", lang: str = "ru") -> bytes:
    """The PDF for `sale` (with business, location, cashier, lines and payments loaded)."""
    _register_fonts()
    t = LABELS[lang]
    title = f"{t[kind]} {number(sale)}"
    out = io.BytesIO()
    if kind == "invoice":
        pdf = canvas.Canvas(out, pagesize=A4, pageCompression=1, initialFontName=REGULAR)
        writer = _Writer(pdf, A4[0], A4[1], 40, paginate=True)
        _invoice(writer, sale, t)
    else:
        width = 80 / 25.4 * 72  # an 80 mm receipt roll
        measure = _Writer(
            canvas.Canvas(io.BytesIO(), pagesize=(width, 4000)), width, 4000, 10, False
        )
        _receipt(measure, sale, t)
        height = measure.y + 10
        pdf = canvas.Canvas(
            out, pagesize=(width, height), pageCompression=1, initialFontName=REGULAR
        )
        _receipt(_Writer(pdf, width, height, 10, False), sale, t)
    pdf.setTitle(title)
    pdf.setAuthor(sale.business.name)
    pdf.save()
    return out.getvalue()
