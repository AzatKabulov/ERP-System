import 'package:flutter/foundation.dart';

import '../../core/money/decimal_math.dart';
import '../inventory/inventory_models.dart';

const orderStatuses = [
  'draft',
  'ordered',
  'partially_received',
  'received',
  'cancelled',
];

/// "PO-0007": how a purchase order is named on screen.
String orderNumber(int number) => 'PO-${number.toString().padLeft(4, '0')}';

@immutable
class Supplier {
  const Supplier({
    required this.id,
    required this.name,
    required this.contactName,
    required this.phone,
    required this.email,
    required this.address,
    required this.notes,
    required this.isActive,
  });
  final String id;
  final String name;
  final String contactName;
  final String phone;
  final String email;
  final String address;
  final String notes;
  final bool isActive;

  factory Supplier.fromJson(Map<String, dynamic> json) => Supplier(
    id: json['id'] as String,
    name: json['name'] as String,
    contactName: (json['contact_name'] as String?) ?? '',
    phone: (json['phone'] as String?) ?? '',
    email: (json['email'] as String?) ?? '',
    address: (json['address'] as String?) ?? '',
    notes: (json['notes'] as String?) ?? '',
    isActive: (json['is_active'] as bool?) ?? true,
  );
}

class SupplierPage {
  const SupplierPage(this.items, this.count);
  final List<Supplier> items;
  final int count;
}

@immutable
class OrderSummary {
  const OrderSummary({
    required this.id,
    required this.number,
    required this.status,
    required this.supplierName,
    required this.locationName,
    required this.expectedDate,
    required this.lineCount,
    required this.orderedMilli,
    required this.receivedMilli,
    this.totalMinor,
  });
  final String id;
  final int number;
  final String status;
  final String supplierName;
  final String locationName;
  final String? expectedDate;
  final int lineCount;
  final int orderedMilli;
  final int receivedMilli;

  /// TMT hundredths; only present for roles that may see costs.
  final int? totalMinor;

  factory OrderSummary.fromJson(Map<String, dynamic> json) => OrderSummary(
    id: json['id'] as String,
    number: json['number'] as int,
    status: json['status'] as String,
    supplierName: (json['supplier'] as Map)['name'] as String,
    locationName: (json['location'] as Map)['name'] as String,
    expectedDate: json['expected_date'] as String?,
    lineCount: json['line_count'] as int,
    orderedMilli:
        parseServerDecimal(json['ordered_quantity'] as String, 3) ?? 0,
    receivedMilli:
        parseServerDecimal(json['received_quantity'] as String, 3) ?? 0,
    totalMinor: parseServerDecimal(json['total'] as String?, 2),
  );
}

class OrderPage {
  const OrderPage(this.items, this.count);
  final List<OrderSummary> items;
  final int count;
}

@immutable
class OrderLine {
  const OrderLine({
    required this.id,
    required this.product,
    required this.quantityMilli,
    required this.receivedMilli,
    required this.outstandingMilli,
    this.unitCostMinor,
    this.lineTotalMinor,
  });
  final String id;
  final ProductRef product;
  final int quantityMilli;
  final int receivedMilli;
  final int outstandingMilli;
  final int? unitCostMinor;
  final int? lineTotalMinor;

  factory OrderLine.fromJson(Map<String, dynamic> json) => OrderLine(
    id: json['id'] as String,
    product: ProductRef.fromJson(
      (json['product'] as Map).cast<String, dynamic>(),
    ),
    quantityMilli: parseServerDecimal(json['quantity'] as String, 3) ?? 0,
    receivedMilli:
        parseServerDecimal(json['received_quantity'] as String, 3) ?? 0,
    outstandingMilli: parseServerDecimal(json['outstanding'] as String, 3) ?? 0,
    unitCostMinor: parseServerDecimal(json['unit_cost'] as String?, 2),
    lineTotalMinor: parseServerDecimal(json['line_total'] as String?, 2),
  );
}

@immutable
class DeliveryLineRecord {
  const DeliveryLineRecord({
    required this.product,
    required this.quantityMilli,
    this.unitCostMinor,
  });
  final ProductRef product;
  final int quantityMilli;
  final int? unitCostMinor;

  factory DeliveryLineRecord.fromJson(Map<String, dynamic> json) =>
      DeliveryLineRecord(
        product: ProductRef.fromJson(
          (json['product'] as Map).cast<String, dynamic>(),
        ),
        quantityMilli: parseServerDecimal(json['quantity'] as String, 3) ?? 0,
        unitCostMinor: parseServerDecimal(json['unit_cost'] as String?, 2),
      );
}

@immutable
class DeliveryRecord {
  const DeliveryRecord({
    required this.number,
    required this.receivedAt,
    required this.receivedBy,
    required this.note,
    required this.lines,
  });
  final int number;
  final DateTime receivedAt;
  final String receivedBy;
  final String note;
  final List<DeliveryLineRecord> lines;

  factory DeliveryRecord.fromJson(Map<String, dynamic> json) => DeliveryRecord(
    number: json['number'] as int,
    receivedAt: DateTime.parse(json['received_at'] as String),
    receivedBy: ((json['received_by'] as Map?)?['name'] as String?) ?? '',
    note: (json['note'] as String?) ?? '',
    lines: [
      for (final l in json['lines'] as List)
        DeliveryLineRecord.fromJson((l as Map).cast<String, dynamic>()),
    ],
  );
}

@immutable
class PurchaseOrder {
  const PurchaseOrder({
    required this.id,
    required this.number,
    required this.status,
    required this.supplierId,
    required this.supplierName,
    required this.locationId,
    required this.locationName,
    required this.expectedDate,
    required this.notes,
    required this.cancelReason,
    required this.lines,
    required this.deliveries,
    this.totalMinor,
  });
  final String id;
  final int number;
  final String status;
  final String supplierId;
  final String supplierName;
  final String locationId;
  final String locationName;
  final String? expectedDate;
  final String notes;
  final String cancelReason;
  final List<OrderLine> lines;
  final List<DeliveryRecord> deliveries;
  final int? totalMinor;

  bool get isDraft => status == 'draft';
  bool get isOpen => status == 'ordered' || status == 'partially_received';
  bool get canCancel => isDraft || isOpen;

  factory PurchaseOrder.fromJson(Map<String, dynamic> json) {
    final supplier = (json['supplier'] as Map).cast<String, dynamic>();
    final location = (json['location'] as Map).cast<String, dynamic>();
    return PurchaseOrder(
      id: json['id'] as String,
      number: json['number'] as int,
      status: json['status'] as String,
      supplierId: supplier['id'] as String,
      supplierName: supplier['name'] as String,
      locationId: location['id'] as String,
      locationName: location['name'] as String,
      expectedDate: json['expected_date'] as String?,
      notes: (json['notes'] as String?) ?? '',
      cancelReason: (json['cancel_reason'] as String?) ?? '',
      lines: [
        for (final l in json['lines'] as List)
          OrderLine.fromJson((l as Map).cast<String, dynamic>()),
      ],
      deliveries: [
        for (final d in json['deliveries'] as List)
          DeliveryRecord.fromJson((d as Map).cast<String, dynamic>()),
      ],
      totalMinor: parseServerDecimal(json['total'] as String?, 2),
    );
  }
}

/// A line typed into the order form.
class OrderDraftLine {
  OrderDraftLine({
    required this.product,
    this.quantityText = '',
    this.costText = '',
  });
  final ProductRef product;
  String quantityText;
  String costText;
}
