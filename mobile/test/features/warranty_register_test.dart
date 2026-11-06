import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/real_rig.dart';
import 'catalog_test.dart' show seedProduct;

const store = 'l-1';

/// One entry of the register as the server answers it.
Map<String, dynamic> entry({
  required String saleId,
  required String lineId,
  required String name,
  String status = 'active',
  int number = 1,
  String customer = '',
  int daysLeft = 90,
  int openClaims = 0,
  String starts = '2026-10-01',
  String until = '2027-01-01',
}) => {
  'sale_line': lineId,
  'sale': saleId,
  'sale_number': number,
  'product': 'p-1',
  'sku': 'BP-1',
  'name': name,
  'quantity': '1.000',
  'returned': status == 'returned' ? '1.000' : '0.000',
  'customer_name': customer,
  'customer_phone': '',
  'warranty_months': 3,
  'warranty_terms': '',
  'starts': starts,
  'until': until,
  'days_left': daysLeft,
  'status': status,
  'open_claims': openClaims,
};

void main() {
  ({RealRig rig, Map<String, dynamic> sale}) rigWithRegister() {
    final rig = RealRig();
    final pad = seedProduct(
      rig.server,
      sku: 'BP-1',
      name: 'Наушники',
      warrantyMonths: 3,
    );
    final id = pad['id'] as String;
    rig.server.ledger.seedStock(id, store, '10', '50.00');
    final sale = rig.server.ledger.seedSale(
      productId: id,
      locationId: store,
      quantity: '1',
      price: '100.00',
    );
    final saleId = sale['id'] as String;
    final lineId = (sale['lines'] as List).first['id'] as String;
    rig.server.office.register.addAll([
      entry(
        saleId: saleId,
        lineId: lineId,
        name: 'Наушники',
        customer: 'Аман',
        number: 1,
      ),
      entry(
        saleId: 'old-sale',
        lineId: 'old-line',
        name: 'Колонка',
        status: 'expired',
        number: 2,
        daysLeft: -12,
        until: '2026-10-19',
      ),
      entry(
        saleId: 'back-sale',
        lineId: 'back-line',
        name: 'Зарядка',
        status: 'returned',
        number: 3,
      ),
    ]);
    return (rig: rig, sale: sale);
  }

  Future<void> openRegister(WidgetTester tester, RealRig rig) async {
    await rig.launchSignedIn(tester);
    await tapKey(tester, 'nav-warranties');
    await settle(tester);
  }

  testWidgets('the page opens on the goods sold with a warranty, with dates', (
    tester,
  ) async {
    final t = rigWithRegister();
    await openRegister(tester, t.rig);
    expect(key('warranty-tab-sold'), findsOneWidget);
    // the default filter is "in force": the earlier sale is listed, the expired and returned are not
    expect(find.text('Наушники'), findsOneWidget);
    expect(find.text('Колонка'), findsNothing);
    expect(find.text('Зарядка'), findsNothing);
    expect(find.textContaining('Гарантия до 01.01.2027'), findsOneWidget);
    expect(find.textContaining('Куплено 01.10.2026'), findsOneWidget);
    expect(find.text('Осталось 90 дн.'), findsOneWidget);
    expect(find.text('Аман'), findsNothing); // shown after the receipt number
    expect(find.textContaining('S-000001 · Аман'), findsOneWidget);
  });

  testWidgets('the filters show expired and returned goods and their counts', (
    tester,
  ) async {
    final t = rigWithRegister();
    await openRegister(tester, t.rig);
    expect(find.textContaining('Действует · 1'), findsOneWidget);
    expect(find.textContaining('Истекла · 1'), findsOneWidget);
    await tapKey(tester, 'warranty-sold-expired');
    await settle(tester);
    expect(find.text('Колонка'), findsOneWidget);
    expect(find.text('Истекла 12 дн. назад'), findsOneWidget);
    await tapKey(tester, 'warranty-sold-returned');
    await settle(tester);
    expect(find.text('Зарядка'), findsOneWidget);
    expect(find.text('Товар возвращён — гарантии нет'), findsOneWidget);
    await tapKey(tester, 'warranty-sold-all');
    await settle(tester);
    expect(find.text('Наушники'), findsOneWidget);
    expect(find.text('Колонка'), findsOneWidget);
    expect(find.text('Зарядка'), findsOneWidget);
  });

  testWidgets('searching by the customer narrows the list', (tester) async {
    final t = rigWithRegister();
    await openRegister(tester, t.rig);
    await tapKey(tester, 'warranty-sold-all');
    await settle(tester);
    await tester.enterText(key('warranty-search'), 'аман');
    await tester.pump(const Duration(milliseconds: 500));
    await settle(tester);
    expect(find.text('Наушники'), findsOneWidget);
    expect(find.text('Колонка'), findsNothing);
    await tester.enterText(key('warranty-search'), 'нет такого');
    await tester.pump(const Duration(milliseconds: 500));
    await settle(tester);
    expect(key('warranty-sold-nomatch'), findsOneWidget);
  });

  testWidgets('taking a claim opens the form for that sale', (tester) async {
    final t = rigWithRegister();
    await openRegister(tester, t.rig);
    final lineId = (t.sale['lines'] as List).first['id'] as String;
    await tapKey(tester, 'warranty-accept-$lineId');
    await settle(tester);
    expect(key('wn-sale'), findsOneWidget); // the sale is known: no search step
  });

  testWidgets('an expired warranty can only be taken by an owner or manager', (
    tester,
  ) async {
    final t = rigWithRegister();
    // the owner sees the button on an expired line, and no button on a returned one
    await openRegister(tester, t.rig);
    await tapKey(tester, 'warranty-sold-all');
    await settle(tester);
    expect(key('warranty-accept-old-line'), findsOneWidget);
    expect(key('warranty-accept-back-line'), findsNothing);
  });

  testWidgets('a seller cannot take a claim on an expired warranty', (
    tester,
  ) async {
    final t = rigWithRegister();
    t.rig.server.role = 'sales';
    t.rig.server.permissions = [
      'warranty.view',
      'warranty.open',
      'sales.view',
      'catalog.view',
      'dashboard.view',
    ];
    await openRegister(tester, t.rig);
    await tapKey(tester, 'warranty-sold-all');
    await settle(tester);
    expect(key('warranty-accept-old-line'), findsNothing);
    final lineId = (t.sale['lines'] as List).first['id'] as String;
    expect(key('warranty-accept-$lineId'), findsOneWidget);
  });

  testWidgets('an empty register explains where the entries come from', (
    tester,
  ) async {
    final rig = RealRig();
    await openRegister(tester, rig);
    await tapKey(tester, 'warranty-sold-all');
    await settle(tester);
    expect(key('warranty-sold-empty'), findsOneWidget);
    expect(
      find.textContaining('появится здесь сразу после продажи'),
      findsOneWidget,
    );
  });

  for (final size in [const Size(360, 800), const Size(800, 1100)]) {
    testWidgets('the register fits $size with doubled text', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final t = rigWithRegister();
      await t.rig.launch(tester, size: size);
      await t.rig.signIn(tester);
      if (size.width < 600) {
        await tester.tap(find.byTooltip('Меню'));
        await settle(tester, ms: 400);
        await tester.scrollUntilVisible(
          key('nav-warranties'),
          200,
          scrollable: find.descendant(
            of: find.byType(Drawer),
            matching: find.byType(Scrollable),
          ),
        );
      }
      await tapKey(tester, 'nav-warranties');
      await settle(tester);
      expect(tester.takeException(), isNull);
      await tapKey(tester, 'warranty-sold-all');
      await settle(tester);
      expect(tester.takeException(), isNull);
    });
  }
}
