import 'package:flutter/foundation.dart';

import '../../core/money/decimal_math.dart';
import '../../l10n/app_localizations.dart';

/// "R-0012": how a customer return is named on screen.
String returnNumber(int number) => 'R-${number.toString().padLeft(4, '0')}';

/// Where goods go when a customer brings them back.
const returnConditions = ['sellable', 'damaged', 'inspection'];

String returnConditionLabel(AppLocalizations l, String condition) =>
    switch (condition) {
      'sellable' => l.conditionSellable,
      'damaged' => l.conditionDamaged,
      'inspection' => l.conditionInspection,
      _ => condition,
    };

/// What is refunded for [quantityMilli] of a sale line. The same rule as the server's: the
/// price charged times the quantity, rounded half up to a cent; bringing back everything that
/// is left refunds exactly what is left of the line (so the refunds always add up to the
/// line's total and no cent goes missing).
int refundMinor({
  required int quantityMilli,
  required int returnableMilli,
  required int unitPriceMinor,
  required int lineTotalMinor,
  required int refundedMinor,
}) {
  final left = lineTotalMinor - refundedMinor;
  final value = quantityMilli == returnableMilli
      ? left
      : (quantityMilli * unitPriceMinor + 500) ~/ 1000;
  if (value < 0) return 0;
  return value > left ? left : value;
}

@immutable
class ReturnLineRecord {
  const ReturnLineRecord({
    required this.id,
    required this.saleLineId,
    required this.name,
    required this.sku,
    required this.unitSymbol,
    required this.unitDecimals,
    required this.quantityMilli,
    required this.condition,
    required this.refundMinor,
    required this.awaitingMilli,
  });
  final String id;
  final String saleLineId;
  final String name;
  final String sku;
  final String unitSymbol;
  final int unitDecimals;
  final int quantityMilli;
  final String condition;
  final int refundMinor;

  /// Goods still waiting for the decision "sellable or damaged".
  final int awaitingMilli;

  factory ReturnLineRecord.fromJson(Map<String, dynamic> json) =>
      ReturnLineRecord(
        id: json['id'] as String,
        saleLineId: json['sale_line'] as String,
        name: json['name'] as String,
        sku: json['sku'] as String,
        unitSymbol: json['unit_symbol'] as String,
        unitDecimals: json['unit_decimals'] as int,
        quantityMilli: parseServerDecimal(json['quantity'] as String, 3) ?? 0,
        condition: json['condition'] as String,
        refundMinor:
            parseServerDecimal(json['refund_amount'] as String, 2) ?? 0,
        awaitingMilli:
            parseServerDecimal(json['awaiting_inspection'] as String?, 3) ?? 0,
      );
}

@immutable
class ReturnSummary {
  const ReturnSummary({
    required this.id,
    required this.number,
    required this.createdAt,
    required this.saleId,
    required this.saleNumber,
    required this.locationName,
    required this.reason,
    required this.refundMinor,
    required this.awaitingInspection,
  });
  final String id;
  final int number;
  final DateTime createdAt;
  final String saleId;
  final int saleNumber;
  final String locationName;
  final String reason;
  final int refundMinor;
  final bool awaitingInspection;

  factory ReturnSummary.fromJson(Map<String, dynamic> json) => ReturnSummary(
    id: json['id'] as String,
    number: json['number'] as int,
    createdAt: DateTime.parse(json['created_at'] as String),
    saleId: (json['sale'] as Map)['id'] as String,
    saleNumber: (json['sale'] as Map)['number'] as int,
    locationName: (json['location'] as Map)['name'] as String,
    reason: (json['reason'] as String?) ?? '',
    refundMinor: parseServerDecimal(json['refund_total'] as String, 2) ?? 0,
    awaitingInspection: (json['awaiting_inspection'] as bool?) ?? false,
  );
}

class ReturnPage {
  const ReturnPage(this.items, this.count);
  final List<ReturnSummary> items;
  final int count;
}

@immutable
class SaleReturnDoc {
  const SaleReturnDoc({
    required this.id,
    required this.number,
    required this.createdAt,
    required this.saleId,
    required this.saleNumber,
    required this.locationId,
    required this.locationName,
    required this.createdBy,
    required this.reason,
    required this.note,
    required this.refundMinor,
    required this.paymentMethod,
    required this.lines,
  });
  final String id;
  final int number;
  final DateTime createdAt;
  final String saleId;
  final int saleNumber;
  final String locationId;
  final String locationName;
  final String createdBy;
  final String reason;
  final String note;
  final int refundMinor;
  final String paymentMethod;
  final List<ReturnLineRecord> lines;

  bool get awaitingInspection => lines.any((l) => l.awaitingMilli > 0);

  factory SaleReturnDoc.fromJson(Map<String, dynamic> json) => SaleReturnDoc(
    id: json['id'] as String,
    number: json['number'] as int,
    createdAt: DateTime.parse(json['created_at'] as String),
    saleId: (json['sale'] as Map)['id'] as String,
    saleNumber: (json['sale'] as Map)['number'] as int,
    locationId: (json['location'] as Map)['id'] as String,
    locationName: (json['location'] as Map)['name'] as String,
    createdBy: ((json['created_by'] as Map?)?['name'] as String?) ?? '',
    reason: (json['reason'] as String?) ?? '',
    note: (json['note'] as String?) ?? '',
    refundMinor: parseServerDecimal(json['refund_total'] as String, 2) ?? 0,
    paymentMethod: (json['payment_method'] as String?) ?? 'cash',
    lines: [
      for (final l in json['lines'] as List)
        ReturnLineRecord.fromJson((l as Map).cast<String, dynamic>()),
    ],
  );
}

int _pow10(int exponent) {
  var result = 1;
  for (var i = 0; i < exponent; i++) {
    result *= 10;
  }
  return result;
}

/// A typed quantity in thousandths, or null when it is empty, not positive, or has more
/// decimals than the unit allows ([decimals]; pieces are whole). Never rounds.
int? parseReturnQuantity(String text, int decimals) {
  final milli = parseScaled(text, 3);
  if (milli == null || milli <= 0) return null;
  if (milli % _pow10(3 - decimals.clamp(0, 3)) != 0) return null;
  return milli;
}
