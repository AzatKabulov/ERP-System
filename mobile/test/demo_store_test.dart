import 'package:flutter_test/flutter_test.dart';
import 'package:erp_system/demo/demo_store.dart';
import 'package:erp_system/widgets/common.dart';

void main() {
  late DemoStore store;
  setUp(() => store = DemoStore());
  tearDown(() => store.dispose());

  test(
    'sale decreases stock once and a second checkout cannot duplicate it',
    () {
      final p = store.product('filter');
      store.addToCart(p);
      store.addToCart(p);
      final sale = store.checkout();
      expect(sale!.totalMinor, 17000);
      expect(store.stock(p), 22);
      expect(store.cart, isEmpty);
      expect(store.checkout(), isNull);
      expect(store.sales, hasLength(1));
    },
  );

  test(
    'cart cannot oversell and changing location cannot silently lose it',
    () {
      final p = store.product('battery');
      expect(store.addToCart(p), isTrue);
      expect(store.addToCart(p), isTrue);
      expect(store.addToCart(p), isFalse);
      expect(store.changeLocation('warehouse'), isFalse);
      expect(store.location, 'store');
      expect(store.cartCount, 2);
      expect(store.changeLocation('warehouse', discardCart: true), isTrue);
      expect(store.cart, isEmpty);
    },
  );

  test('receiving an order twice does not duplicate inventory', () {
    final p = store.product('oil');
    expect(store.receive(p, 10, orderId: 'PO-001'), isTrue);
    expect(store.receive(p, 10, orderId: 'PO-001'), isFalse);
    expect(store.stock(p), 18);
    expect(store.receive(p, -1), isFalse);
  });

  test('demo transfer conserves stock and respects cart quantities', () {
    final p = store.product('battery');
    store.addToCart(p);
    expect(store.transfer(p, 2, 'warehouse'), isFalse);
    expect(store.transfer(p, 1, 'warehouse'), isTrue);
    expect(store.stock(p), 1);
    expect(store.stock(p, 'warehouse'), 13);
    expect(store.transfer(p, 1, 'store'), isFalse);
    expect(store.transfer(p, 1, 'missing'), isFalse);
  });

  test(
    'count rejects negative quantities and preserves active cart capacity',
    () {
      final p = store.product('filter');
      store.addToCart(p);
      expect(store.count(p, -1), isFalse);
      expect(store.count(p, 0), isFalse);
      expect(store.count(p, 10), isTrue);
      expect(store.stock(p), 10);
      expect(store.activities.first.quantity, -14);
    },
  );

  test(
    'return restores original location only for sellable goods and caps quantity',
    () {
      final p = store.product('filter');
      store.addToCart(p);
      store.addToCart(p);
      final sale = store.checkout()!;
      store.changeLocation('warehouse');
      expect(store.refund(sale, p.id, 1, sellable: true), isTrue);
      expect(store.stock(p, 'store'), 23);
      expect(store.stock(p, 'warehouse'), 80);
      expect(store.refund(sale, p.id, 1, sellable: false), isTrue);
      expect(store.stock(p, 'store'), 23);
      expect(store.refund(sale, p.id, 1, sellable: true), isFalse);
      expect(store.refundTotal, 17000);
    },
  );

  test(
    'money parsing uses integer minor units and rejects excess decimal precision',
    () {
      expect(parseMinor('12,34'), 1234);
      expect(parseMinor('1 234.5'), 123450);
      expect(parseMinor('0.29'), 29);
      expect(parseMinor('2.345'), isNull);
      expect(parseMinor('-4'), isNull);
      expect(parseMinor('NaN'), isNull);
      expect(money(123456), '1\u00a0234,56\u00a0TMT');
      expect(store.addExpense('Доставка', 1234), isTrue);
      expect(store.expenseTotal, 1234);
      expect(store.addExpense('', 100), isFalse);
    },
  );
}
