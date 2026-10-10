import 'package:flutter/foundation.dart';

import '../../core/money/decimal_math.dart';

/// The periods the report page offers. Dates are calendar days ("2026-10-07"); the server reads
/// them in the business's own time zone.
enum ReportPeriod { today, week, month, lastMonth }

String reportDay(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// What a report is about: the days it covers and, optionally, one location.
@immutable
class ReportQuery {
  const ReportQuery({required this.from, required this.to, this.locationId});

  final String from;
  final String to;
  final String? locationId;

  factory ReportQuery.forPeriod(
    ReportPeriod period, {
    String? locationId,
    DateTime? now,
  }) {
    final today = now ?? DateTime.now();
    switch (period) {
      case ReportPeriod.today:
        return ReportQuery(
          from: reportDay(today),
          to: reportDay(today),
          locationId: locationId,
        );
      case ReportPeriod.week:
        return ReportQuery(
          from: reportDay(DateTime(today.year, today.month, today.day - 6)),
          to: reportDay(today),
          locationId: locationId,
        );
      case ReportPeriod.month:
        return ReportQuery(
          from: reportDay(DateTime(today.year, today.month, 1)),
          to: reportDay(today),
          locationId: locationId,
        );
      case ReportPeriod.lastMonth:
        return ReportQuery(
          from: reportDay(DateTime(today.year, today.month - 1, 1)),
          to: reportDay(DateTime(today.year, today.month, 0)),
          locationId: locationId,
        );
    }
  }

  Map<String, String> toQuery() => {
    'date_from': from,
    'date_to': to,
    'location': ?locationId,
  };

  @override
  bool operator ==(Object other) =>
      other is ReportQuery &&
      other.from == from &&
      other.to == to &&
      other.locationId == locationId;

  @override
  int get hashCode => Object.hash(from, to, locationId);
}

int _money(Object? v) => parseSignedServerDecimal(v as String?, 2) ?? 0;
int? _moneyOrNull(Object? v) =>
    v == null ? null : parseSignedServerDecimal(v as String, 2);
int _qty(Object? v) => parseSignedServerDecimal(v as String?, 3) ?? 0;
int _int(Object? v) => (v as num?)?.toInt() ?? 0;
Map<String, dynamic> _map(Object? v) => (v as Map).cast<String, dynamic>();
List<Map<String, dynamic>> _list(Object? v) => [
  for (final e in (v as List?) ?? const []) _map(e),
];

/// Totals for the owner review. A figure the person's role may not see arrives as null: costs,
/// profit and the result are removed by the server, never merely hidden by the app.
@immutable
class ReportSummary {
  const ReportSummary({
    required this.revenue,
    required this.refunds,
    required this.netSales,
    required this.salesCount,
    required this.returnsCount,
    required this.lowStockCount,
    required this.openOrdersCount,
    this.costOfGoods,
    this.grossProfit,
    this.expenses,
    this.result,
    this.inventoryValue,
  });

  final int revenue;
  final int refunds;
  final int netSales;
  final int salesCount;
  final int returnsCount;
  final int lowStockCount;
  final int openOrdersCount;
  final int? costOfGoods;
  final int? grossProfit;
  final int? expenses;
  final int? result;
  final int? inventoryValue;

  factory ReportSummary.fromJson(Map<String, dynamic> j) => ReportSummary(
    revenue: _money(j['revenue']),
    refunds: _money(j['refunds']),
    netSales: _money(j['net_sales']),
    salesCount: _int(j['sales_count']),
    returnsCount: _int(j['returns_count']),
    lowStockCount: _int(j['low_stock_count']),
    openOrdersCount: _int(j['open_orders_count']),
    costOfGoods: _moneyOrNull(j['cost_of_goods']),
    grossProfit: _moneyOrNull(j['gross_profit']),
    expenses: _moneyOrNull(j['expenses']),
    result: _moneyOrNull(j['result']),
    inventoryValue: _moneyOrNull(j['inventory_value']),
  );
}

@immutable
class PaymentRow {
  const PaymentRow(this.method, this.count, this.total);
  final String method; // cash | card
  final int count;
  final int total;
}

@immutable
class DayRow {
  const DayRow(this.date, this.count, this.revenue, this.refunds);
  final String date;
  final int count;
  final int revenue;
  final int refunds;
}

@immutable
class TopProduct {
  const TopProduct({
    required this.sku,
    required this.name,
    required this.unitSymbol,
    required this.unitDecimals,
    required this.quantityMilli,
    required this.revenue,
  });
  final String sku;
  final String name;
  final String unitSymbol;
  final int unitDecimals;
  final int quantityMilli;
  final int revenue;
}

@immutable
class SalesReport {
  const SalesReport({
    required this.salesCount,
    required this.revenue,
    required this.refunds,
    required this.returnsCount,
    required this.netSales,
    required this.byPayment,
    required this.byDay,
    required this.topProducts,
    this.costOfGoods,
    this.grossProfit,
  });

  final int salesCount;
  final int revenue;
  final int refunds;
  final int returnsCount;
  final int netSales;
  final int? costOfGoods;
  final int? grossProfit;
  final List<PaymentRow> byPayment;
  final List<DayRow> byDay;
  final List<TopProduct> topProducts;

  factory SalesReport.fromJson(Map<String, dynamic> j) => SalesReport(
    salesCount: _int(j['sales_count']),
    revenue: _money(j['revenue']),
    refunds: _money(j['refunds']),
    returnsCount: _int(j['returns_count']),
    netSales: _money(j['net_sales']),
    costOfGoods: _moneyOrNull(j['cost_of_goods']),
    grossProfit: _moneyOrNull(j['gross_profit']),
    byPayment: [
      for (final r in _list(j['by_payment']))
        PaymentRow(r['method'] as String, _int(r['count']), _money(r['total'])),
    ],
    byDay: [
      for (final r in _list(j['by_day']))
        DayRow(
          r['date'] as String,
          _int(r['count']),
          _money(r['revenue']),
          _money(r['refunds']),
        ),
    ],
    topProducts: [
      for (final r in _list(j['top_products']))
        TopProduct(
          sku: (r['sku'] as String?) ?? '',
          name: (r['name'] as String?) ?? '',
          unitSymbol: (r['unit_symbol'] as String?) ?? '',
          unitDecimals: _int(r['unit_decimals']),
          quantityMilli: _qty(r['quantity']),
          revenue: _money(r['revenue']),
        ),
    ],
  );
}

@immutable
class LowStockRow {
  const LowStockRow({
    required this.sku,
    required this.name,
    required this.unitSymbol,
    required this.unitDecimals,
    required this.locationName,
    required this.onHandMilli,
    required this.minimumMilli,
    required this.targetMilli,
  });
  final String sku;
  final String name;
  final String unitSymbol;
  final int unitDecimals;
  final String locationName;
  final int onHandMilli;
  final int minimumMilli;
  final int targetMilli;
}

@immutable
class ValueByLocation {
  const ValueByLocation(this.locationName, this.total, this.byCondition);
  final String locationName;
  final int total;
  final Map<String, int> byCondition;
}

@immutable
class MovementRow {
  const MovementRow(this.type, this.count, this.inMilli, this.outMilli);
  final String type;
  final int count;
  final int inMilli;
  final int outMilli;
}

@immutable
class StockReport {
  const StockReport({
    required this.lowStock,
    required this.lowStockCount,
    required this.movements,
    this.valueTotal,
    this.valueByLocation = const [],
  });

  final List<LowStockRow> lowStock;
  final int lowStockCount;
  final List<MovementRow> movements;

  /// Null for roles without cost access.
  final int? valueTotal;
  final List<ValueByLocation> valueByLocation;

  factory StockReport.fromJson(Map<String, dynamic> j) {
    final value = j['value'] == null ? null : _map(j['value']);
    return StockReport(
      lowStockCount: _int(j['low_stock_count']),
      lowStock: [
        for (final r in _list(j['low_stock']))
          LowStockRow(
            sku: (_map(r['product'])['sku'] as String?) ?? '',
            name: (_map(r['product'])['name'] as String?) ?? '',
            unitSymbol: (_map(r['product'])['unit_symbol'] as String?) ?? '',
            unitDecimals: _int(_map(r['product'])['unit_decimals']),
            locationName: (_map(r['location'])['name'] as String?) ?? '',
            onHandMilli: _qty(r['on_hand']),
            minimumMilli: _qty(r['minimum']),
            targetMilli: _qty(r['target']),
          ),
      ],
      movements: [
        for (final r in _list(j['movements']))
          MovementRow(
            r['type'] as String,
            _int(r['count']),
            _qty(r['quantity_in']),
            _qty(r['quantity_out']),
          ),
      ],
      valueTotal: value == null ? null : _money(value['total']),
      valueByLocation: value == null
          ? const []
          : [
              for (final r in _list(value['by_location']))
                ValueByLocation(
                  (_map(r['location'])['name'] as String?) ?? '',
                  _money(r['total']),
                  {
                    for (final e in _map(r['by_condition']).entries)
                      e.key: _money(e.value),
                  },
                ),
            ],
    );
  }
}

@immutable
class SupplierRow {
  const SupplierRow(this.name, this.orders, this.receivedValue);
  final String name;
  final int orders;
  final int? receivedValue;
}

@immutable
class PurchasingReport {
  const PurchasingReport({
    required this.ordersCount,
    required this.deliveriesCount,
    required this.byStatus,
    required this.bySupplier,
    required this.supplierReturnsCount,
    this.orderedTotal,
    this.receivedValue,
    this.supplierReturnsCredit,
  });

  final int ordersCount;
  final int deliveriesCount;
  final List<(String status, int count)> byStatus;
  final List<SupplierRow> bySupplier;
  final int supplierReturnsCount;
  final int? orderedTotal;
  final int? receivedValue;
  final int? supplierReturnsCredit;

  factory PurchasingReport.fromJson(Map<String, dynamic> j) => PurchasingReport(
    ordersCount: _int(j['orders_count']),
    deliveriesCount: _int(j['deliveries_count']),
    orderedTotal: _moneyOrNull(j['ordered_total']),
    receivedValue: _moneyOrNull(j['received_value']),
    supplierReturnsCount: _int(j['supplier_returns_count']),
    supplierReturnsCredit: _moneyOrNull(j['supplier_returns_credit']),
    byStatus: [
      for (final r in _list(j['by_status']))
        (r['status'] as String, _int(r['count'])),
    ],
    bySupplier: [
      for (final r in _list(j['by_supplier']))
        SupplierRow(
          (_map(r['supplier'])['name'] as String?) ?? '',
          _int(r['orders']),
          _moneyOrNull(r['received_value']),
        ),
    ],
  );
}

@immutable
class ConditionRow {
  const ConditionRow(this.condition, this.quantityMilli, this.refund);
  final String condition;
  final int quantityMilli;
  final int refund;
}

@immutable
class ReasonRow {
  const ReasonRow(this.reason, this.count, this.refund);
  final String reason;
  final int count;
  final int refund;
}

@immutable
class ReturnsReport {
  const ReturnsReport({
    required this.returnsCount,
    required this.refundTotal,
    required this.byCondition,
    required this.byReason,
    required this.supplierReturnsCount,
    this.supplierReturnsCredit,
  });

  final int returnsCount;
  final int refundTotal;
  final List<ConditionRow> byCondition;
  final List<ReasonRow> byReason;
  final int supplierReturnsCount;
  final int? supplierReturnsCredit;

  factory ReturnsReport.fromJson(Map<String, dynamic> j) {
    final supplier = j['supplier_returns'] == null
        ? const <String, dynamic>{}
        : _map(j['supplier_returns']);
    return ReturnsReport(
      returnsCount: _int(j['returns_count']),
      refundTotal: _money(j['refund_total']),
      byCondition: [
        for (final r in _list(j['by_condition']))
          ConditionRow(
            r['condition'] as String,
            _qty(r['quantity']),
            _money(r['refund']),
          ),
      ],
      byReason: [
        for (final r in _list(j['by_reason']))
          ReasonRow(
            (r['reason'] as String?) ?? '',
            _int(r['count']),
            _money(r['refund']),
          ),
      ],
      supplierReturnsCount: _int(supplier['count']),
      supplierReturnsCredit: _moneyOrNull(supplier['credit']),
    );
  }
}

@immutable
class TotalRow {
  const TotalRow(this.name, this.total, this.count);
  final String name;
  final int total;
  final int count;
}

@immutable
class ExpensesReport {
  const ExpensesReport({
    required this.total,
    required this.count,
    required this.byCategory,
    required this.byLocation,
  });

  final int total;
  final int count;
  final List<TotalRow> byCategory;
  final List<TotalRow> byLocation;

  factory ExpensesReport.fromJson(Map<String, dynamic> j) => ExpensesReport(
    total: _money(j['total']),
    count: _int(j['count']),
    byCategory: [
      for (final r in _list(j['by_category']))
        TotalRow(
          (_map(r['category'])['name'] as String?) ?? '',
          _money(r['total']),
          _int(r['count']),
        ),
    ],
    byLocation: [
      for (final r in _list(j['by_location']))
        TotalRow(
          (_map(r['location'])['name'] as String?) ?? '',
          _money(r['total']),
          _int(r['count']),
        ),
    ],
  );
}

/// One line of the activity history: who did what to which record, and when.
@immutable
class AuditEntry {
  const AuditEntry({
    required this.id,
    required this.action,
    required this.objectType,
    required this.objectId,
    required this.actorName,
    required this.createdAt,
  });

  final String id;
  final String action; // "sale.completed"
  final String objectType;
  final String objectId;
  final String actorName; // empty when the system did it
  final DateTime createdAt;

  factory AuditEntry.fromJson(Map<String, dynamic> j) => AuditEntry(
    id: j['id'] as String,
    action: j['action'] as String,
    objectType: (j['object_type'] as String?) ?? '',
    objectId: (j['object_id'] as String?) ?? '',
    actorName: ((j['actor'] as Map?)?['name'] as String?) ?? '',
    createdAt: DateTime.parse(j['created_at'] as String),
  );
}

class AuditPage {
  const AuditPage(this.items, this.count);
  final List<AuditEntry> items;
  final int count;
}

/// The dashboard: every section is present only when the person's role may see it.
@immutable
class Dashboard {
  const Dashboard({
    this.salesTodayCount,
    this.salesTodayTotal,
    this.salesMonthCount,
    this.salesMonthTotal,
    this.grossProfitMonth,
    this.expensesMonth,
    this.inventoryValue,
    this.lowStockCount,
    this.reorderCount,
    this.openOrdersCount,
    this.openClaimsCount,
    this.recentActivity,
  });

  final int? salesTodayCount;
  final int? salesTodayTotal;
  final int? salesMonthCount;
  final int? salesMonthTotal;
  final int? grossProfitMonth;
  final int? expensesMonth;
  final int? inventoryValue;
  final int? lowStockCount;
  final int? reorderCount;
  final int? openOrdersCount;
  final int? openClaimsCount;
  final List<AuditEntry>? recentActivity;

  bool get hasAnything =>
      salesTodayTotal != null ||
      salesMonthTotal != null ||
      grossProfitMonth != null ||
      expensesMonth != null ||
      inventoryValue != null ||
      lowStockCount != null ||
      reorderCount != null ||
      openOrdersCount != null ||
      openClaimsCount != null ||
      recentActivity != null;

  factory Dashboard.fromJson(Map<String, dynamic> j) {
    final today = j['sales_today'] == null ? null : _map(j['sales_today']);
    final month = j['sales_month'] == null ? null : _map(j['sales_month']);
    return Dashboard(
      salesTodayCount: today == null ? null : _int(today['count']),
      salesTodayTotal: today == null ? null : _money(today['total']),
      salesMonthCount: month == null ? null : _int(month['count']),
      salesMonthTotal: month == null ? null : _money(month['total']),
      grossProfitMonth: _moneyOrNull(j['gross_profit_month']),
      expensesMonth: _moneyOrNull(j['expenses_month']),
      inventoryValue: _moneyOrNull(j['inventory_value']),
      lowStockCount: j['low_stock_count'] == null
          ? null
          : _int(j['low_stock_count']),
      reorderCount: j['reorder_count'] == null
          ? null
          : _int(j['reorder_count']),
      openOrdersCount: j['open_orders_count'] == null
          ? null
          : _int(j['open_orders_count']),
      openClaimsCount: j['open_claims_count'] == null
          ? null
          : _int(j['open_claims_count']),
      recentActivity: j['recent_activity'] == null
          ? null
          : [
              for (final e in _list(j['recent_activity']))
                AuditEntry.fromJson(e),
            ],
    );
  }
}
