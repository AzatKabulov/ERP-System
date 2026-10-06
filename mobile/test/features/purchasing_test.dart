import 'package:erp_system/core/money/decimal_math.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/real_rig.dart';
import 'catalog_test.dart' show seedProduct;

const store = 'l-1'; // Esasy dükan
const warehouse = 'l-2'; // Ammar

Future<void> openPurchasing(WidgetTester tester, RealRig rig) async {
  await rig.launchSignedIn(tester);
  await tapKey(tester, 'nav-purchasing');
  await settle(tester);
}

/// A rig with two products, a supplier and an ordered order of 10 pads at 50.
({RealRig rig, Map<String, dynamic> pad, Map<String, dynamic> order})
ordered() {
  final rig = RealRig();
  final pad = seedProduct(
    rig.server,
    sku: 'BP-1',
    name: 'Колодки',
    cost: '50.00',
  );
  final supplier = rig.server.ledger.seedSupplier('Ашхабад Запчасти');
  final order = rig.server.ledger.seedOrder(
    supplierId: supplier['id'] as String,
    locationId: warehouse,
    lines: [(productId: pad['id'] as String, quantity: '10', cost: '50.00')],
  );
  return (rig: rig, pad: pad, order: order);
}

Future<void> openOrder(WidgetTester tester, String label) async {
  await tapKey(tester, 'order-$label');
  await settle(tester);
}

Future<void> receive(WidgetTester tester, String quantity) async {
  await tapKey(tester, 'od-receive');
  await settle(tester);
  await tester.enterText(key('receive-qty-BP-1'), quantity);
  await tapKey(tester, 'receive-submit');
  await settle(tester);
}

