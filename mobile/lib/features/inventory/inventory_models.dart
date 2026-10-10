import 'package:flutter/foundation.dart';

import '../../core/money/decimal_math.dart';
import '../catalog/catalog_models.dart';

/// The product as stock and purchasing screens show it.
@immutable
class ProductRef {
  const ProductRef({
    required this.id,
    required this.sku,
    required this.name,
    required this.unit,
  });
  final String id;
  final String sku;
  final String name;
  final UnitRef unit;

  factory ProductRef.fromJson(Map<String, dynamic> json) => ProductRef(
    id: json['id'] as String,
    sku: json['sku'] as String,
    name: json['name'] as String,
    unit: UnitRef.fromJson((json['unit'] as Map).cast<String, dynamic>()),
  );

  factory ProductRef.fromProduct(Product p) =>
      ProductRef(id: p.id, sku: p.sku, name: p.name, unit: p.unit);
}

/// Where goods are: sellable, damaged, awaiting inspection or in transit.
const stockConditions = ['sellable', 'damaged', 'inspection', 'in_transit'];

/// One balance row: how much of a product is at a location in a condition.
@immutable
class StockRow {
  const StockRow({
    required this.id,
    required this.product,
    required this.locationId,
    required this.locationName,
    required this.condition,
    required this.quantityMilli,
    this.valueMinor,
    this.averageCostMinor,
  });
  final String id;
  final ProductRef product;
  final String locationId;
  final String locationName;
  final String condition;

  /// Thousandths of the unit.
  final int quantityMilli;

  /// TMT hundredths; only present for roles that may see costs.
  final int? valueMinor;
  final int? averageCostMinor;

  factory StockRow.fromJson(Map<String, dynamic> json) {
    final location = (json['location'] as Map).cast<String, dynamic>();
    return StockRow(
      id: json['id'] as String,
      product: ProductRef.fromJson(
        (json['product'] as Map).cast<String, dynamic>(),
      ),
      locationId: location['id'] as String,
      locationName: location['name'] as String,
      condition: json['condition'] as String,
      quantityMilli: parseServerDecimal(json['quantity'] as String, 3) ?? 0,
      valueMinor: parseServerDecimal(json['value'] as String?, 2),
      averageCostMinor: parseServerDecimal(json['average_cost'] as String?, 2),
    );
  }
}

class StockPage {
  const StockPage(this.items, this.count);
  final List<StockRow> items;
  final int count;
}

/// One line of the stock ledger. Never edited; corrections are new movements.
@immutable
class MovementRow {
  const MovementRow({
    required this.id,
    required this.createdAt,
    required this.type,
    required this.product,
    required this.locationName,
    required this.condition,
    required this.quantityMilli,
    required this.documentType,
    required this.reason,
    required this.actorName,
    this.unitCostMinor,
  });
  final String id;
  final DateTime createdAt;
  final String type;
  final ProductRef product;
  final String locationName;
  final String condition;

  /// Signed: negative when goods left.
  final int quantityMilli;
  final String documentType;
  final String reason;
  final String actorName;
  final int? unitCostMinor;

  factory MovementRow.fromJson(Map<String, dynamic> json) => MovementRow(
    id: json['id'] as String,
    createdAt: DateTime.parse(json['created_at'] as String),
    type: json['movement_type'] as String,
    product: ProductRef.fromJson(
      (json['product'] as Map).cast<String, dynamic>(),
    ),
    locationName: (json['location'] as Map)['name'] as String,
    condition: json['condition'] as String,
    quantityMilli: parseServerDecimal(json['quantity'] as String, 3) ?? 0,
    documentType: (json['document_type'] as String?) ?? '',
    reason: (json['reason'] as String?) ?? '',
    actorName: ((json['actor'] as Map?)?['name'] as String?) ?? '',
    unitCostMinor: parseServerDecimal(json['unit_cost'] as String?, 2),
  );
}

class MovementPage {
  const MovementPage(this.items, this.count);
  final List<MovementRow> items;
  final int count;
}

/// A line typed into the opening-stock or adjustment form, before it is sent.
class StockEntryLine {
  StockEntryLine({
    required this.product,
    this.quantityText = '',
    this.costText = '',
    this.incoming = true,
    this.condition = 'sellable',
  });
  final ProductRef product;
  String quantityText;
  String costText;

  /// Adjustments only: true adds goods, false removes them.
  bool incoming;
  String condition;
}
