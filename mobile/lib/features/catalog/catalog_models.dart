import 'package:flutter/foundation.dart';

import '../../core/money/decimal_math.dart';

@immutable
class NamedRef {
  const NamedRef({required this.id, required this.name, this.isActive = true});
  final String id;
  final String name;
  final bool isActive;

  factory NamedRef.fromJson(Map<String, dynamic> json) => NamedRef(
    id: json['id'] as String,
    name: json['name'] as String,
    isActive: (json['is_active'] as bool?) ?? true,
  );
}

@immutable
class UnitRef {
  const UnitRef({
    required this.id,
    required this.name,
    required this.symbol,
    required this.decimalPlaces,
    this.isActive = true,
  });
  final String id;
  final String name;
  final String symbol;

  /// How many decimals a quantity of this unit may have (pieces: 0).
  final int decimalPlaces;
  final bool isActive;

  factory UnitRef.fromJson(Map<String, dynamic> json) => UnitRef(
    id: json['id'] as String,
    name: json['name'] as String,
    symbol: json['symbol'] as String,
    decimalPlaces: json['decimal_places'] as int,
    isActive: (json['is_active'] as bool?) ?? true,
  );
}

@immutable
class Product {
  const Product({
    required this.id,
    required this.sku,
    required this.name,
    required this.unit,
    required this.priceMinor,
    required this.priceCurrency,
    required this.priceTmtMinor,
    required this.rateMissing,
    required this.defaultCostMinor,
    required this.warrantyMonths,
    required this.warrantyTerms,
    required this.barcodes,
    required this.isActive,
    this.returnDays,
    this.category,
    this.brand,
    this.photoVersion,
    this.onHandMilli,
    this.minimumMilli,
    this.expiryDate,
    this.expiryQuantityMilli,
    this.expiryStatus,
  });

  final String id;
  final String sku;
  final String name;
  final NamedRef? category;
  final NamedRef? brand;
  final UnitRef unit;

  /// The price as the shop states it, in hundredths of [priceCurrency].
  final int priceMinor;
  final String priceCurrency; // TMT | USD

  /// The same price in TMT hundredths; null for a USD price when no rate exists.
  final int? priceTmtMinor;
  final bool rateMissing;

  /// Only present for roles that may see costs.
  final int? defaultCostMinor;
  final int warrantyMonths;
  final String warrantyTerms;

  /// Days after a sale the customer may return it: null = no limit, 0 = not returnable.
  final int? returnDays;
  final List<String> barcodes;
  final bool isActive;

  /// The version of the product's picture; null when it has none. A new picture is a new
  /// version, which is how a downloaded one is known to be out of date.
  final String? photoVersion;

  /// The sellable quantity in this person's places and the sum of their minimum levels, in
  /// thousandths. Null when the role may not see stock.
  final int? onHandMilli;
  final int? minimumMilli;
  final String? expiryDate;
  final int? expiryQuantityMilli;
  final String? expiryStatus;

  factory Product.fromJson(Map<String, dynamic> json) {
    final price = (json['price'] as Map).cast<String, dynamic>();
    return Product(
      id: json['id'] as String,
      sku: json['sku'] as String,
      name: json['name'] as String,
      category: json['category'] == null
          ? null
          : NamedRef.fromJson(
              (json['category'] as Map).cast<String, dynamic>(),
            ),
      brand: json['brand'] == null
          ? null
          : NamedRef.fromJson((json['brand'] as Map).cast<String, dynamic>()),
      unit: UnitRef.fromJson((json['unit'] as Map).cast<String, dynamic>()),
      priceMinor: parseServerDecimal(price['amount'] as String, 2) ?? 0,
      priceCurrency: price['currency'] as String,
      priceTmtMinor: parseServerDecimal(json['price_tmt'] as String?, 2),
      rateMissing: (json['price_rate_missing'] as bool?) ?? false,
      defaultCostMinor: parseServerDecimal(
        json['default_purchase_cost'] as String?,
        2,
      ),
      warrantyMonths: (json['warranty_months'] as int?) ?? 0,
      warrantyTerms: (json['warranty_terms'] as String?) ?? '',
      returnDays: json['return_days'] as int?,
      barcodes: [for (final b in json['barcodes'] as List) b as String],
      isActive: json['is_active'] as bool,
      photoVersion: (json['photo'] as Map?)?['version'] as String?,
      expiryDate: (json['expiry'] as Map?)?['date'] as String?,
      expiryQuantityMilli: parseServerDecimal(
        (json['expiry'] as Map?)?['quantity'] as String?,
        3,
      ),
      expiryStatus: (json['expiry'] as Map?)?['status'] as String?,
      onHandMilli: parseServerDecimal(
        (json['stock'] as Map?)?['on_hand'] as String?,
        3,
      ),
      minimumMilli: parseServerDecimal(
        (json['stock'] as Map?)?['minimum'] as String?,
        3,
      ),
    );
  }
}

