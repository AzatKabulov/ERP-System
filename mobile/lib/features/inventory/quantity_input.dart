import '../../core/money/decimal_math.dart';
import '../catalog/catalog_models.dart';

int _pow10(int exponent) {
  var result = 1;
  for (var i = 0; i < exponent; i++) {
    result *= 10;
  }
  return result;
}

/// A typed quantity in thousandths, or null when it is empty, not a positive number,
/// or has more decimals than [unit] allows (pieces are whole). Never rounds.
int? parseQuantity(String text, UnitRef unit) {
  final milli = parseScaled(text, 3);
  if (milli == null || milli <= 0) return null;
  if (milli % _pow10(3 - unit.decimalPlaces.clamp(0, 3)) != 0) return null;
  return milli;
}

/// "12,5 шт" - a quantity with its unit symbol.
String quantityWithUnit(int milli, UnitRef unit) =>
    '${formatQuantity(milli, unit.decimalPlaces)} ${unit.symbol}';
