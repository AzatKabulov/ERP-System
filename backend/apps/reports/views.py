"""Reports, CSV exports and the dashboard. Everything here only reads (GET); cost, profit and
inventory-value keys are left out of the answer for roles without the matching `*.cost.view`
right, and every figure is limited to the caller's locations."""

from django.http import HttpResponse
from rest_framework.response import Response

from apps.audit import services as audit
from apps.businesses.access import BusinessAPIView
from apps.catalog import csvio
from apps.common.negotiation import IgnoreClientContentNegotiation

from . import exports, summary
from .expenses import expenses_report
from .purchases import purchasing_report
from .returns import returns_report
from .sales import sales_report
from .scope import ReportContext
from .stock import stock_report


class ReportView(BusinessAPIView):
    """A JSON report. Subclasses build the answer from the validated period, location and
    rights. `full` is set by the export, which is not capped like the screen version."""

    required_permission = "report.view"

    def build(self, ctx: ReportContext, *, full: bool = False) -> dict:
        raise NotImplementedError

    def get(self, request, business_id):
        return Response(self.build(ReportContext.from_request(request)))


class ExportMixin:
    """The same report as a `;`-separated UTF-8 CSV with a byte-order mark. Same permission,
    query parameters and left-out keys as the JSON report. Every export is audited."""

    slug = ""
    table = None
    content_negotiation_class = IgnoreClientContentNegotiation

    def get(self, request, business_id):
        ctx = ReportContext.from_request(request)
        columns, rows, text_columns = self.table(self.build(ctx, full=True))
        content = csvio.table_csv(columns, rows, text_columns=text_columns)
        audit.record(
            "report.exported",
            actor=request.user,
            business=request.business,
            metadata={
                "slug": self.slug,
                "period": ctx.period.as_json(),
                "location": ctx.scope.location_json,
                "rows": len(rows),
            },
        )
        period = ctx.period.as_json()
        response = HttpResponse(content, content_type="text/csv; charset=utf-8")
        response["Content-Disposition"] = (
            f'attachment; filename="{self.slug}-{period["from"]}-{period["to"]}.csv"'
        )
        response["X-Content-Type-Options"] = "nosniff"
        response["Cache-Control"] = "private, no-store"
        return response


# ---- reports -------------------------------------------------------------------------------


class SummaryReportView(ReportView):
    def build(self, ctx, *, full=False):
        return summary.summary_report(ctx)


class SalesReportView(ReportView):
    def build(self, ctx, *, full=False):
        return sales_report(ctx)


class StockReportView(ReportView):
    def build(self, ctx, *, full=False):
        return stock_report(ctx, full=full)


class PurchasingReportView(ReportView):
    def build(self, ctx, *, full=False):
        return purchasing_report(ctx)


class ReturnsReportView(ReportView):
    def build(self, ctx, *, full=False):
        return returns_report(ctx, full=full)


class ExpensesReportView(ReportView):
    required_permission = "expense.view"

    def build(self, ctx, *, full=False):
        return expenses_report(ctx)


# ---- exports -------------------------------------------------------------------------------


class SalesExportView(ExportMixin, SalesReportView):
    slug, table = "sales", staticmethod(exports.sales_table)


class StockExportView(ExportMixin, StockReportView):
    slug, table = "stock", staticmethod(exports.stock_table)


class PurchasingExportView(ExportMixin, PurchasingReportView):
    slug, table = "purchasing", staticmethod(exports.purchasing_table)


class ReturnsExportView(ExportMixin, ReturnsReportView):
    slug, table = "returns", staticmethod(exports.returns_table)


class ExpensesExportView(ExportMixin, ExpensesReportView):
    slug, table = "expenses", staticmethod(exports.expenses_table)


# ---- dashboard -----------------------------------------------------------------------------


class DashboardView(BusinessAPIView):
    """Only the sections the caller's role may see, for the caller's own locations."""

    required_permission = "dashboard.view"

    def get(self, request, business_id):
        return Response(summary.dashboard(request))
