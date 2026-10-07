import 'package:flutter/foundation.dart';

import '../../core/money/decimal_math.dart';

/// "S-000012": how a sale is named on screen and on documents.
String saleNumber(int number) => 'S-${number.toString().padLeft(6, '0')}';

/// How the customer paid. Only the fact is recorded, never amounts or change.
const paymentMethods = ['cash', 'card'];

@immutable
class Customer {
  const Customer({
    required this.id,
    required this.name,
    required this.phone,
    required this.isActive,
  });
  final String id;
  final String name;
  final String phone;
  final bool isActive;

  factory Customer.fromJson(Map<String, dynamic> json) => Customer(
    id: json['id'] as String,
    name: json['name'] as String,
    phone: (json['phone'] as String?) ?? '',
    isActive: (json['is_active'] as bool?) ?? true,
  );
}

@immutable
class SaleLineRecord {
  const SaleLineRecord({
    required this.id,
    required this.productId,
    required this.sku,
    required this.name,
    required this.unitSymbol,
    required this.unitDecimals,
    required this.quantityMilli,
    required this.unitPriceMinor,
    required this.lineTotalMinor,
    required this.warrantyMonths,
    required this.warrantyTerms,
    this.returnedMilli = 0,
    this.returnableMilli = 0,
    this.refundedMinor = 0,
    this.returnDays,
    this.returnUntil,
    this.costTotalMinor,
  });
  final String id;
  final String productId;
  final String sku;
  final String name;
  final String unitSymbol;
  final int unitDecimals;
  final int quantityMilli;
  final int unitPriceMinor;
  final int lineTotalMinor;
  final int warrantyMonths;
  final String warrantyTerms;

  /// How much of this line came back already, how much still can, and what was refunded.
  final int returnedMilli;
  final int returnableMilli;
  final int refundedMinor;

  /// Days after the sale the customer may return it: null = no limit, 0 = not returnable.
  final int? returnDays;

  /// The last day to return it (a date, "2026-10-14"), null when there is no limit.
  final String? returnUntil;

  /// Only for roles that may see costs.
  final int? costTotalMinor;

  factory SaleLineRecord.fromJson(Map<String, dynamic> json) => SaleLineRecord(
    id: (json['id'] as String?) ?? '',
    productId: json['product'] as String,
    sku: json['sku'] as String,
    name: json['name'] as String,
    unitSymbol: json['unit_symbol'] as String,
    unitDecimals: json['unit_decimals'] as int,
    quantityMilli: parseServerDecimal(json['quantity'] as String, 3) ?? 0,
    unitPriceMinor: parseServerDecimal(json['unit_price'] as String, 2) ?? 0,
    lineTotalMinor: parseServerDecimal(json['line_total'] as String, 2) ?? 0,
    warrantyMonths: (json['warranty_months'] as int?) ?? 0,
    warrantyTerms: (json['warranty_terms'] as String?) ?? '',
    returnedMilli:
        parseServerDecimal(json['returned_quantity'] as String?, 3) ?? 0,
    returnableMilli:
        parseServerDecimal(json['returnable_quantity'] as String?, 3) ?? 0,
    refundedMinor:
        parseServerDecimal(json['refunded_total'] as String?, 2) ?? 0,
    returnDays: json['return_days'] as int?,
    returnUntil: json['return_until'] as String?,
    costTotalMinor: parseServerDecimal(json['cost_total'] as String?, 2),
  );
}

/// A return made against a sale, as the sale lists it.
@immutable
class SaleReturnRef {
  const SaleReturnRef({
    required this.id,
    required this.number,
    required this.refundMinor,
    required this.createdAt,
  });
  final String id;
  final int number;
  final int refundMinor;
  final DateTime createdAt;

  factory SaleReturnRef.fromJson(Map<String, dynamic> json) => SaleReturnRef(
    id: json['id'] as String,
    number: json['number'] as int,
    refundMinor: parseServerDecimal(json['refund_total'] as String?, 2) ?? 0,
    createdAt: DateTime.parse(json['created_at'] as String),
  );
}

@immutable
class SaleSummary {
  const SaleSummary({
    required this.id,
    required this.number,
    required this.createdAt,
    required this.locationName,
    required this.cashierName,
    required this.customerName,
    required this.totalMinor,
    required this.lineCount,
    required this.paymentMethod,
  });
  final String id;
  final int number;
  final DateTime createdAt;
  final String locationName;
  final String cashierName;
  final String customerName;
  final int totalMinor;
  final int lineCount;
  final String paymentMethod;

  factory SaleSummary.fromJson(Map<String, dynamic> json) => SaleSummary(
    id: json['id'] as String,
    number: json['number'] as int,
    createdAt: DateTime.parse(json['created_at'] as String),
    locationName: (json['location'] as Map)['name'] as String,
    cashierName: (json['cashier'] as Map)['name'] as String,
    customerName: (json['customer_name'] as String?) ?? '',
    totalMinor: parseServerDecimal(json['total'] as String, 2) ?? 0,
    lineCount: json['line_count'] as int,
    paymentMethod: json['payment_method'] as String,
  );
}

class SalePage {
  const SalePage(this.items, this.count);
  final List<SaleSummary> items;
  final int count;
}

@immutable
class SaleDetail {
  const SaleDetail({
    required this.id,
    required this.number,
    required this.createdAt,
    required this.locationName,
    required this.cashierName,
    required this.customerName,
    required this.totalMinor,
    required this.paymentMethod,
    required this.note,
    required this.lines,
    this.locationId = '',
    this.returns = const [],
    this.costTotalMinor,
    this.profitMinor,
  });
  final String id;
  final int number;
  final DateTime createdAt;
  final String locationId;
  final String locationName;
  final String cashierName;
  final String customerName;
  final int totalMinor;
  final String paymentMethod;
  final String note;
  final List<SaleLineRecord> lines;
  final List<SaleReturnRef> returns;
  final int? costTotalMinor;
  final int? profitMinor;

  /// Whether anything on this sale can still be brought back.
  bool get hasReturnable => lines.any((l) => l.returnableMilli > 0);

  factory SaleDetail.fromJson(Map<String, dynamic> json) => SaleDetail(
    id: json['id'] as String,
    number: json['number'] as int,
    createdAt: DateTime.parse(json['created_at'] as String),
    locationId: (json['location'] as Map)['id'] as String,
    locationName: (json['location'] as Map)['name'] as String,
    cashierName: (json['cashier'] as Map)['name'] as String,
    customerName: (json['customer_name'] as String?) ?? '',
    totalMinor: parseServerDecimal(json['total'] as String, 2) ?? 0,
    paymentMethod: json['payment_method'] as String,
    note: (json['note'] as String?) ?? '',
    lines: [
      for (final l in json['lines'] as List)
        SaleLineRecord.fromJson((l as Map).cast<String, dynamic>()),
    ],
    returns: [
      for (final r in (json['returns'] as List?) ?? const [])
        SaleReturnRef.fromJson((r as Map).cast<String, dynamic>()),
    ],
    costTotalMinor: parseServerDecimal(json['cost_total'] as String?, 2),
    profitMinor: parseSignedServerDecimal(json['profit'] as String?, 2),
  );
}
