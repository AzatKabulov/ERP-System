import 'package:flutter/foundation.dart';

import '../../core/money/decimal_math.dart';
import '../../l10n/app_localizations.dart';

/// "W-0003": how a warranty claim is named on screen.
String warrantyNumber(int number) => 'W-${number.toString().padLeft(4, '0')}';

const warrantyOutcomes = ['repair', 'replacement', 'refund', 'rejected'];

String warrantyOutcomeLabel(AppLocalizations l, String? outcome) =>
    switch (outcome) {
      'repair' => l.warrantyOutcomeRepair,
      'replacement' => l.warrantyOutcomeReplacement,
      'refund' => l.warrantyOutcomeRefund,
      'rejected' => l.warrantyOutcomeRejected,
      _ => outcome ?? '',
    };

@immutable
class WarrantyEvent {
  const WarrantyEvent({
    required this.kind,
    required this.note,
    required this.outcome,
    required this.createdAt,
    required this.actor,
  });
  final String kind; // opened | note | closed
  final String note;
  final String? outcome;
  final DateTime createdAt;
  final String actor;

  factory WarrantyEvent.fromJson(Map<String, dynamic> json) => WarrantyEvent(
    kind: json['kind'] as String,
    note: (json['note'] as String?) ?? '',
    outcome: json['outcome'] as String?,
    createdAt: DateTime.parse(json['created_at'] as String),
    actor: ((json['actor'] as Map?)?['name'] as String?) ?? '',
  );
}

/// A warranty claim: the list shows the summary fields, the detail adds the history.
@immutable
class WarrantyClaim {
  const WarrantyClaim({
    required this.id,
    required this.number,
    required this.status,
    required this.outcome,
    required this.outOfWarranty,
    required this.saleId,
    required this.saleNumber,
    required this.productName,
    required this.sku,
    required this.unitSymbol,
    required this.unitDecimals,
    required this.quantityMilli,
    required this.customerName,
    required this.customerPhone,
    required this.problem,
    required this.resolutionNote,
    required this.openedAt,
    required this.openedBy,
    required this.closedAt,
    required this.returnId,
    required this.returnNumber,
    required this.warrantyUntil,
    required this.events,
  });
  final String id;
  final int number;
  final String status; // open | closed
  final String? outcome;
  final bool outOfWarranty;
  final String saleId;
  final int saleNumber;
  final String productName;
  final String sku;
  final String unitSymbol;
  final int unitDecimals;
  final int quantityMilli;
  final String customerName;
  final String customerPhone;
  final String problem;
  final String resolutionNote;
  final DateTime openedAt;
  final String openedBy;
  final DateTime? closedAt;
  final String? returnId;
  final int? returnNumber;
  final String? warrantyUntil;
  final List<WarrantyEvent> events;

  bool get isOpen => status == 'open';

  factory WarrantyClaim.fromJson(Map<String, dynamic> json) {
    final product = (json['product'] as Map).cast<String, dynamic>();
    final line = (json['sale_line'] as Map?)?.cast<String, dynamic>();
    final ret = (json['return'] as Map?)?.cast<String, dynamic>();
    return WarrantyClaim(
      id: json['id'] as String,
      number: json['number'] as int,
      status: json['status'] as String,
      outcome: json['outcome'] as String?,
      outOfWarranty: (json['out_of_warranty'] as bool?) ?? false,
      saleId: (json['sale'] as Map)['id'] as String,
      saleNumber: (json['sale'] as Map)['number'] as int,
      productName: product['name'] as String,
      sku: (product['sku'] as String?) ?? '',
      unitSymbol: (product['unit_symbol'] as String?) ?? '',
      unitDecimals: (product['unit_decimals'] as int?) ?? 0,
      quantityMilli: parseServerDecimal(json['quantity'] as String, 3) ?? 0,
      customerName: (json['customer_name'] as String?) ?? '',
      customerPhone: (json['customer_phone'] as String?) ?? '',
      problem: (json['problem'] as String?) ?? '',
      resolutionNote: (json['resolution_note'] as String?) ?? '',
      openedAt: DateTime.parse(json['opened_at'] as String),
      openedBy: ((json['opened_by'] as Map?)?['name'] as String?) ?? '',
      closedAt: json['closed_at'] == null
          ? null
          : DateTime.parse(json['closed_at'] as String),
      returnId: ret?['id'] as String?,
      returnNumber: ret?['number'] as int?,
      warrantyUntil: line?['warranty_until'] as String?,
      events: [
        for (final e in (json['events'] as List?) ?? const [])
          WarrantyEvent.fromJson((e as Map).cast<String, dynamic>()),
      ],
    );
  }
}

class WarrantyPage {
  const WarrantyPage(this.items, this.count);
  final List<WarrantyClaim> items;
  final int count;
}

/// Whether a sale line's warranty has run out or never existed, by the date the server gave.
bool warrantyExpired({
  required int warrantyMonths,
  required String? warrantyUntil,
  DateTime? now,
}) {
  if (warrantyMonths <= 0 || warrantyUntil == null) return true;
  final until = DateTime.tryParse(warrantyUntil);
  if (until == null) return false;
  final today = now ?? DateTime.now();
  return DateTime(today.year, today.month, today.day).isAfter(until);
}
