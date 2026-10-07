/// Exact decimal handling with integers. Money and quantities are never held in
/// `double`: money is a count of hundredths, quantities a count of thousandths.
library;

const _nbsp = ' ';

int _pow10(int exponent) {
  var result = 1;
  for (var i = 0; i < exponent; i++) {
    result *= 10;
  }
  return result;
}

/// Parses a non-negative decimal typed by a person ("12,34", "1 234.5", ",5") into
/// `value * 10^scale`. Returns null for anything else: negative numbers, letters,
/// more than one separator, or more decimals than [scale] allows (never rounds).
int? parseScaled(String input, int scale) {
  final text = input
      .trim()
      .replaceAll(' ', '')
      .replaceAll(_nbsp, '')
      .replaceAll(',', '.');
  final match = RegExp(r'^(\d*)(?:\.(\d+))?$').firstMatch(text);
  if (match == null) return null;
  final whole = match.group(1)!;
  final fraction = match.group(2) ?? '';
  if (whole.isEmpty && fraction.isEmpty) return null;
  if (fraction.length > scale) return null;
  if (whole.length > 12) return null;
  final wholePart = whole.isEmpty ? 0 : int.parse(whole);
  final fractionPart = fraction.isEmpty
      ? 0
      : int.parse(fraction.padRight(scale, '0'));
  return wholePart * _pow10(scale) + fractionPart;
}

/// Parses a decimal string from the server ("85.00", "24.000", "3.505000") into
/// `value * 10^scale`. Trailing zeros beyond [scale] are accepted; any other extra
/// precision is rejected rather than rounded.
int? parseServerDecimal(String? input, int scale) {
  if (input == null) return null;
  final match = RegExp(r'^(\d+)(?:\.(\d+))?$').firstMatch(input.trim());
  if (match == null) return null;
  final whole = match.group(1)!;
  var fraction = match.group(2) ?? '';
  while (fraction.length > scale && fraction.endsWith('0')) {
    fraction = fraction.substring(0, fraction.length - 1);
  }
  if (fraction.length > scale) return null;
  final fractionValue = scale == 0
      ? 0
      : int.parse(fraction.padRight(scale, '0'));
  return int.parse(whole) * _pow10(scale) + fractionValue;
}

/// Like [parseServerDecimal], but accepts a leading minus sign: a profit can be a loss
/// (the seller may charge less than the goods cost).
int? parseSignedServerDecimal(String? input, int scale) {
  if (input == null) return null;
  final text = input.trim();
  if (!text.startsWith('-')) return parseServerDecimal(text, scale);
  final value = parseServerDecimal(text.substring(1), scale);
  return value == null ? null : -value;
}

/// The decimal string the server expects ("85.00"): a dot, exactly [scale] digits.
String toServerDecimal(int value, int scale) {
  final negative = value < 0;
  final absolute = value.abs();
  final unit = _pow10(scale);
  final whole = absolute ~/ unit;
  final text = scale == 0
      ? '$whole'
      : '$whole.${(absolute % unit).toString().padLeft(scale, '0')}';
  return negative ? '-$text' : text;
}

String _groupThousands(int whole) => whole.toString().replaceAllMapped(
  RegExp(r'\B(?=(\d{3})+(?!\d))'),
  (_) => _nbsp,
);

/// "1 234,50 TMT": hundredths of a currency unit, shown with a decimal comma.
String formatMoney(int minor, String currency) {
  final absolute = minor.abs();
  final text =
      '${_groupThousands(absolute ~/ 100)},${(absolute % 100).toString().padLeft(2, '0')}';
  return '${minor < 0 ? '−' : ''}$text$_nbsp$currency';
}

/// A quantity held in thousandths, shown with at least [unitDecimals] decimals and
/// no needless trailing zeros ("24", "2,5", "2,50" for a unit with 2 decimals).
String formatQuantity(int milli, int unitDecimals) {
  final absolute = milli.abs();
  final whole = absolute ~/ 1000;
  var fraction = (absolute % 1000).toString().padLeft(3, '0');
  while (fraction.length > unitDecimals && fraction.endsWith('0')) {
    fraction = fraction.substring(0, fraction.length - 1);
  }
  final text = fraction.isEmpty
      ? _groupThousands(whole)
      : '${_groupThousands(whole)},$fraction';
  return milli < 0 ? '−$text' : text;
}

/// An exchange rate held in millionths ("3,5", "3,505", "3,123456"): at least two
/// decimals, no needless trailing zeros.
String formatRate(int millionths) {
  final whole = millionths ~/ 1000000;
  var fraction = (millionths % 1000000).toString().padLeft(6, '0');
  while (fraction.length > 2 && fraction.endsWith('0')) {
    fraction = fraction.substring(0, fraction.length - 1);
  }
  return '$whole,$fraction';
}
