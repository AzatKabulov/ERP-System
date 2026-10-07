import 'package:flutter/foundation.dart';

import '../../core/money/decimal_math.dart';

/// "S-000012": how a sale is named on screen and on documents.
String saleNumber(int number) => 'S-${number.toString().padLeft(6, '0')}';

const paymentMethods = ['cash', 'card', 'transfer'];

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
class SalePaymentRecord {
  const SalePaymentRecord({required this.method, required this.amountMinor});
  final String method;
  final int amountMinor;

  factory SalePaymentRecord.fromJson(Map<String, dynamic> json) =>
      SalePaymentRecord(
        method: json['method'] as String,
        amountMinor: parseServerDecimal(json['amount'] as String, 2) ?? 0,
      );
}

@immutable
class SaleLineRecord {
  const SaleLineRecord({
    required this.productId,
    required this.sku,
    required this.name,
    required this.unitSymbol,
    required this.unitDecimals,
    required this.quantityMilli,
    required this.unitPriceMinor,
    required this.grossMinor,
    required this.discountMinor,
    required this.lineTotalMinor,
    required this.warrantyMonths,
    required this.warrantyTerms,
    this.costTotalMinor,
  });
  final String productId;
  final String sku;
  final String name;
  final String unitSymbol;
  final int unitDecimals;
  final int quantityMilli;
  final int unitPriceMinor;
  final int grossMinor;
  final int discountMinor;
  final int lineTotalMinor;
  final int warrantyMonths;
  final String warrantyTerms;

  /// Only for roles that may see costs.
  final int? costTotalMinor;

  factory SaleLineRecord.fromJson(Map<String, dynamic> json) => SaleLineRecord(
    productId: json['product'] as String,
    sku: json['sku'] as String,
    name: json['name'] as String,
    unitSymbol: json['unit_symbol'] as String,
    unitDecimals: json['unit_decimals'] as int,
    quantityMilli: parseServerDecimal(json['quantity'] as String, 3) ?? 0,
    unitPriceMinor: parseServerDecimal(json['unit_price'] as String, 2) ?? 0,
    grossMinor: parseServerDecimal(json['gross'] as String, 2) ?? 0,
    discountMinor: parseServerDecimal(json['discount'] as String, 2) ?? 0,
    lineTotalMinor: parseServerDecimal(json['line_total'] as String, 2) ?? 0,
    warrantyMonths: (json['warranty_months'] as int?) ?? 0,
    warrantyTerms: (json['warranty_terms'] as String?) ?? '',
    costTotalMinor: parseServerDecimal(json['cost_total'] as String?, 2),
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
    required this.discountMinor,
    required this.lineCount,
    required this.methods,
  });
  final String id;
  final int number;
  final DateTime createdAt;
  final String locationName;
  final String cashierName;
  final String customerName;
  final int totalMinor;
  final int discountMinor;
  final int lineCount;
  final List<String> methods;

  factory SaleSummary.fromJson(Map<String, dynamic> json) => SaleSummary(
    id: json['id'] as String,
    number: json['number'] as int,
    createdAt: DateTime.parse(json['created_at'] as String),
    locationName: (json['location'] as Map)['name'] as String,
    cashierName: (json['cashier'] as Map)['name'] as String,
    customerName: (json['customer_name'] as String?) ?? '',
    totalMinor: parseServerDecimal(json['total'] as String, 2) ?? 0,
    discountMinor: parseServerDecimal(json['discount_total'] as String, 2) ?? 0,
    lineCount: json['line_count'] as int,
    methods: [for (final m in json['methods'] as List) m as String],
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
    required this.discountMinor,
    required this.paidMinor,
    required this.changeMinor,
    required this.usdRate,
    required this.note,
    required this.lines,
    required this.payments,
    this.costTotalMinor,
    this.profitMinor,
  });
  final String id;
  final int number;
  final DateTime createdAt;
  final String locationName;
  final String cashierName;
  final String customerName;
  final int totalMinor;
  final int discountMinor;
  final int paidMinor;
  final int changeMinor;

  /// TMT per USD at the moment of sale, when any line was priced in USD.
  final String? usdRate;
  final String note;
  final List<SaleLineRecord> lines;
  final List<SalePaymentRecord> payments;
  final int? costTotalMinor;
  final int? profitMinor;

  factory SaleDetail.fromJson(Map<String, dynamic> json) => SaleDetail(
    id: json['id'] as String,
    number: json['number'] as int,
    createdAt: DateTime.parse(json['created_at'] as String),
    locationName: (json['location'] as Map)['name'] as String,
    cashierName: (json['cashier'] as Map)['name'] as String,
    customerName: (json['customer_name'] as String?) ?? '',
    totalMinor: parseServerDecimal(json['total'] as String, 2) ?? 0,
    discountMinor: parseServerDecimal(json['discount_total'] as String, 2) ?? 0,
    paidMinor: parseServerDecimal(json['paid'] as String, 2) ?? 0,
    changeMinor: parseServerDecimal(json['change_given'] as String, 2) ?? 0,
    usdRate: json['usd_rate'] as String?,
    note: (json['note'] as String?) ?? '',
    lines: [
      for (final l in json['lines'] as List)
        SaleLineRecord.fromJson((l as Map).cast<String, dynamic>()),
    ],
    payments: [
      for (final p in json['payments'] as List)
        SalePaymentRecord.fromJson((p as Map).cast<String, dynamic>()),
    ],
    costTotalMinor: parseServerDecimal(json['cost_total'] as String?, 2),
    profitMinor: parseServerDecimal(json['profit'] as String?, 2),
  );
}
