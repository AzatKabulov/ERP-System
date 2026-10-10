import 'package:erp_system/core/money/decimal_math.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/real_rig.dart';
import 'catalog_test.dart' show seedProduct;

const store = 'l-1'; // Esasy dükan
const warehouse = 'l-2'; // Ammar

Future<void> openStock(WidgetTester tester, RealRig rig) async {
  await rig.launchSignedIn(tester);
  await tapKey(tester, 'nav-inventory');
  await settle(tester);
}

/// Picks a product in the picker dialog (search, then tap the result).
Future<void> pickProduct(WidgetTester tester, String sku) async {
  await tapKey(tester, 'entry-add-line');
  await settle(tester, ms: 600);
  await tester.tap(key('picker-$sku'));
  await settle(tester, ms: 400);
}

void main() {
  group('stock list', () {
    testWidgets('an empty ledger says so and offers the first entries', (
      tester,
    ) async {
      final rig = RealRig();
      await openStock(tester, rig);
      expect(key('stock-empty'), findsOneWidget);
      expect(find.text('Остатков пока нет'), findsOneWidget);
      expect(key('stock-opening'), findsOneWidget);
      expect(key('stock-adjust'), findsOneWidget);
      expect(key('stock-history'), findsOneWidget);
    });

    testWidgets('shows quantity with its unit, and the value for cost roles', (
      tester,
    ) async {
      final rig = RealRig();
      final pad = seedProduct(
        rig.server,
        sku: 'BP-1',
        name: 'Тормозные колодки',
      );
      rig.server.ledger
        ..seedStock(pad['id'] as String, store, '10', '50.00')
        ..seedStock(pad['id'] as String, store, '10', '60.00')
        ..seedStock(
          pad['id'] as String,
          warehouse,
          '3',
          '50.00',
          condition: 'damaged',
        );
      await openStock(tester, rig);
      expect(key('stock-BP-1-Esasy dükan-sellable'), findsOneWidget);
      expect(find.text('20 шт'), findsOneWidget);
      // 10 x 50 + 10 x 60 = 1 100,00
      expect(
        find.text('Стоимость: ${formatMoney(110000, 'TMT')}'),
        findsOneWidget,
      );
      expect(find.text('3 шт'), findsOneWidget);
      expect(find.text('Повреждённый'), findsOneWidget);
    });

    testWidgets('filters by location and by search', (tester) async {
      final rig = RealRig();
      final pad = seedProduct(
        rig.server,
        sku: 'BP-1',
        name: 'Тормозные колодки',
      );
      final oil = seedProduct(rig.server, sku: 'OIL-1', name: 'Масло');
      rig.server.ledger
        ..seedStock(pad['id'] as String, store, '5', '50')
        ..seedStock(oil['id'] as String, warehouse, '7', '20');
      await openStock(tester, rig);
      expect(key('stock-BP-1-Esasy dükan-sellable'), findsOneWidget);
      expect(key('stock-OIL-1-Ammar-sellable'), findsOneWidget);
      await tapKey(tester, 'stock-location-Ammar');
      await settle(tester);
      expect(key('stock-BP-1-Esasy dükan-sellable'), findsNothing);
      expect(key('stock-OIL-1-Ammar-sellable'), findsOneWidget);
      await tapKey(tester, 'stock-location-all');
      await tester.enterText(key('stock-search'), 'колодки');
      await settle(tester, ms: 600);
      expect(key('stock-OIL-1-Ammar-sellable'), findsNothing);
      expect(key('stock-BP-1-Esasy dükan-sellable'), findsOneWidget);
      await tester.enterText(key('stock-search'), 'нет такого');
      await settle(tester, ms: 600);
      expect(find.text('Товары не найдены'), findsOneWidget);
    });

    testWidgets(
      'a warehouse user sees quantities but no cost and no stock entry',
      (tester) async {
        final rig = RealRig();
        rig.server.role = 'warehouse';
        rig.server.permissions = [
          'catalog.view',
          'stock.view',
          'stock.history.view',
          'location.view',
        ];
        final pad = seedProduct(
          rig.server,
          sku: 'BP-1',
          name: 'Колодки',
          cost: '50.00',
        );
        rig.server.ledger.seedStock(pad['id'] as String, store, '10', '50.00');
        await openStock(tester, rig);
        expect(find.text('10 шт'), findsOneWidget);
        expect(find.textContaining('Стоимость'), findsNothing);
        expect(key('stock-opening'), findsNothing);
        expect(key('stock-adjust'), findsNothing);
        expect(key('stock-history'), findsOneWidget);
        await tapKey(tester, 'stock-history');
        await settle(tester);
        expect(
          find.textContaining('@'),
          findsNothing,
        ); // no unit cost in the history
        expect(find.text('+10 шт'), findsOneWidget);
      },
    );

    testWidgets('a sales user sees stock but not the history button', (
      tester,
    ) async {
      final rig = RealRig();
      rig.server.role = 'sales';
      rig.server.permissions = ['catalog.view', 'stock.view', 'location.view'];
      final pad = seedProduct(rig.server, sku: 'BP-1', name: 'Колодки');
      rig.server.ledger.seedStock(pad['id'] as String, store, '4', '50');
      await openStock(tester, rig);
      expect(find.text('4 шт'), findsOneWidget);
      expect(key('stock-history'), findsNothing);
    });

    testWidgets(
      'movement history shows signed quantities, newest first, with cost',
      (tester) async {
        final rig = RealRig();
        final pad = seedProduct(rig.server, sku: 'BP-1', name: 'Колодки');
        rig.server.ledger
          ..seedStock(pad['id'] as String, store, '10', '50.00')
          ..seedStock(pad['id'] as String, store, '10', '60.00');
        await openStock(tester, rig);
        await tapKey(tester, 'stock-history');
        await settle(tester);
        expect(
          find.text('Корректировка (приход)'),
          findsNothing,
        ); // type is part of a longer line
        expect(
          find.textContaining('Корректировка (приход) · Esasy dükan'),
          findsNWidgets(2),
        );
        expect(find.text('+10 шт'), findsNWidgets(2));
        expect(find.text('@ ${formatMoney(5000, 'TMT')}'), findsOneWidget);
        expect(find.text('@ ${formatMoney(6000, 'TMT')}'), findsOneWidget);
      },
    );
  });

  group('opening stock', () {
    Future<void> openForm(WidgetTester tester, RealRig rig) async {
      await openStock(tester, rig);
      await tapKey(tester, 'stock-opening');
      await settle(tester);
    }

    testWidgets('posts quantity with its unit cost and updates the list', (
      tester,
    ) async {
      final rig = RealRig();
      final pad = seedProduct(rig.server, sku: 'BP-1', name: 'Колодки');
      await openForm(tester, rig);
      await pickProduct(tester, 'BP-1');
      await tester.enterText(key('entry-qty-0'), '12');
      await tester.enterText(key('entry-cost-0'), '48,50');
      await tester.enterText(key('entry-reason'), 'Инвентаризация при запуске');
      await tapKey(tester, 'entry-submit');
      await settle(tester);
      expect(rig.server.ledger.quantityOf(pad['id'] as String, store), 12000);
      expect(find.text('Проведено.'), findsOneWidget);
      expect(key('stock-BP-1-Esasy dükan-sellable'), findsOneWidget);
      expect(find.text('12 шт'), findsOneWidget);
      expect(
        find.text('Стоимость: ${formatMoney(58200, 'TMT')}'),
        findsOneWidget,
      );
      final sent = rig.server.records.values.single.body;
      expect(sent['document_id'], isNotNull);
      expect(rig.store.backing, isEmpty); // confirmed, so nothing stays pending
    });

    testWidgets('checks the form before anything is sent', (tester) async {
      final rig = RealRig();
      seedProduct(rig.server, sku: 'BP-1', name: 'Колодки');
      await openForm(tester, rig);
      await tapKey(tester, 'entry-submit');
      await settle(tester, ms: 300);
      expect(key('entry-needs-lines'), findsOneWidget);
      await pickProduct(tester, 'BP-1');
      await tester.enterText(key('entry-qty-0'), '1,5'); // pieces are whole
      await tapKey(tester, 'entry-submit');
      await settle(tester, ms: 300);
      expect(
        find.text('Для этой единицы допускается меньше знаков после запятой.'),
        findsOneWidget,
      );
      expect(find.text('Обязательное поле.'), findsOneWidget); // the cost
      expect(rig.server.ledger.stockWrites, 0);
      expect(
        rig.server.log.where((l) => l.contains('/stock/opening/')),
        isEmpty,
      );
    });

    testWidgets(
      'a second opening for the same product is refused with a clear message',
      (tester) async {
        final rig = RealRig();
        final pad = seedProduct(rig.server, sku: 'BP-1', name: 'Колодки');
        rig.server.ledger.seedStock(pad['id'] as String, store, '1', '10');
        await openForm(tester, rig);
        await pickProduct(tester, 'BP-1');
        await tester.enterText(key('entry-qty-0'), '5');
        await tester.enterText(key('entry-cost-0'), '10');
        await tapKey(tester, 'entry-submit');
        await settle(tester);
        expect(
          find.text(
            'По этому товару в этой точке уже есть движения. Используйте корректировку.',
          ),
          findsOneWidget,
        );
        expect(find.textContaining('opening_stock_exists'), findsNothing);
        expect(rig.server.ledger.quantityOf(pad['id'] as String, store), 1000);
        expect(
          rig.store.backing,
          isEmpty,
        ); // a refusal is definite: nothing is left pending
      },
    );

    testWidgets('the same product cannot be added twice', (tester) async {
      final rig = RealRig();
      seedProduct(rig.server, sku: 'BP-1', name: 'Колодки');
      await openForm(tester, rig);
      await pickProduct(tester, 'BP-1');
      await pickProduct(tester, 'BP-1');
      expect(key('entry-qty-1'), findsNothing);
      expect(find.text('Этот товар уже есть в списке.'), findsOneWidget);
    });

    testWidgets('leaving a form with entries asks first', (tester) async {
      final rig = RealRig();
      seedProduct(rig.server, sku: 'BP-1', name: 'Колодки');
      await openForm(tester, rig);
      await pickProduct(tester, 'BP-1');
      await tester.tap(find.byType(BackButton));
      await settle(tester, ms: 400);
      expect(find.text('Подтвердить'), findsOneWidget);
      await tester.tap(find.text('Отмена'));
      await settle(tester, ms: 400);
      expect(key('entry-qty-0'), findsOneWidget);
    });

    testWidgets('a lost answer is recovered: one posting, with the same key', (
      tester,
    ) async {
      final rig = RealRig();
      final pad = seedProduct(rig.server, sku: 'BP-1', name: 'Колодки');
      await openForm(tester, rig);
      await pickProduct(tester, 'BP-1');
      await tester.enterText(key('entry-qty-0'), '12');
      await tester.enterText(key('entry-cost-0'), '48,50');
      rig.server.dropResponseAfterCommit = 1;
      await tapKey(tester, 'entry-submit');
      await settle(tester);
      // the server committed, the app never heard: it says so and keeps the key
      expect(find.textContaining('Ответ сервера не получен'), findsOneWidget);
      expect(key('pending-banner'), findsOneWidget);
      expect(rig.store.backing, hasLength(1));
      expect(rig.server.ledger.quantityOf(pad['id'] as String, store), 12000);
      final pendingKey = rig.store.backing.single.key;
      // retrying uses the SAME key and is answered from the server's record
      await tapKey(tester, 'pending-review');
      await settle(tester, ms: 400);
      await tapKey(tester, 'pending-retry-$pendingKey');
      await settle(tester);
      expect(rig.server.ledger.quantityOf(pad['id'] as String, store), 12000);
      expect(rig.server.ledger.stockWrites, 1);
      expect(rig.store.backing, isEmpty);
    });
  });

  group('adjustments', () {
    Future<void> openForm(WidgetTester tester, RealRig rig) async {
      await openStock(tester, rig);
      await tapKey(tester, 'stock-adjust');
      await settle(tester);
    }

    testWidgets('a write-off needs a reason and takes the oldest cost first', (
      tester,
    ) async {
      final rig = RealRig();
      final pad = seedProduct(rig.server, sku: 'BP-1', name: 'Колодки');
      rig.server.ledger
        ..seedStock(pad['id'] as String, store, '10', '50.00')
        ..seedStock(pad['id'] as String, store, '10', '60.00');
      await openForm(tester, rig);
      await pickProduct(tester, 'BP-1');
      await tapKey(tester, 'entry-out-0');
      await tester.enterText(key('entry-qty-0'), '15');
      await tapKey(tester, 'entry-submit'); // no reason yet
      await settle(tester, ms: 300);
      expect(find.text('Обязательное поле.'), findsOneWidget);
      expect(rig.server.ledger.stockWrites, 0);
      await tester.enterText(key('entry-reason'), 'Повреждено водой');
      await tapKey(tester, 'entry-submit');
      await settle(tester);
      expect(rig.server.ledger.quantityOf(pad['id'] as String, store), 5000);
      final costs = rig.server.ledger.movements
          .where((m) => m['movement_type'] == 'adjustment_out')
          .map((m) => '${m['quantity']}@${m['unit_cost']}')
          .toList();
      expect(costs, ['-5.000@60.00', '-10.000@50.00']); // newest first
      expect(find.text('5 шт'), findsOneWidget);
    });

    testWidgets(
      'taking out more than there is shows the server refusal and changes nothing',
      (tester) async {
        final rig = RealRig();
        final pad = seedProduct(rig.server, sku: 'BP-1', name: 'Колодки');
        rig.server.ledger.seedStock(pad['id'] as String, store, '3', '50');
        await openForm(tester, rig);
        await pickProduct(tester, 'BP-1');
        await tapKey(tester, 'entry-out-0');
        await tester.enterText(key('entry-qty-0'), '4');
        await tester.enterText(key('entry-reason'), 'Потеря');
        await tapKey(tester, 'entry-submit');
        await settle(tester);
        expect(find.text('Недостаточно товара на складе.'), findsOneWidget);
        expect(rig.server.ledger.quantityOf(pad['id'] as String, store), 3000);
        expect(rig.store.backing, isEmpty);
        expect(
          key('entry-submit'),
          findsOneWidget,
        ); // still on the form to correct it
      },
    );

    testWidgets('an increase asks for a cost and a condition can be chosen', (
      tester,
    ) async {
      final rig = RealRig();
      final pad = seedProduct(rig.server, sku: 'BP-1', name: 'Колодки');
      await openForm(tester, rig);
      await pickProduct(tester, 'BP-1');
      expect(key('entry-cost-0'), findsNothing); // starts as a decrease
      await tapKey(tester, 'entry-in-0');
      expect(key('entry-cost-0'), findsOneWidget);
      await tester.enterText(key('entry-qty-0'), '2');
      await tester.enterText(key('entry-cost-0'), '55');
      await tester.enterText(key('entry-reason'), 'Найдено при проверке');
      await tapKey(tester, 'entry-condition-0');
      await settle(tester, ms: 400);
      await tester.tap(find.text('Повреждённый').last);
      await settle(tester, ms: 400);
      await tapKey(tester, 'entry-submit');
      await settle(tester);
      expect(
        rig.server.ledger.quantityOf(pad['id'] as String, store, 'damaged'),
        2000,
      );
      expect(rig.server.ledger.quantityOf(pad['id'] as String, store), 0);
    });
  });
}
