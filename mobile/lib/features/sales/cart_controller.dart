import 'package:flutter/foundation.dart';

import '../../core/money/decimal_math.dart';
import '../catalog/catalog_models.dart';
import '../inventory/quantity_input.dart';
import 'sales_models.dart';

/// One line of the cart: a product with the typed quantity and discount.
class CartLine {
  CartLine({
    required this.product,
    this.quantityText = '1',
    this.discountText = '',
    this.availableMilli,
  });

  Product product;
  String quantityText;
  String discountText;

  /// Sellable stock at the current location when it was last looked up; null when unknown.
  /// Only a hint: the cart reserves nothing, and the server decides at checkout.
  int? availableMilli;
}

/// The cart, with exact integer arithmetic (hundredths of TMT, thousandths of a unit). It
/// reserves no stock. Totals follow the server's rules: line gross = quantity x unit price
/// rounded half up to hundredths, the discount comes off the line, the total is the sum.
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

  void setDiscountText(CartLine line, String text) {
    line.discountText = text;
    notifyListeners();
  }

  void step(CartLine line, int deltaMilli) {
    final current = quantityMilli(line) ?? 0;
    final next = current + deltaMilli;
    if (next <= 0) return;
    line.quantityText = formatQuantity(next, line.product.unit.decimalPlaces);
    notifyListeners();
  }

  /// Gives every line the same percentage off ([percentText] like "10" or "7,5").
  /// Returns false when the percentage is not a number from 0 to 100.
  bool applyPercentToAll(String percentText) {
    final percent = parseScaled(percentText, 2); // hundredths of a percent
    if (percent == null || percent > 10000) return false;
    for (final line in _lines) {
      final gross = grossMinor(line);
      if (gross == null) continue;
      final discount = (gross * percent + 5000) ~/ 10000;
      line.discountText = discount == 0
          ? ''
          : toServerDecimal(discount, 2).replaceAll('.', ',');
    }
    notifyListeners();
    return true;
  }

  /// Replaces a product with a freshly loaded copy (after the prices changed).
  void refreshProduct(Product fresh) {
    for (final line in _lines) {
      if (line.product.id == fresh.id) line.product = fresh;
    }
    notifyListeners();
  }

  // ---- arithmetic -------------------------------------------------------------

  int? quantityMilli(CartLine line) =>
      parseQuantity(line.quantityText, line.product.unit);

  /// The unit price in TMT hundredths; null for a USD price while no rate exists.
  int? unitPriceMinor(CartLine line) => line.product.priceTmtMinor;

  int? grossMinor(CartLine line) {
    final quantity = quantityMilli(line);
    final unit = unitPriceMinor(line);
    if (quantity == null || unit == null) return null;
    return (quantity * unit + 500) ~/ 1000;
  }

  int? discountMinor(CartLine line) {
    if (line.discountText.trim().isEmpty) return 0;
    return parseScaled(line.discountText, 2);
  }

  int? lineTotalMinor(CartLine line) {
    final gross = grossMinor(line);
    final discount = discountMinor(line);
    if (gross == null || discount == null || discount > gross) return null;
    return gross - discount;
  }

  int get totalMinor =>
      _lines.fold(0, (sum, line) => sum + (lineTotalMinor(line) ?? 0));

  int get discountTotalMinor =>
      _lines.fold(0, (sum, line) => sum + (discountMinor(line) ?? 0));

  /// What is wrong with a line, as a code the screen translates; null when it is fine.
  String? problem(CartLine line) {
    if (line.product.priceTmtMinor == null) return 'rate_missing';
    if (line.quantityText.trim().isEmpty) return 'required';
    final quantity = quantityMilli(line);
    if (quantity == null) return 'quantity';
    final available = line.availableMilli;
    if (available != null && quantity > available) return 'exceeds_available';
    final discount = discountMinor(line);
    if (discount == null) return 'discount_invalid';
    if (discount > (grossMinor(line) ?? 0)) return 'discount_too_large';
    return null;
  }

  bool get isReady =>
      _lines.isNotEmpty && _lines.every((l) => problem(l) == null);

  /// The lines as the sale command wants them (call only when [isReady]).
  List<({String productId, int quantityMilli, int discountMinor})>
  get saleLines => [
    for (final l in _lines)
      (
        productId: l.product.id,
        quantityMilli: quantityMilli(l)!,
        discountMinor: discountMinor(l)!,
      ),
  ];
}
