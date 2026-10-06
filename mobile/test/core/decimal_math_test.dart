import 'package:erp_system/core/money/decimal_math.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseScaled (what a person types)', () {
    test('accepts commas, dots and spaces', () {
      expect(parseScaled('12,34', 2), 1234);
      expect(parseScaled('12.34', 2), 1234);
      expect(parseScaled('1 234.5', 2), 123450);
      expect(parseScaled('1 234,5', 2), 123450);
      expect(parseScaled('85', 2), 8500);
      expect(parseScaled(',5', 2), 50);
      expect(parseScaled('0.29', 2), 29);
      expect(parseScaled('2,5', 3), 2500);
    });

    test('never rounds: extra decimals are refused', () {
      expect(parseScaled('2.345', 2), isNull);
      expect(parseScaled('1.5', 0), isNull);
      expect(parseScaled('0.0001', 3), isNull);
    });

    test('rejects negatives, letters, empties and double separators', () {
      for (final bad in [
        '-4',
        'NaN',
        'abc',
        '',
        ' ',
        '.',
        ',',
        '1.2.3',
        '1,2,3',
        '1e5',
        '12abc',
        '+5',
      ]) {
        expect(parseScaled(bad, 2), isNull, reason: '"$bad"');
      }
    });

    test('exact where doubles are not: 0.1 + 0.2 and 0.29', () {
      expect(
        parseScaled('0.1', 2)! + parseScaled('0.2', 2)!,
        parseScaled('0.3', 2),
      );
      expect((0.29 * 100).toInt(), isNot(29)); // the binary-float trap
      expect(parseScaled('0.29', 2), 29);
    });

    test('very large values are refused instead of overflowing silently', () {
      expect(parseScaled('1234567890123', 2), isNull);
      expect(parseScaled('999999999999', 2), 99999999999900);
    });
  });

  group('parseServerDecimal', () {
    test('reads the decimal strings the API sends', () {
      expect(parseServerDecimal('85.00', 2), 8500);
      expect(parseServerDecimal('24.000', 3), 24000);
      expect(
        parseServerDecimal('3.505000', 3),
        3505,
      ); // trailing zeros are harmless
      expect(parseServerDecimal('0.53', 2), 53);
      expect(parseServerDecimal('7', 2), 700);
      expect(parseServerDecimal('7', 0), 7);
    });

    test('refuses real extra precision, bad text and null', () {
      expect(parseServerDecimal('3.505001', 3), isNull);
      expect(parseServerDecimal('-1.00', 2), isNull);
      expect(parseServerDecimal('abc', 2), isNull);
      expect(parseServerDecimal(null, 2), isNull);
    });
  });

  group('formatting', () {
    test('toServerDecimal uses a dot and a fixed scale', () {
      expect(toServerDecimal(8500, 2), '85.00');
      expect(toServerDecimal(5, 2), '0.05');
      expect(toServerDecimal(123450, 2), '1234.50');
      expect(toServerDecimal(2500, 3), '2.500');
      expect(toServerDecimal(7, 0), '7');
      expect(toServerDecimal(-150, 2), '-1.50');
    });

    test('formatMoney groups thousands and uses a decimal comma', () {
      expect(formatMoney(123456, 'TMT'), '1 234,56 TMT');
      expect(formatMoney(5, 'USD'), '0,05 USD');
      expect(formatMoney(0, 'TMT'), '0,00 TMT');
      expect(formatMoney(-4200, 'TMT'), '−42,00 TMT');
      expect(formatMoney(100000000, 'TMT'), '1 000 000,00 TMT');
    });

    test('formatQuantity respects the unit precision', () {
      expect(formatQuantity(24000, 0), '24');
      expect(formatQuantity(2500, 2), '2,50');
      expect(formatQuantity(2500, 3), '2,500');
      expect(formatQuantity(1234567, 0), '1\u00a0234,567');
      expect(formatQuantity(-3000, 0), '−3');
    });

    test('round trip: what is typed is what is sent', () {
      for (final typed in ['85', '85,5', '0,05', '1 234,56']) {
        final minor = parseScaled(typed, 2)!;
        expect(parseServerDecimal(toServerDecimal(minor, 2), 2), minor);
      }
    });
  });
}
