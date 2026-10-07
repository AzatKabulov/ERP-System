import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/real_rig.dart';
import 'purchasing_test.dart'
    show openOrder, openPurchasing, ordered, warehouse;
import 'stock_ops_test.dart' show fieldNames;

String idOf(Map<String, dynamic> product) => product['id'] as String;

/// The delivery line of the received order (to type into its quantity box).
String deliveryLineId(Map<String, dynamic> order) =>
    (((order['deliveries'] as List).first as Map)['lines'] as List).first['id']
        as String;

({RealRig rig, Map<String, dynamic> pad, Map<String, dynamic> order}) received({
  int stockAfter = 10,
}) {
  final t = ordered();
  t.rig.server.ledger.seedDelivery(t.order);
  return t;
}

Future<void> openDelivery(WidgetTester tester, RealRig rig) async {
  await openPurchasing(tester, rig);
  await openOrder(tester, 'PO-0001');
  await tapKey(tester, 'od-return-1');
  await settle(tester);
}

Future<void> sendBack(
  WidgetTester tester,
  Map<String, dynamic> order, {
  String quantity = '3',
  String reason = 'Не тот товар',
}) async {
  await tester.enterText(key('sr-qty-${deliveryLineId(order)}'), quantity);
  await tester.enterText(key('sr-reason'), reason);
  await tester.pump();
  await tapKey(tester, 'sr-confirm');
  await settle(tester);
}

void main() {
  group('returns to a supplier', () {
    testWidgets('goods go back against the delivery and leave the stock', (
      tester,
    ) async {
      final t = received();
      await openDelivery(tester, t.rig);
      expect(find.text('Можно вернуть: 10 шт'), findsOneWidget);
      await sendBack(tester, t.order);
      final ledger = t.rig.server.ledger;
      expect(ledger.supplierReturnsRecorded, 1);
      expect(find.text('Возврат поставщику оформлен.'), findsOneWidget);
      expect(ledger.quantityOf(idOf(t.pad), warehouse), 7000);
      expect(t.rig.store.backing, isEmpty);
      await goBack(tester);
      await tapKey(tester, 'purchasing-returns');
      await settle(tester);
      expect(key('supplier-return-SR-0001'), findsOneWidget);
      expect(find.textContaining('Зачёт поставщика: 150,00'), findsOneWidget);
    });

    testWidgets('only what the delivery brought and is still here is offered', (
      tester,
    ) async {
      final t = received();
      await openDelivery(tester, t.rig);
      await sendBack(tester, t.order, quantity: '8');
      await tapKey(tester, 'od-return-1');
      await settle(tester);
      expect(find.text('Можно вернуть: 2 шт'), findsOneWidget);
      await tester.enterText(key('sr-qty-${deliveryLineId(t.order)}'), '3');
      await tester.pump();
      expect(find.text('Некорректное значение.'), findsOneWidget);
    });

    testWidgets('goods that are already gone cannot be sent back', (
      tester,
    ) async {
      final t = received();
      t.rig.server.ledger.seedSale(
        productId: idOf(t.pad),
        locationId: warehouse,
        quantity: '9',
        price: '100.00',
      );
      await openDelivery(tester, t.rig);
      await sendBack(tester, t.order, quantity: '3');
      expect(find.textContaining('Недостаточно товара'), findsOneWidget);
      expect(t.rig.server.ledger.supplierReturnsRecorded, 0);
      expect(t.rig.store.backing, isEmpty);
    });

    testWidgets('answer lost then the tablet restarts: exactly one return', (
      tester,
    ) async {
      final t = received();
      await openDelivery(tester, t.rig);
      t.rig.server.dropResponseAfterCommit = 1;
      await sendBack(tester, t.order);
      expect(find.textContaining('Ответ сервера не получен'), findsOneWidget);
      expect(t.rig.store.backing.single.action, 'supplier_return_create');
      expect(t.rig.server.ledger.supplierReturnsRecorded, 1);
      await tester.pumpWidget(const SizedBox());
      await t.rig.launch(tester);
      await settle(tester);
      expect(key('pending-banner'), findsNothing);
      expect(t.rig.server.ledger.supplierReturnsRecorded, 1);
      expect(t.rig.server.ledger.quantityOf(idOf(t.pad), warehouse), 7000);
    });

    testWidgets('a text field keeps its own name for a screen reader', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final t = received();
      await openDelivery(tester, t.rig);
      expect(fieldNames(tester), ['Вернуть', 'Причина возврата (обязательно)']);
      handle.dispose();
    });

    testWidgets('the button is only for those who may send goods back', (
      tester,
    ) async {
      final t = received();
      t.rig.server.permissions = [
        'catalog.view',
        'stock.view',
        'location.view',
        'purchasing.view',
        'supplier.view',
      ];
      await openPurchasing(tester, t.rig);
      expect(key('purchasing-returns'), findsNothing);
      await openOrder(tester, 'PO-0001');
      expect(key('od-return-1'), findsNothing);
    });
  });

  group('what to buy again', () {
    testWidgets('nothing is listed while everything is above its minimum', (
      tester,
    ) async {
      final t = ordered();
      await openPurchasing(tester, t.rig);
      await tapKey(tester, 'purchasing-reorder');
      await settle(tester);
      expect(key('reorder-empty'), findsOneWidget);
    });

    testWidgets('a product below its minimum becomes a draft order', (
      tester,
    ) async {
      final t = ordered();
      final ledger = t.rig.server.ledger;
      final id = idOf(t.pad);
      ledger.seedStock(id, warehouse, '4', '50.00');
      ledger.reorderLevels[id] = [
        {'location': warehouse, 'minimum': 10000, 'target': 30000},
      ];
      await openPurchasing(tester, t.rig);
      await tapKey(tester, 'purchasing-reorder');
      await settle(tester);
      // 4 on the shelf + 10 already ordered (the seeded order) = 14 >= 10: nothing to order
      expect(key('reorder-empty'), findsOneWidget);
      ledger.orders.first['status'] = 'cancelled';
      await goBack(tester);
      await tapKey(tester, 'purchasing-reorder');
      await settle(tester);
      expect(key('reorder-BP-1'), findsOneWidget);
      expect(
        find.textContaining('Предлагается заказать: 26 шт'),
        findsOneWidget,
      );
      await tester.tap(key('reorder-BP-1'));
      await tester.pump();
      await tapKey(tester, 'reorder-create');
      await settle(tester);
      // the order form opens with the suggestion; a person picks the supplier
      expect(tester.widget<TextField>(key('of-qty-0')).controller!.text, '26');
      expect(
        tester.widget<TextField>(key('of-cost-0')).controller!.text,
        '50,00',
      );
      await tapKey(tester, 'of-supplier');
      await settle(tester, ms: 400);
      await tester.tap(find.text('Ашхабад Запчасти').last);
      await settle(tester, ms: 400);
      await tapKey(tester, 'of-save');
      await settle(tester);
      final draft = ledger.orders.first;
      expect(draft['status'], 'draft');
      expect(draft['location'], warehouse);
      expect((draft['lines'] as List).single['quantity'], 26000);
      expect(find.text('Черновик'), findsWidgets);
    });

    testWidgets('the reorder list is only for those who may see it', (
      tester,
    ) async {
      final t = ordered();
      t.rig.server.permissions = [
        'catalog.view',
        'stock.view',
        'location.view',
        'purchasing.view',
      ];
      await openPurchasing(tester, t.rig);
      expect(key('purchasing-reorder'), findsNothing);
    });
  });
}
