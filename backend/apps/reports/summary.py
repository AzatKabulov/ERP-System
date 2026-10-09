"""The period summary.

Summary (`report.view`): the headline figures of a period. Revenue, gross profit, expenses and
the result stay separate measures:

* result = gross_profit - expenses, shown only to someone who may see both. It is an OPERATING
  result, not an accounting profit: it knows nothing about tax, depreciation, owner's pay,
  stock bought but not yet sold, or anything that is not recorded as an expense.
* inventory_value, low_stock_count and open_orders_count are snapshots of now (restricted to the
  locations in scope), not figures of the period.
"""

from . import expenses as expense_figures
from . import sales as sales_figures
from . import stock
from .purchases import open_orders_count
from .scope import ReportContext, money, round_money


def summary_report(ctx: ReportContext) -> dict:
    scope, period, rights = ctx.scope, ctx.period, ctx.rights
    f = sales_figures.figures(scope, period, rights)
    out = {**ctx.head(), **f}
    if rights.expenses:
        spent = round_money(expense_figures.expenses_total(scope, period))
        out["expenses"] = str(spent)
        if rights.sales_cost:
            out["result"] = money(round_money(f["gross_profit"]) - spent)
    if rights.stock_cost:
        out["inventory_value"] = stock.inventory_value(scope)["total"]
    out["low_stock_count"] = stock.low_stock_count(scope)
    out["open_orders_count"] = open_orders_count(scope)
    return out
