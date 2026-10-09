from django.urls import path

from . import views

B = "businesses/<uuid:business_id>/"

urlpatterns = [
    path(f"{B}reports/summary/", views.SummaryReportView.as_view(), name="report-summary"),
    path(f"{B}reports/sales/", views.SalesReportView.as_view(), name="report-sales"),
    path(f"{B}reports/sales/export/", views.SalesExportView.as_view(), name="report-sales-export"),
    path(f"{B}reports/stock/", views.StockReportView.as_view(), name="report-stock"),
    path(f"{B}reports/stock/export/", views.StockExportView.as_view(), name="report-stock-export"),
    path(f"{B}reports/purchasing/", views.PurchasingReportView.as_view(), name="report-purchasing"),
    path(
        f"{B}reports/purchasing/export/",
        views.PurchasingExportView.as_view(),
        name="report-purchasing-export",
    ),
    path(f"{B}reports/returns/", views.ReturnsReportView.as_view(), name="report-returns"),
    path(
        f"{B}reports/returns/export/",
        views.ReturnsExportView.as_view(),
        name="report-returns-export",
    ),
    path(f"{B}reports/expenses/", views.ExpensesReportView.as_view(), name="report-expenses"),
    path(
        f"{B}reports/expenses/export/",
        views.ExpensesExportView.as_view(),
        name="report-expenses-export",
    ),
]
