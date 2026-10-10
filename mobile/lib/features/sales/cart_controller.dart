import 'package:flutter/foundation.dart';

import '../../core/money/decimal_math.dart';
import '../catalog/catalog_models.dart';
import '../inventory/quantity_input.dart';
import 'sales_models.dart';

/// One line of the cart: a product with the typed quantity and the price the seller
/// charges. Prices are not fixed, so the price starts as the catalog price in TMT (empty
/// when a USD price has no rate yet) and the seller may change it to anything.
class CartLine {
  CartLine({
    required this.product,
    this.quantityText = '1',
    String? priceText,
    this.availableMilli,
  }) : priceText = priceText ?? _catalogPriceText(product);

  Product product;
  String quantityText;
  String priceText;

  /// Sellable stock at the current location when it was last looked up; null when unknown.
  /// Only a hint: the cart reserves nothing, and the server decides when the sale is saved.
  int? availableMilli;

  static String _catalogPriceText(Product product) {
    final minor = product.priceTmtMinor;
    return minor == null ? '' : toServerDecimal(minor, 2).replaceAll('.', ',');
  }
}

/// The cart, with exact integer arithmetic (hundredths of TMT, thousandths of a unit). It
/// reserves no stock. The line total is quantity x price rounded half up to hundredths, as
/// the server does it; the total is the sum of the lines.
class CartController extends ChangeNotifier {
  final List<CartLine> _lines = [];
  Customer? _customer;

  List<CartLine> get lines => List.unmodifiable(_lines);
  Customer? get customer => _customer;
  bool get isEmpty => _lines.isEmpty;

  set customer(Customer? value) {
    _customer = value;
    notifyListeners();
  }

  /// Adds one unit of [product], or one more when it is already there.
  void add(Product product, {int? availableMilli}) {
    final existing = _lines
        .where((l) => l.product.id == product.id)
        .firstOrNull;
    if (existing == null) {
      _lines.add(CartLine(product: product, availableMilli: availableMilli));
    } else {
      final current = quantityMilli(existing) ?? 0;
      existing.quantityText = formatQuantity(
        current + 1000,
        product.unit.decimalPlaces,
      );
      existing.availableMilli = availableMilli ?? existing.availableMilli;
    }
    notifyListeners();
  }

  void remove(CartLine line) {
    _lines.remove(line);
    notifyListeners();
  }

  void clear() {
    _lines.clear();
    _customer = null;
    notifyListeners();
  }

  void setQuantityText(CartLine line, String text) {
    line.quantityText = text;
    notifyListeners();
  }

  void setPriceText(CartLine line, String text) {
    line.priceText = text;
    notifyListeners();
  }

  void step(CartLine line, int deltaMilli) {
    final current = quantityMilli(line) ?? 0;
    final next = current + deltaMilli;
    if (next <= 0) return;
    line.quantityText = formatQuantity(next, line.product.unit.decimalPlaces);
    notifyListeners();
  }

  // ---- arithmetic -------------------------------------------------------------

  int? quantityMilli(CartLine line) =>
      parseQuantity(line.quantityText, line.product.unit);

  /// The price the seller charges for one unit, in TMT hundredths; null while it is empty
  /// or not a number. Zero is allowed.
  int? priceMinor(CartLine line) => parseScaled(line.priceText, 2);

  int? lineTotalMinor(CartLine line) {
    final quantity = quantityMilli(line);
    final price = priceMinor(line);
    if (quantity == null || price == null) return null;
    return (quantity * price + 500) ~/ 1000;
  }

  int get totalMinor =>
      _lines.fold(0, (sum, line) => sum + (lineTotalMinor(line) ?? 0));

  /// What is wrong with a line, as a code the screen translates; null when it is fine.
  String? problem(CartLine line) {
    if (line.quantityText.trim().isEmpty) return 'required';
    final quantity = quantityMilli(line);
    if (quantity == null) return 'quantity';
    final available = line.availableMilli;
    if (available != null && quantity > available) return 'exceeds_available';
    if (line.priceText.trim().isEmpty) return 'price_required';
    if (priceMinor(line) == null) return 'price_invalid';
    return null;
  }

  bool get isReady =>
      _lines.isNotEmpty && _lines.every((l) => problem(l) == null);

  /// The lines as the sale command wants them (call only when [isReady]).
  List<({String productId, int quantityMilli, int unitPriceMinor})>
  get saleLines => [
    for (final l in _lines)
      (
        productId: l.product.id,
        quantityMilli: quantityMilli(l)!,
        unitPriceMinor: priceMinor(l)!,
      ),
  ];
}
