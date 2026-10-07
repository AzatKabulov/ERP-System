from django.urls import path

from . import views

B = "businesses/<uuid:business_id>/"

urlpatterns = [
    path(
        f"{B}expense-categories/",
        views.CategoryListCreateView.as_view(),
        name="expense-category-list",
    ),
    path(
        f"{B}expense-categories/<uuid:category_id>/",
        views.CategoryDetailView.as_view(),
        name="expense-category-detail",
    ),
    path(f"{B}expenses/", views.ExpenseListCreateView.as_view(), name="expense-list"),
    path(f"{B}expenses/summary/", views.ExpenseSummaryView.as_view(), name="expense-summary"),
    path(
        f"{B}expenses/<uuid:expense_id>/", views.ExpenseDetailView.as_view(), name="expense-detail"
    ),
    path(
        f"{B}expenses/<uuid:expense_id>/void/",
        views.ExpenseVoidView.as_view(),
        name="expense-void",
    ),
]
