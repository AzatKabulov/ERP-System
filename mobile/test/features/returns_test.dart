import 'package:erp_system/core/money/decimal_math.dart';
import 'package:erp_system/features/returns/returns_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/real_rig.dart';
import 'catalog_test.dart' show seedProduct;
import 'stock_ops_test.dart' show canPress, fieldNames;

const store = 'l-1'; // Esasy dükan, where the signed-in user starts

({RealRig rig, Map<String, dynamic> pad, Map<String, dynamic> sale}) salesRig({
  int stock = 10,
  int sold = 4,
  String price = '100.00',
  int? returnDays,
}) {
  final rig = RealRig();
  final pad = seedProduct(
    rig.server,
    sku: 'BP-1',
    name: 'Тормозные колодки',
    returnDays: returnDays,
  );
  final id = pad['id'] as String;
  rig.server.ledger.seedStock(id, store, '$stock', '50.00');
  final sale = rig.server.ledger.seedSale(
    productId: id,
    locationId: store,
    quantity: '$sold',
    price: price,
  );
  return (rig: rig, pad: pad, sale: sale);
}

String idOf(Map<String, dynamic> product) => product['id'] as String;

Future<void> openSale(WidgetTester tester, RealRig rig) async {
  await rig.launchSignedIn(tester);
  await tapKey(tester, 'nav-sales');
  await settle(tester);
  await tapKey(tester, 'sales-history');
  await settle(tester);
  await tapKey(tester, 'sale-S-000001');
  await settle(tester);
}

Future<void> openReturnForm(WidgetTester tester, RealRig rig) async {
  await openSale(tester, rig);
  await tapKey(tester, 'sd-return');
  await settle(tester);
}

String lineId(RealRig rig) =>
    ((rig.server.ledger.sales.first['lines'] as List).first as Map)['id']
        as String;

/// Types a quantity and a reason, then confirms.
Future<void> giveBack(
  WidgetTester tester,
  RealRig rig, {
  String quantity = '1',
  String reason = 'Не подошли',
}) async {
  await tester.enterText(key('return-qty-${lineId(rig)}'), quantity);
  await tester.enterText(key('return-reason'), reason);
  await tester.pump();
  await tapKey(tester, 'return-confirm');
  await settle(tester, ms: 400);
  await tester.tap(find.text('Подтвердить').last);
  await settle(tester);
}

