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
