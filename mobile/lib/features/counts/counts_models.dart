import 'package:flutter/foundation.dart';

import '../../core/money/decimal_math.dart';
import '../../l10n/app_localizations.dart';
import '../inventory/inventory_models.dart';

/// "C-0003": how a count is named on screen.
String countNumber(int number) => 'C-${number.toString().padLeft(4, '0')}';

const countStatuses = ['open', 'submitted', 'approved', 'cancelled'];

String countStatusLabel(AppLocalizations l, String status) => switch (status) {
  'open' => l.countStatusOpen,
  'submitted' => l.countStatusSubmitted,
  'approved' => l.countStatusApproved,
  'cancelled' => l.countStatusCancelled,
  _ => status,
};

@immutable
class CountSummary {
  const CountSummary({
    required this.id,
    required this.number,
    required this.status,
    required this.scope,
    required this.locationName,
    required this.createdAt,
    required this.lineCount,
    required this.countedCount,
    required this.differenceCount,
  });
  final String id;
  final int number;
  final String status;
  final String scope;
  final String locationName;
  final DateTime createdAt;
  final int lineCount;
  final int countedCount;
  final int differenceCount;

  factory CountSummary.fromJson(Map<String, dynamic> json) => CountSummary(
    id: json['id'] as String,
    number: json['number'] as int,
    status: json['status'] as String,
    scope: json['scope'] as String,
    locationName: (json['location'] as Map)['name'] as String,
    createdAt: DateTime.parse(json['created_at'] as String),
    lineCount: json['line_count'] as int,
    countedCount: json['counted_count'] as int,
    differenceCount: json['difference_count'] as int,
  );
}

class CountPage {
  const CountPage(this.items, this.count);
  final List<CountSummary> items;
  final int count;
}

@immutable
class CountLineRecord {
  const CountLineRecord({
    required this.id,
    required this.product,
    required this.baselineMilli,
    required this.countedMilli,
    required this.varianceMilli,
    required this.movedSinceStart,
    required this.note,
  });
  final String id;
  final ProductRef product;

  /// What the system showed when the count started.
  final int baselineMilli;
  final int? countedMilli;

  /// counted - baseline (can be negative); null while nothing is counted.
  final int? varianceMilli;

  /// Sellable stock of this product changed after the count began.
  final bool movedSinceStart;
  final String note;

  factory CountLineRecord.fromJson(Map<String, dynamic> json) =>
      CountLineRecord(
        id: json['id'] as String,
        product: ProductRef.fromJson(
          (json['product'] as Map).cast<String, dynamic>(),
        ),
        baselineMilli:
            parseServerDecimal(json['baseline_quantity'] as String, 3) ?? 0,
        countedMilli: parseServerDecimal(
          json['counted_quantity'] as String?,
          3,
        ),
        varianceMilli: parseSignedServerDecimal(json['variance'] as String?, 3),
        movedSinceStart: (json['moved_since_start'] as bool?) ?? false,
        note: (json['note'] as String?) ?? '',
      );
}

@immutable
class StockCountDoc {
  const StockCountDoc({
    required this.id,
    required this.number,
    required this.status,
    required this.scope,
    required this.locationId,
    required this.locationName,
    required this.note,
    required this.createdBy,
    required this.createdAt,
    required this.decisionReason,
    required this.lines,
  });
  final String id;
  final int number;
  final String status;
  final String scope;
  final String locationId;
  final String locationName;
  final String note;
  final String createdBy;
  final DateTime createdAt;
  final String decisionReason;
  final List<CountLineRecord> lines;

  bool get isOpen => status == 'open';
  bool get isSubmitted => status == 'submitted';
  int get countedCount => lines.where((l) => l.countedMilli != null).length;
  int get differenceCount =>
      lines.where((l) => (l.varianceMilli ?? 0) != 0).length;

  factory StockCountDoc.fromJson(Map<String, dynamic> json) => StockCountDoc(
    id: json['id'] as String,
    number: json['number'] as int,
    status: json['status'] as String,
    scope: json['scope'] as String,
    locationId: (json['location'] as Map)['id'] as String,
    locationName: (json['location'] as Map)['name'] as String,
    note: (json['note'] as String?) ?? '',
    createdBy: ((json['created_by'] as Map?)?['name'] as String?) ?? '',
    createdAt: DateTime.parse(json['created_at'] as String),
    decisionReason: (json['decision_reason'] as String?) ?? '',
    lines: [
      for (final l in json['lines'] as List)
        CountLineRecord.fromJson((l as Map).cast<String, dynamic>()),
    ],
  );
}
