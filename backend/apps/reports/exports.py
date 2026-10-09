"""CSV tables for the report exports. Each function turns the finished JSON report (so the same
permissions and left-out cost keys apply) into `(columns, rows, text_columns)`: column names are
English snake_case, money has a decimal point, and `text_columns` are the cells a person typed
(names, reasons), which `csvio.table_csv` protects against spreadsheet formulas.

* sales      - one row per day with sales or returns
* stock      - one row per low-stock line, then the value rows (every location x condition), then
               one `value_total` row
* purchasing - one row per supplier
* returns    - one row per reason
* expenses   - one row per category
"""

from decimal import Decimal

from apps.inventory.models import Condition

from .scope import money


def sales_table(report: dict):
    columns = ["date", "sales_count", "revenue", "refunds", "net_sales"]
    rows = [
        [
            d["date"],
            d["count"],
            d["revenue"],
            d["refunds"],
            money(Decimal(d["revenue"]) - Decimal(d["refunds"])),
        ]
        for d in report["by_day"]
    ]
    return columns, rows, ()


def stock_table(report: dict):
    columns = [
        "section",
        "location",
        "sku",
        "product",
        "condition",
        "on_hand",
        "minimum",
        "target",
        "value",
    ]
    rows = [
        [
            "low_stock",
            line["location"]["name"],
            line["product"]["sku"],
            line["product"]["name"],
            "",
            line["on_hand"],
            line["minimum"],
            line["target"],
            "",
        ]
        for line in report["low_stock"]
    ]
    value = report.get("value")
    if value is not None:
        for place in value["by_location"]:
            for condition in Condition.values:
                rows.append(
                    [
                        "value",
                        place["location"]["name"],
                        "",
                        "",
                        condition,
                        "",
                        "",
                        "",
                        place["by_condition"][condition],
                    ]
                )
        rows.append(["value_total", "", "", "", "", "", "", "", value["total"]])
    return columns, rows, ("location", "sku", "product")


def purchasing_table(report: dict):
    with_value = "received_value" in report  # present only for those who may see amounts
    columns = ["supplier", "orders", *(["received_value"] if with_value else [])]
    rows = [
        [row["supplier"]["name"], row["orders"], *([row["received_value"]] if with_value else [])]
        for row in report["by_supplier"]
    ]
    return columns, rows, ("supplier",)


def returns_table(report: dict):
    columns = ["reason", "returns_count", "refund"]
    rows = [[r["reason"], r["count"], r["refund"]] for r in report["by_reason"]]
    return columns, rows, ("reason",)


def expenses_table(report: dict):
    columns = ["category", "count", "total"]
    rows = [[r["category"]["name"], r["count"], r["total"]] for r in report["by_category"]]
    return columns, rows, ("category",)