/// What the product form sends. Amounts are exact decimal strings.
@immutable
class ProductDraft {
  const ProductDraft({
    required this.sku,
    required this.name,
    required this.unitId,
    required this.priceMinor,
    required this.priceCurrency,
    required this.warrantyMonths,
    required this.warrantyTerms,
    required this.barcodes,
    this.returnDays,
    this.categoryId,
    this.brandId,
    this.defaultCostMinor,
    this.includeCost = false,
  });

  final String sku;
  final String name;
  final String unitId;
  final String? categoryId;
  final String? brandId;
  final int priceMinor;
  final String priceCurrency;
  final int? defaultCostMinor;

  /// Only send the cost field when the user may see and edit it.
  final bool includeCost;
  final int warrantyMonths;
  final String warrantyTerms;

  /// Null clears the limit (the product can always be returned).
  final int? returnDays;
  final List<String> barcodes;

  Map<String, dynamic> toJson() => {
    'sku': sku,
    'name': name,
    'unit': unitId,
    'category': categoryId,
    'brand': brandId,
    'price_amount': toServerDecimal(priceMinor, 2),
    'price_currency': priceCurrency,
    if (includeCost)
      'default_purchase_cost': defaultCostMinor == null
          ? null
          : toServerDecimal(defaultCostMinor!, 2),
    'warranty_months': warrantyMonths,
    'warranty_terms': warrantyTerms,
    'return_days': returnDays,
    'barcodes': barcodes,
  };
}

@immutable
class ExchangeRateEntry {
  const ExchangeRateEntry({
    required this.id,
    required this.rate,
    required this.setBy,
    required this.createdAt,
  });
  final String id;

  /// TMT per 1 USD, as the server's exact decimal string.
  final String rate;
  final String setBy;
  final DateTime createdAt;

  factory ExchangeRateEntry.fromJson(Map<String, dynamic> json) =>
      ExchangeRateEntry(
        id: json['id'] as String,
        rate: json['rate'] as String,
        setBy: (json['set_by'] as String?) ?? '',
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}

class ProductPage {
  const ProductPage(this.items, this.count);
  final List<Product> items;
  final int count;
}

/// Whether [code] could be a GTIN (EAN-8, UPC-A, EAN-13, GTIN-14): only then the server is
/// asked what the open databases know. The server checks the check digit.
bool looksLikeGtin(String code) =>
    RegExp(r'^(\d{8}|\d{12,14})$').hasMatch(code.trim());

/// What the open product databases know about a barcode: a name to start from. Never saved by
/// itself; the person confirms or changes it.
@immutable
class ExternalInfo {
  const ExternalInfo({
    required this.name,
    required this.brand,
    required this.quantity,
    required this.source,
    this.category = '',
  });
  final String name;
  final String brand;
  final String quantity;
  final String source;
  final String category;

  /// The name to offer: the product's own name, with the brand and the size added when the name
  /// does not already say them ("CeraVe Moisturising Cream 454 g").
  String get displayName {
    final lower = name.toLowerCase();
    return [
      if (brand.isNotEmpty && !lower.contains(brand.toLowerCase())) brand,
      name,
      if (quantity.isNotEmpty && !lower.contains(quantity.toLowerCase()))
        quantity,
    ].join(' ');
  }