void main() {
  group('orders list', () {
    testWidgets('an empty list says so and offers a new order and suppliers', (
      tester,
    ) async {
      final rig = RealRig();
      await openPurchasing(tester, rig);
      expect(key('orders-empty'), findsOneWidget);
      expect(find.text('Заказов пока нет'), findsOneWidget);
      expect(key('order-new'), findsOneWidget);
      expect(key('order-suppliers'), findsOneWidget);
    });

    testWidgets(
      'lists orders with status, progress and total, and filters by status',
      (tester) async {
        final t = ordered();
        t.rig.server.ledger.seedOrder(
          supplierId: t.rig.server.ledger.suppliers.first['id'] as String,
          locationId: warehouse,
          status: 'draft',
          lines: [
            (productId: t.pad['id'] as String, quantity: '2', cost: '50.00'),
          ],
        );
        await openPurchasing(tester, t.rig);
        expect(key('order-PO-0001'), findsOneWidget);
        expect(key('order-PO-0002'), findsOneWidget);
        expect(find.text('Оформлен'), findsWidgets);
        expect(find.text('Черновик'), findsWidgets);
        expect(find.text(formatMoney(50000, 'TMT')), findsOneWidget);
        expect(find.text('Заказано 10, принято 0'), findsOneWidget);
        await tapKey(tester, 'order-filter-draft');
        await settle(tester);
        expect(key('order-PO-0001'), findsNothing);
        expect(key('order-PO-0002'), findsOneWidget);
      },
    );

    testWidgets(
      'a warehouse user sees quantities and no costs, and cannot create orders',
      (tester) async {
        final t = ordered();
        t.rig.server.role = 'warehouse';
        t.rig.server.permissions = [
          'catalog.view',
          'stock.view',
          'supplier.view',
          'purchasing.view',
          'purchasing.receive',
          'location.view',
        ];
        await openPurchasing(tester, t.rig);
        expect(key('order-new'), findsNothing);
        expect(
          find.textContaining('TMT'),
          findsNothing,
        ); // no totals in the list
        await openOrder(tester, 'PO-0001');
        expect(find.text('Заказано 10 шт, принято 0 шт'), findsOneWidget);
        expect(key('od-total'), findsNothing);
        expect(find.textContaining('TMT'), findsNothing);
        expect(key('od-receive'), findsOneWidget);
        expect(key('od-edit'), findsNothing);
        expect(key('od-cancel'), findsNothing);
      },
    );
  });

  group('suppliers', () {
    testWidgets('add, reject a duplicate name, edit and archive', (
      tester,
    ) async {
      final rig = RealRig();
      await openPurchasing(tester, rig);
      await tapKey(tester, 'order-suppliers');
      await settle(tester);
      expect(key('suppliers-empty'), findsOneWidget);
      await tapKey(tester, 'supplier-add');
      await settle(tester, ms: 400);
      await tester.enterText(key('supplier-name'), 'Ýüpek Ätiýaçlyk');
      await tester.enterText(key('supplier-phone'), '+993 12 000000');
      await tapKey(tester, 'supplier-save');
      await settle(tester);
      expect(key('supplier-Ýüpek Ätiýaçlyk'), findsOneWidget);
      expect(find.text('Поставщик сохранён.'), findsOneWidget);
      // the same name again, in other letter case
      await tapKey(tester, 'supplier-add');
      await settle(tester, ms: 400);
      await tester.enterText(key('supplier-name'), 'ÝÜPEK ÄTIÝAÇLYK');
      await tapKey(tester, 'supplier-save');
      await settle(tester);
      expect(find.text('Такое название уже есть.'), findsOneWidget);
      await tester.tap(find.text('Отмена'));
      await settle(tester, ms: 400);
      // edit, then archive
      await tapKey(tester, 'supplier-Ýüpek Ätiýaçlyk');
      await settle(tester, ms: 400);
      await tester.enterText(key('supplier-contact'), 'Aman');
      await tapKey(tester, 'supplier-save');
      await settle(tester);
      expect(rig.server.ledger.suppliers.single['contact_name'], 'Aman');
      await tapKey(tester, 'supplier-Ýüpek Ätiýaçlyk');
      await settle(tester, ms: 400);
      await tapKey(tester, 'supplier-toggle');
      await settle(tester);
      expect(rig.server.ledger.suppliers.single['is_active'], isFalse);
      expect(
        key('suppliers-empty'),
        findsOneWidget,
      ); // archived ones are hidden
    });

    testWidgets('a user who may only view suppliers cannot add or edit', (
      tester,
    ) async {
      final rig = RealRig();
      rig.server.permissions = [
        'supplier.view',
        'purchasing.view',
        'location.view',
      ];
      rig.server.ledger.seedSupplier('Ашхабад');
      await openPurchasing(tester, rig);
      await tapKey(tester, 'order-suppliers');
      await settle(tester);
      expect(key('supplier-Ашхабад'), findsOneWidget);
      expect(key('supplier-add'), findsNothing);
    });
  });

  group('creating and submitting an order', () {
    testWidgets(
      'a draft is saved with a number, submitted after confirming, and stays fixed',
      (tester) async {
        final rig = RealRig();
        final pad = seedProduct(
          rig.server,
          sku: 'BP-1',
          name: 'Колодки',
          cost: '50.00',
        );
        rig.server.ledger.seedSupplier('Ашхабад Запчасти');
        await openPurchasing(tester, rig);
        await tapKey(tester, 'order-new');
        await settle(tester);
        await tapKey(tester, 'of-supplier');
        await settle(tester, ms: 400);
        await tester.tap(find.text('Ашхабад Запчасти').last);
        await settle(tester, ms: 400);
        await tapKey(tester, 'of-add-line');
        await settle(tester, ms: 600);
        await tester.tap(key('picker-BP-1'));
        await settle(tester, ms: 400);
        expect(
          tester.widget<TextField>(key('of-cost-0')).controller!.text,
          '50,00',
        ); // pre-filled from the product's default cost
        await tester.enterText(key('of-qty-0'), '10');
        await tapKey(tester, 'of-save');
        await settle(tester);
        // saved as a draft and opened
        expect(find.text('PO-0001'), findsWidgets);
        expect(find.text('Черновик'), findsWidgets);
        expect(key('od-total'), findsOneWidget);
        expect(
          find.text('Итого: ${formatMoney(50000, 'TMT')}'),
          findsOneWidget,
        );
        expect(rig.server.ledger.orders.single['status'], 'draft');
        expect(rig.server.ledger.quantityOf(pad['id'] as String, warehouse), 0);
        // submit, after confirming
        await tapKey(tester, 'od-submit');
        await settle(tester, ms: 400);
        expect(
          find.text('После оформления заказ нельзя редактировать. Оформить?'),
          findsOneWidget,
        );
        await tester.tap(find.text('Подтвердить'));
        await settle(tester);
        expect(rig.server.ledger.orders.single['status'], 'ordered');
        expect(find.text('Оформлен'), findsWidgets);
        expect(key('od-edit'), findsNothing); // no longer editable
        expect(key('od-receive'), findsOneWidget);
        // still no stock: only receiving moves stock
        expect(rig.server.ledger.quantityOf(pad['id'] as String, warehouse), 0);
      },
    );

    testWidgets(
      'a draft can be edited and an order can be cancelled with a reason',
      (tester) async {
        final t = ordered();
        final draft = t.rig.server.ledger.seedOrder(
          supplierId: t.rig.server.ledger.suppliers.first['id'] as String,
          locationId: warehouse,
          status: 'draft',
          lines: [
            (productId: t.pad['id'] as String, quantity: '2', cost: '50.00'),
          ],
        );
        await openPurchasing(tester, t.rig);
        await openOrder(tester, 'PO-0002');
        await tapKey(tester, 'od-edit');
        await settle(tester);
        await tester.enterText(key('of-qty-0'), '4');
        await tester.enterText(key('of-notes'), 'Срочно');
        await tapKey(tester, 'of-save');
        await settle(tester);
        expect(((draft['lines'] as List).single as Map)['quantity'], 4000);
        expect(draft['notes'], 'Срочно');
        expect(find.text('Заказ сохранён.'), findsOneWidget);
        // cancel it
        await tapKey(tester, 'od-cancel');
        await settle(tester, ms: 400);
        await tester.enterText(key('od-cancel-reason'), 'Передумали');
        await tester.tap(key('od-cancel-confirm'));
        await settle(tester);
        expect(draft['status'], 'cancelled');
        expect(find.text('Причина отмены: Передумали'), findsOneWidget);
        expect(key('od-cancel'), findsNothing);
      },
    );

    testWidgets('the form checks required fields before sending', (
      tester,
    ) async {
      final rig = RealRig();
      seedProduct(rig.server, sku: 'BP-1', name: 'Колодки');
      rig.server.ledger.seedSupplier('Ашхабад');
      await openPurchasing(tester, rig);
      await tapKey(tester, 'order-new');
      await settle(tester);
      await tapKey(tester, 'of-save');
      await settle(tester, ms: 300);
      expect(find.text('Обязательное поле.'), findsOneWidget); // the supplier
      expect(rig.server.ledger.orders, isEmpty);
    });
  });

  group('receiving', () {
    testWidgets(
      'a partial delivery, then the rest: stock follows, the order closes',
      (tester) async {
        final t = ordered();
        await openPurchasing(tester, t.rig);
        await openOrder(tester, 'PO-0001');
        expect(find.text('Заказано 10 шт, принято 0 шт'), findsOneWidget);
        await receive(tester, '4');
        expect(
          find.text('Поставка принята, остатки обновлены.'),
          findsOneWidget,
        );
        expect(
          t.rig.server.ledger.quantityOf(t.pad['id'] as String, warehouse),
          4000,
        );
        expect(find.text('Принят частично'), findsWidgets);
        expect(find.text('Заказано 10 шт, принято 4 шт'), findsOneWidget);
        expect(key('od-delivery-1'), findsOneWidget);
        expect(key('od-receive'), findsOneWidget);
        // the rest, using "receive everything left"
        await tapKey(tester, 'od-receive');
        await settle(tester);
        expect(
          find.text(
            'Осталось принять: 6 шт · ${formatMoney(5000, 'TMT')}'.replaceFirst(
              'Осталось принять: 6 шт',
              'BP-1 · Осталось принять: 6 шт',
            ),
          ),
          findsOneWidget,
        );
        await tapKey(tester, 'receive-all');
        await tapKey(tester, 'receive-submit');
        await settle(tester);
        expect(
          t.rig.server.ledger.quantityOf(t.pad['id'] as String, warehouse),
          10000,
        );
        expect(find.text('Принят полностью'), findsWidgets);
        expect(key('od-receive'), findsNothing);
        expect(key('od-delivery-2'), findsOneWidget);
        expect(t.rig.server.ledger.deliveriesRecorded, 2);
        expect(t.rig.store.backing, isEmpty);
      },
    );

    testWidgets(
      'more than is outstanding is refused on the form and never sent',
      (tester) async {
        final t = ordered();
        await openPurchasing(tester, t.rig);
        await openOrder(tester, 'PO-0001');
        await receive(tester, '11');
        expect(
          find.text('Нельзя принять больше, чем осталось по заказу.'),
          findsOneWidget,
        );
        expect(t.rig.server.ledger.deliveriesRecorded, 0);
        expect(
          t.rig.server.log.where((l) => l.contains('/deliveries/')),
          isEmpty,
        );
      },
    );

    testWidgets('an empty delivery is refused, a half piece too', (
      tester,
    ) async {
      final t = ordered();
      await openPurchasing(tester, t.rig);
      await openOrder(tester, 'PO-0001');
      await receive(tester, '0');
      expect(key('receive-nothing'), findsOneWidget);
      await tester.enterText(key('receive-qty-BP-1'), '1,5');
      await tapKey(tester, 'receive-submit');
      await settle(tester, ms: 300);
      expect(
        find.text('Для этой единицы допускается меньше знаков после запятой.'),
        findsOneWidget,
      );
      expect(t.rig.server.ledger.deliveriesRecorded, 0);
    });

    testWidgets(
      'a draft has no receive button; a cancelled order cannot be received',
      (tester) async {
        final t = ordered();
        t.rig.server.ledger.orders.single['status'] = 'cancelled';
        await openPurchasing(tester, t.rig);
        await openOrder(tester, 'PO-0001');
        expect(key('od-receive'), findsNothing);
      },
    );

    testWidgets(
      'an order received elsewhere meanwhile is refused with a clear message',
      (tester) async {
        final t = ordered();
        await openPurchasing(tester, t.rig);
        await openOrder(tester, 'PO-0001');
        await tapKey(tester, 'od-receive');
        await settle(tester);
        // someone else cancels it while the form is open
        t.rig.server.ledger.orders.single['status'] = 'cancelled';
        await tapKey(tester, 'receive-submit');
        await settle(tester);
        expect(
          find.text(
            'Этот заказ сейчас не принимается: он не оформлен, уже принят или отменён.',
          ),
          findsOneWidget,
        );
        expect(t.rig.server.ledger.deliveriesRecorded, 0);
        expect(t.rig.store.backing, isEmpty); // a refusal is definite
      },
    );

    testWidgets(
      'a lost answer: the receipt is recorded once, and retrying reuses the key',
      (tester) async {
        final t = ordered();
        await openPurchasing(tester, t.rig);
        await openOrder(tester, 'PO-0001');
        t.rig.server.dropResponseAfterCommit = 1;
        await receive(tester, '4');
        expect(find.textContaining('Ответ сервера не получен'), findsOneWidget);
        expect(key('pending-banner'), findsOneWidget);
        expect(t.rig.server.ledger.deliveriesRecorded, 1);
        expect(t.rig.store.backing.single.action, 'purchase_receive');
        expect(t.rig.store.backing.single.subject, 'PO-0001');
        final pendingKey = t.rig.store.backing.single.key;
        await tapKey(tester, 'pending-review');
        await settle(tester, ms: 400);
        expect(
          find.text('Приём товара · PO-0001'),
          findsOneWidget,
        ); // named, not a raw code
        await tapKey(tester, 'pending-retry-$pendingKey');
        await settle(tester);
        expect(
          t.rig.server.ledger.deliveriesRecorded,
          1,
        ); // answered from the record
        expect(
          t.rig.server.ledger.quantityOf(t.pad['id'] as String, warehouse),
          4000,
        );
        expect(t.rig.store.backing, isEmpty);
      },
    );

    testWidgets(
      'a lost answer then an app restart: found completed, exactly one delivery',
      (tester) async {
        final t = ordered();
        await openPurchasing(tester, t.rig);
        await openOrder(tester, 'PO-0001');
        t.rig.server.dropResponseAfterCommit = 1;
        await receive(tester, '4');
        expect(t.rig.server.ledger.deliveriesRecorded, 1);
        expect(t.rig.store.backing, hasLength(1));
        // the tablet restarts: a fresh app on the same device storage
        await tester.pumpWidget(const SizedBox());
        await t.rig.launch(tester);
        await settle(tester);
        expect(
          key('pending-banner'),
          findsNothing,
        ); // the server confirmed the saved key
        expect(t.rig.store.backing, isEmpty);
        expect(t.rig.server.ledger.deliveriesRecorded, 1);
        expect(
          t.rig.server.ledger.quantityOf(t.pad['id'] as String, warehouse),
          4000,
        );
        await tapKey(tester, 'nav-purchasing');
        await settle(tester);
        await openOrder(tester, 'PO-0001');
        expect(find.text('Заказано 10 шт, принято 4 шт'), findsOneWidget);
      },
    );

    testWidgets(
      'a receipt the server never saw is sent again with the same key after a restart',
      (tester) async {
        final t = ordered();
        await openPurchasing(tester, t.rig);
        await openOrder(tester, 'PO-0001');
        t.rig.server.failBeforeCommit = 1; // a 5xx before anything was recorded
        await receive(tester, '4');
        expect(t.rig.server.ledger.deliveriesRecorded, 0);
        final pendingKey = t.rig.store.backing.single.key;
        await tester.pumpWidget(const SizedBox());
        await t.rig.launch(tester);
        await settle(tester);
        expect(
          key('pending-banner'),
          findsOneWidget,
        ); // not confirmed: still listed
        await tapKey(tester, 'pending-review');
        await settle(tester, ms: 400);
        await tapKey(tester, 'pending-retry-$pendingKey');
        await settle(tester);
        expect(t.rig.server.ledger.deliveriesRecorded, 1);
        expect(t.rig.server.records.keys, [pendingKey]); // one key, one record
        expect(t.rig.store.backing, isEmpty);
      },
    );
  });
}