void main() {
  group('refund arithmetic', () {
    test('a part is the price charged times the quantity, rounded half up', () {
      expect(
        refundMinor(
          quantityMilli: 2000,
          returnableMilli: 4000,
          unitPriceMinor: 8000,
          lineTotalMinor: 32000,
          refundedMinor: 0,
        ),
        16000,
      );
      expect(
        refundMinor(
          quantityMilli: 300,
          returnableMilli: 3000,
          unitPriceMinor: 33,
          lineTotalMinor: 99,
          refundedMinor: 0,
        ),
        10, // 0.099 -> 0.10
      );
    });

    test('bringing back everything that is left takes the remainder', () {
      // 3.00 at 0.33 = 0.99; 0.30 and 0.30 were refunded as 0.10 each
      expect(
        refundMinor(
          quantityMilli: 2400,
          returnableMilli: 2400,
          unitPriceMinor: 33,
          lineTotalMinor: 99,
          refundedMinor: 20,
        ),
        79,
      );
    });

    test('never more than what is left of the line, never negative', () {
      expect(
        refundMinor(
          quantityMilli: 1000,
          returnableMilli: 3000,
          unitPriceMinor: 5000,
          lineTotalMinor: 5500,
          refundedMinor: 1000,
        ),
        4500,
      );
      expect(
        refundMinor(
          quantityMilli: 1000,
          returnableMilli: 1000,
          unitPriceMinor: 100,
          lineTotalMinor: 100,
          refundedMinor: 500,
        ),
        0,
      );
    });

    test('quantities follow the unit precision', () {
      expect(parseReturnQuantity('2', 0), 2000);
      expect(parseReturnQuantity('0,5', 0), isNull);
      expect(parseReturnQuantity('0,5', 2), 500);
      expect(parseReturnQuantity('0', 0), isNull);
    });
  });

  group('customer returns', () {
    testWidgets(
      'a return refunds the price charged and brings the goods back',
      (tester) async {
        final t = salesRig(price: '80.00');
        await openReturnForm(tester, t.rig);
        expect(canPress(tester, 'return-confirm'), isFalse);
        await tester.enterText(key('return-qty-${lineId(t.rig)}'), '2');
        await tester.enterText(key('return-reason'), 'Не подошли');
        await tester.pump();
        expect(
          find.text('К возврату покупателю: ${formatMoney(16000, 'TMT')}'),
          findsOneWidget,
        ); // 2 x 80, not 2 x the catalog's 120
        await tapKey(tester, 'return-confirm');
        await settle(tester, ms: 400);
        expect(find.text('Подтвердить возврат'), findsOneWidget);
        await tester.tap(find.text('Подтвердить').last);
        await settle(tester);
        final ledger = t.rig.server.ledger;
        expect(ledger.returnsRecorded, 1);
        expect(find.text('Возврат оформлен.'), findsOneWidget);
        expect(ledger.quantityOf(idOf(t.pad), store), 8000); // 10 - 4 + 2
        expect(key('sd-return-R-0001'), findsOneWidget);
        expect(find.textContaining('Уже возвращено: 2 шт'), findsOneWidget);
        expect(t.rig.store.backing, isEmpty);
      },
    );

    testWidgets('the form offers only what is left and checks the quantity', (
      tester,
    ) async {
      final t = salesRig();
      await openReturnForm(tester, t.rig);
      expect(find.text('Можно вернуть: 4 шт'), findsOneWidget);
      await tester.enterText(key('return-qty-${lineId(t.rig)}'), '5');
      await tester.enterText(key('return-reason'), 'x');
      await tester.pump();
      expect(find.text('Некорректное значение.'), findsOneWidget);
      expect(canPress(tester, 'return-confirm'), isFalse);
      await tester.enterText(key('return-qty-${lineId(t.rig)}'), '1,5');
      await tester.pump();
      expect(canPress(tester, 'return-confirm'), isFalse); // pieces are whole
      await tester.enterText(key('return-qty-${lineId(t.rig)}'), '4');
      await tester.pump();
      expect(canPress(tester, 'return-confirm'), isTrue);
      await tester.enterText(key('return-reason'), '  ');
      await tester.pump();
      expect(canPress(tester, 'return-confirm'), isFalse); // a reason is needed
    });

    testWidgets('after everything came back there is nothing left to return', (
      tester,
    ) async {
      final t = salesRig();
      await openReturnForm(tester, t.rig);
      await giveBack(tester, t.rig, quantity: '4');
      expect(t.rig.server.ledger.returnsRecorded, 1);
      expect(key('sd-return'), findsNothing);
      expect(
        t.rig.server.ledger.saleReturns.first['refund'],
        40000,
      ); // the whole line
    });

    testWidgets('damaged goods do not become available stock', (tester) async {
      final t = salesRig();
      await openReturnForm(tester, t.rig);
      await tapKey(tester, 'return-cond-${lineId(t.rig)}-damaged');
      await tester.pump();
      await giveBack(tester, t.rig);
      final ledger = t.rig.server.ledger;
      expect(ledger.quantityOf(idOf(t.pad), store), 6000);
      expect(ledger.quantityOf(idOf(t.pad), store, 'damaged'), 1000);
    });

    testWidgets('goods awaiting inspection are decided later', (tester) async {
      final t = salesRig();
      await openReturnForm(tester, t.rig);
      await tapKey(tester, 'return-cond-${lineId(t.rig)}-inspection');
      await tester.pump();
      await giveBack(tester, t.rig, quantity: '3');
      final ledger = t.rig.server.ledger;
      expect(ledger.quantityOf(idOf(t.pad), store), 6000);
      expect(ledger.quantityOf(idOf(t.pad), store, 'inspection'), 3000);
      await goBack(tester);
      await goBack(tester);
      await tapKey(tester, 'sales-returns');
      await settle(tester);
      expect(find.text('Ожидает проверки'), findsWidgets);
      await tapKey(tester, 'return-R-0001');
      await settle(tester);
      final rl = (ledger.saleReturns.first['lines'] as List).first as Map;
      expect(key('rd-awaiting-${rl['id']}'), findsOneWidget);
      await tapKey(tester, 'rd-sellable-${rl['id']}');
      await settle(tester);
      expect(ledger.returnInspections, 1);
      expect(ledger.quantityOf(idOf(t.pad), store), 9000);
      expect(ledger.quantityOf(idOf(t.pad), store, 'inspection'), 0);
      expect(key('rd-awaiting-${rl['id']}'), findsNothing);
    });

    testWidgets('a product that is never taken back cannot be returned', (
      tester,
    ) async {
      final t = salesRig(returnDays: 0);
      await openSale(tester, t.rig);
      expect(find.text('Этот товар не принимается обратно'), findsOneWidget);
      await tapKey(tester, 'sd-return');
      await settle(tester);
      expect(key('return-blocked-${lineId(t.rig)}'), findsOneWidget);
      await tester.enterText(key('return-reason'), 'x');
      await tester.pump();
      expect(canPress(tester, 'return-confirm'), isFalse);
    });

    testWidgets('a return window is shown and the server has the last word', (
      tester,
    ) async {
      final t = salesRig(returnDays: 7);
      await openSale(tester, t.rig);
      expect(find.text('Вернуть можно до 2026-10-13'), findsOneWidget);
      await tapKey(tester, 'sd-return');
      await settle(tester);
      t.rig.server.ledger.returnWindowOver = true;
      await giveBack(tester, t.rig);
      expect(
        find.textContaining('Срок возврата этого товара истёк (2026-10-13).'),
        findsOneWidget,
      );
      expect(t.rig.server.ledger.returnsRecorded, 0);
      expect(t.rig.store.backing, isEmpty); // a refusal is final
    });

    testWidgets('a return refused because of a race names the product', (
      tester,
    ) async {
      final t = salesRig();
      await openReturnForm(tester, t.rig);
      // someone else brought 3 back in the meantime
      await tester.enterText(key('return-qty-${lineId(t.rig)}'), '3');
      await tester.enterText(key('return-reason'), 'x');
      await tester.pump();
      t.rig.server.ledger.saleReturns.add({});
      t.rig.server.ledger.saleReturns.clear();
      final line =
          (t.rig.server.ledger.sales.first['lines'] as List).first as Map;
      line['returned'] = 2000;
      await tapKey(tester, 'return-confirm');
      await settle(tester, ms: 400);
      await tester.tap(find.text('Подтвердить').last);
      await settle(tester);
      expect(
        find.text('Тормозные колодки: можно вернуть не больше 2 шт.'),
        findsOneWidget,
      );
      expect(t.rig.server.ledger.returnsRecorded, 0);
    });

    testWidgets('answer lost then the tablet restarts: exactly one return', (
      tester,
    ) async {
      final t = salesRig();
      await openReturnForm(tester, t.rig);
      t.rig.server.dropResponseAfterCommit = 1;
      await giveBack(tester, t.rig);
      expect(find.textContaining('Ответ сервера не получен'), findsOneWidget);
      expect(t.rig.store.backing.single.action, 'return_complete');
      expect(t.rig.server.ledger.returnsRecorded, 1);
      await tester.pumpWidget(const SizedBox());
      await t.rig.launch(tester);
      await settle(tester);
      expect(key('pending-banner'), findsNothing);
      expect(t.rig.store.backing, isEmpty);
      expect(t.rig.server.ledger.returnsRecorded, 1);
      expect(t.rig.server.ledger.quantityOf(idOf(t.pad), store), 7000);
    });

    testWidgets(
      'a failure before the server committed is resent with the same key',
      (tester) async {
        final t = salesRig();
        await openReturnForm(tester, t.rig);
        t.rig.server.failBeforeCommit = 1;
        await giveBack(tester, t.rig);
        expect(t.rig.server.ledger.returnsRecorded, 0);
        final pendingKey = t.rig.store.backing.single.key;
        await tapKey(tester, 'pending-review');
        await settle(tester, ms: 400);
        await tapKey(tester, 'pending-retry-$pendingKey');
        await settle(tester);
        expect(t.rig.server.ledger.returnsRecorded, 1);
        expect(t.rig.store.backing, isEmpty);
      },
    );

    testWidgets('every text field keeps its own name for a screen reader', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final t = salesRig();
      await openReturnForm(tester, t.rig);
      expect(fieldNames(tester), ['Вернуть', 'Причина возврата (обязательно)']);
      handle.dispose();
    });

    testWidgets(
      'roles: a keeper has no returns and a seller without the right has no button',
      (tester) async {
        final t = salesRig();
        t.rig.server.role = 'sales';
        t.rig.server.permissions = [
          'catalog.view',
          'stock.view',
          'location.view',
          'sales.view',
          'sales.create',
        ];
        await openSale(tester, t.rig);
        expect(key('sd-return'), findsNothing);
        await goBack(tester);
        await goBack(tester);
        expect(key('sales-returns'), findsNothing);
      },
    );

    for (final size in [const Size(360, 800), const Size(800, 1100)]) {
      testWidgets('the return screens fit at $size with doubled text', (
        tester,
      ) async {
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final t = salesRig(returnDays: 14);
        await t.rig.launch(tester, size: size);
        await t.rig.signIn(tester);
        if (size.width < 600) {
          await tester.tap(find.byTooltip('Меню'));
          await settle(tester, ms: 400);
          await tester.scrollUntilVisible(
            key('nav-sales'),
            200,
            scrollable: find.descendant(
              of: find.byType(Drawer),
              matching: find.byType(Scrollable),
            ),
          );
        }
        await tapKey(tester, 'nav-sales');
        await settle(tester);
        expect(tester.takeException(), isNull, reason: 'sales page');
        await tapKey(tester, 'sales-history');
        await settle(tester);
        expect(tester.takeException(), isNull, reason: 'history');
        await tapKey(tester, 'sale-S-000001');
        await settle(tester);
        expect(tester.takeException(), isNull, reason: 'sale detail');
        await tapKey(tester, 'sd-return');
        await settle(tester);
        expect(tester.takeException(), isNull, reason: 'return form');
        await tester.enterText(key('return-qty-${lineId(t.rig)}'), '1');
        await tester.pump();
        expect(tester.takeException(), isNull);
      });
    }
  });
}