  /// Null when the databases know nothing (or could not be asked).
  static ExternalInfo? fromJson(Map<String, dynamic> json) {
    if (json['found'] != true) return null;
    final name = ((json['name'] as String?) ?? '').trim();
    if (name.isEmpty) return null;
    return ExternalInfo(
      name: name,
      brand: ((json['brand'] as String?) ?? '').trim(),
      quantity: ((json['quantity'] as String?) ?? '').trim(),
      source: (json['source'] as String?) ?? '',
      category: ((json['category'] as String?) ?? '').trim(),
    );
  }
}

/// A product that still needs a selling price or a cost: the "to complete" list.
@immutable
class ToCompleteItem {
  const ToCompleteItem({
    required this.id,
    required this.sku,
    required this.name,
    required this.unitSymbol,
    required this.unitDecimals,
    required this.priceMinor,
    required this.priceCurrency,
    required this.missingPrice,
    required this.missingCost,
    required this.stockWithoutCostMilli,
    required this.soldWithoutCostMilli,
  });

  final String id;
  final String sku;
  final String name;
  final String unitSymbol;
  final int unitDecimals;
  final int priceMinor;
  final String priceCurrency;
  final bool missingPrice;
  final bool missingCost;

  /// Pieces on the shelf, and pieces already sold, that wait for a cost (thousandths).
  final int stockWithoutCostMilli;
  final int soldWithoutCostMilli;

  factory ToCompleteItem.fromJson(Map<String, dynamic> json) => ToCompleteItem(
    id: json['id'] as String,
    sku: json['sku'] as String,
    name: json['name'] as String,
    unitSymbol: (json['unit_symbol'] as String?) ?? '',
    unitDecimals: (json['unit_decimals'] as int?) ?? 0,
    priceMinor: parseServerDecimal(json['price_amount'] as String?, 2) ?? 0,
    priceCurrency: (json['price_currency'] as String?) ?? 'TMT',
    missingPrice: json['missing_price'] == true,
    missingCost: json['missing_cost'] == true,
    stockWithoutCostMilli:
        parseServerDecimal(json['stock_without_cost'] as String?, 3) ?? 0,
    soldWithoutCostMilli:
        parseServerDecimal(json['sold_without_cost'] as String?, 3) ?? 0,
  );
}

/// Minimum and target stock of a product at one location (the reorder list uses them).
@immutable
class ReorderLevel {
  const ReorderLevel({
    required this.locationId,
    required this.locationName,
    required this.minimumMilli,
    required this.targetMilli,
  });
  final String locationId;
  final String locationName;
  final int minimumMilli;
  final int targetMilli;

  factory ReorderLevel.fromJson(Map<String, dynamic> json) => ReorderLevel(
    locationId: json['location'] as String,
    locationName: (json['location_name'] as String?) ?? '',
    minimumMilli: parseServerDecimal(json['minimum'] as String, 3) ?? 0,
    targetMilli: parseServerDecimal(json['target'] as String, 3) ?? 0,
  );
}

/// One problem found in an import file: the data row (1 = the first row after the header), the
/// column and what is wrong (a code the app translates).
@immutable
class ImportError {
  const ImportError({
    required this.row,
    required this.field,
    required this.code,
  });
  final int row;
  final String field;
  final String code;

  factory ImportError.fromJson(Map<String, dynamic> json) => ImportError(
    row: (json['row'] as int?) ?? 0,
    field: (json['field'] as String?) ?? '',
    code: (json['code'] as String?) ?? '',
  );
}

/// What checking an import file found. Nothing has been changed yet.
@immutable
class ImportPreview {
  const ImportPreview({
    required this.rows,
    required this.valid,
    required this.errorCount,
    required this.errors,
  });
  final int rows;
  final int valid;
  final int errorCount;
  final List<ImportError> errors;

  bool get canApply => rows > 0 && errorCount == 0;

  factory ImportPreview.fromJson(Map<String, dynamic> json) => ImportPreview(
    rows: (json['rows'] as int?) ?? 0,
    valid: (json['valid'] as int?) ?? 0,
    errorCount: (json['error_count'] as int?) ?? 0,
    errors: [
      for (final e in (json['errors'] as List?) ?? const [])
        ImportError.fromJson((e as Map).cast<String, dynamic>()),
    ],
  );
}
