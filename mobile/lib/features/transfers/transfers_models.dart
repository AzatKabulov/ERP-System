import 'package:flutter/foundation.dart';

import '../../core/money/decimal_math.dart';
import '../../l10n/app_localizations.dart';
import '../inventory/inventory_models.dart';

/// "T-0012": how a transfer is named on screen.
String transferNumber(int number) => 'T-${number.toString().padLeft(4, '0')}';

const transferStatuses = [
  'dispatched',
  'received',
  'partially_received',
  'cancelled',
];

String transferStatusLabel(AppLocalizations l, String status) =>
    switch (status) {
      'dispatched' => l.transferStatusInTransit,
      'received' => l.transferStatusReceived,
      'partially_received' => l.transferStatusPartial,
      'cancelled' => l.transferStatusCancelled,
      _ => status,
    };

@immutable
class TransferSummary {
  const TransferSummary({
    required this.id,
    required this.number,
    required this.status,
    required this.fromName,
    required this.toName,
    required this.createdAt,
    required this.lineCount,
  });
  final String id;
  final int number;
  final String status;
  final String fromName;
  final String toName;
  final DateTime createdAt;
  final int lineCount;

  factory TransferSummary.fromJson(Map<String, dynamic> json) =>
      TransferSummary(
        id: json['id'] as String,
        number: json['number'] as int,
        status: json['status'] as String,
        fromName: (json['from_location'] as Map)['name'] as String,
        toName: (json['to_location'] as Map)['name'] as String,
        createdAt: DateTime.parse(json['created_at'] as String),
        lineCount: json['line_count'] as int,
      );
}

class TransferPage {
  const TransferPage(this.items, this.count);
  final List<TransferSummary> items;
  final int count;
}

@immutable
class TransferLineRecord {
  const TransferLineRecord({
    required this.id,
    required this.product,
    required this.quantityMilli,
    required this.receivedMilli,
  });
  final String id;
  final ProductRef product;
  final int quantityMilli;

  /// Null until the transfer has been received.
  final int? receivedMilli;

  factory TransferLineRecord.fromJson(Map<String, dynamic> json) =>
      TransferLineRecord(
        id: json['id'] as String,
        product: ProductRef.fromJson(
          (json['product'] as Map).cast<String, dynamic>(),
        ),
        quantityMilli: parseServerDecimal(json['quantity'] as String, 3) ?? 0,
        receivedMilli: parseServerDecimal(
          json['received_quantity'] as String?,
          3,
        ),
      );
}

@immutable
class Transfer {
  const Transfer({
    required this.id,
    required this.number,
    required this.status,
    required this.fromId,
    required this.fromName,
    required this.toId,
    required this.toName,
    required this.note,
    required this.createdBy,
    required this.createdAt,
    required this.receivedBy,
    required this.discrepancyReason,
    required this.cancelReason,
    required this.lines,
  });
  final String id;
  final int number;
  final String status;
  final String fromId;
  final String fromName;
  final String toId;
  final String toName;
  final String note;
  final String createdBy;
  final DateTime createdAt;
  final String? receivedBy;
  final String discrepancyReason;
  final String cancelReason;
  final List<TransferLineRecord> lines;

  bool get inTransit => status == 'dispatched';

  factory Transfer.fromJson(Map<String, dynamic> json) => Transfer(
    id: json['id'] as String,
    number: json['number'] as int,
    status: json['status'] as String,
    fromId: (json['from_location'] as Map)['id'] as String,
    fromName: (json['from_location'] as Map)['name'] as String,
    toId: (json['to_location'] as Map)['id'] as String,
    toName: (json['to_location'] as Map)['name'] as String,
    note: (json['note'] as String?) ?? '',
    createdBy: ((json['created_by'] as Map?)?['name'] as String?) ?? '',
    createdAt: DateTime.parse(json['created_at'] as String),
    receivedBy: (json['received_by'] as Map?)?['name'] as String?,
    discrepancyReason: (json['discrepancy_reason'] as String?) ?? '',
    cancelReason: (json['cancel_reason'] as String?) ?? '',
    lines: [
      for (final l in json['lines'] as List)
        TransferLineRecord.fromJson((l as Map).cast<String, dynamic>()),
    ],
  );
}
