import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/real_rig.dart';
import 'catalog_test.dart' show seedProduct;

/// What the server sends for a product that still needs something.
Map<String, dynamic> waiting(
  Map<String, dynamic> product, {
  bool price = false,
  bool cost = true,
  String stock = '3.000',
  String sold = '2.000',
}) => {
  'id': product['id'],
  'sku': product['sku'],
  'name': product['name'],
  'unit_symbol': 'шт',
  'unit_decimals': 0,
  'price_amount': price ? '0.00' : '${product['price_amount']}',
  'price_currency': 'TMT',
  'missing_price': price,
  'missing_cost': cost,
  'stock_without_cost': cost ? stock : '0.000',
  'sold_without_cost': cost ? sold : '0.000',
};

Future<void> openList(WidgetTester tester, RealRig rig) async {
  await rig.launchSignedIn(tester);
  await tapKey(tester, 'dash-to-complete');
  await settle(tester);
}

void main() {
  group('the dashboard card', () {
    testWidgets('counts what is missing and opens the list', (tester) async {
      final rig = RealRig();
      final pad = seedProduct(rig.server, sku: 'BP-1', name: 'Колодки');
      rig.server.toCompleteData.add(waiting(pad));
      await openList(tester, rig);
      expect(find.text('Дополнить данные'), findsWidgets);
      expect(key('complete-BP-1'), findsOneWidget);
    });

    testWidgets('is not there when nothing is missing', (tester) async {
      final rig = RealRig();
      await rig.launchSignedIn(tester);
      expect(key('dash-to-complete'), findsNothing);
    });

    testWidgets('is not offered to a seller', (tester) async {
      final rig = RealRig();
      final pad = seedProduct(rig.server, sku: 'BP-1', name: 'Колодки');
      rig.server.toCompleteData.add(waiting(pad));
      rig.server.role = 'sales';
      rig.server.permissions = [
        'catalog.view',
        'sales.view',
        'sales.create',
        'dashboard.view',
      ];
      await rig.launchSignedIn(tester);
      expect(key('dash-to-complete'), findsNothing);
    });

    testWidgets('the catalog page has a button for the same list', (
      tester,
    ) async {
      final rig = RealRig();
      final pad = seedProduct(rig.server, sku: 'BP-1', name: 'Колодки');
      rig.server.toCompleteData.add(waiting(pad));
      await rig.launchSignedIn(tester);
      await tapKey(tester, 'nav-products');
      await settle(tester);
      await tapKey(tester, 'catalog-to-complete');
      await settle(tester);
      expect(key('complete-BP-1'), findsOneWidget);
    });

    testWidgets('a role that cannot manage the catalog has no such button', (
      tester,
    ) async {
      final rig = RealRig();
      rig.server.role = 'sales';
      rig.server.permissions = ['catalog.view', 'dashboard.view'];
      await rig.launchSignedIn(tester);
      await tapKey(tester, 'nav-products');
      await settle(tester);
      expect(key('catalog-to-complete'), findsNothing);
    });
  });

  group('the list', () {
    testWidgets('shows what is missing, how much stock and sales wait', (
      tester,
    ) async {
      final rig = RealRig();
      final pad = seedProduct(rig.server, sku: 'BP-1', name: 'Колодки');
      final oil = seedProduct(rig.server, sku: 'OIL-1', name: 'Масло');
      rig.server.toCompleteData
        ..add(waiting(pad))
        ..add(waiting(oil, price: true, cost: false));
      await openList(tester, rig);
      expect(find.text('Нет закупочной цены'), findsOneWidget);
      expect(find.text('Нет цены продажи'), findsOneWidget);
      expect(find.text('На складе без закупочной цены: 3 шт'), findsOneWidget);
      expect(find.text('Продано без закупочной цены: 2 шт'), findsOneWidget);
      // each row asks only for what is missing
      expect(key('complete-cost-BP-1'), findsOneWidget);
      expect(key('complete-price-BP-1'), findsNothing);
      expect(key('complete-price-OIL-1'), findsOneWidget);
      expect(key('complete-cost-OIL-1'), findsNothing);
    });

    testWidgets(
      'a cost is sent and the row goes away, then the list says all is done',
      (tester) async {
        final rig = RealRig();
        final pad = seedProduct(rig.server, sku: 'BP-1', name: 'Колодки');
        rig.server.toCompleteData.add(waiting(pad));
        await openList(tester, rig);
        await tester.enterText(key('complete-cost-BP-1'), '60,50');
        await tapKey(tester, 'complete-save-BP-1');
        await settle(tester);
        expect(rig.server.costsSet, [(pad['id'] as String, '60.50')]);
        expect(key('complete-BP-1'), findsNothing);
        expect(key('complete-none'), findsOneWidget);
        expect(find.text('Сохранено.'), findsOneWidget);
      },
    );

    testWidgets('a price and a cost are both saved from one row', (
      tester,
    ) async {
      final rig = RealRig();
      final pad = seedProduct(rig.server, sku: 'BP-1', name: 'Колодки');
      rig.server.toCompleteData.add(waiting(pad, price: true));
      await openList(tester, rig);
      await tester.enterText(key('complete-price-BP-1'), '100');
      await tester.enterText(key('complete-cost-BP-1'), '60');
      await tapKey(tester, 'complete-save-BP-1');
      await settle(tester);
      expect(rig.server.costsSet, [(pad['id'] as String, '60.00')]);
      expect(pad['price_amount'], '100.00');
      expect(key('complete-none'), findsOneWidget);
    });

    testWidgets('only the cost: the row stays and still asks for the price', (
      tester,
    ) async {
      final rig = RealRig();
      final pad = seedProduct(rig.server, sku: 'BP-1', name: 'Колодки');
      rig.server.toCompleteData.add(waiting(pad, price: true));
      await openList(tester, rig);
      await tester.enterText(key('complete-cost-BP-1'), '60');
      await tapKey(tester, 'complete-save-BP-1');
      await settle(tester);
      expect(rig.server.costsSet.length, 1);
      expect(key('complete-BP-1'), findsOneWidget);
      expect(key('complete-cost-BP-1'), findsNothing);
      expect(key('complete-price-BP-1'), findsOneWidget);
    });

    testWidgets('a cost of zero is allowed, a price of zero is not', (
      tester,
    ) async {
      final rig = RealRig();
      final pad = seedProduct(rig.server, sku: 'BP-1', name: 'Колодки');
      rig.server.toCompleteData.add(waiting(pad, price: true));
      await openList(tester, rig);
      await tester.enterText(key('complete-price-BP-1'), '0');
      await tester.enterText(key('complete-cost-BP-1'), '0');
      await tapKey(tester, 'complete-save-BP-1');
      await settle(tester);
      expect(find.text('Некорректное значение.'), findsOneWidget);
      expect(
        rig.server.costsSet,
        isEmpty,
        reason: 'nothing is sent while a field is wrong',
      );
      await tester.enterText(key('complete-price-BP-1'), '10');
      await tapKey(tester, 'complete-save-BP-1');
      await settle(tester);
      expect(rig.server.costsSet, [(pad['id'] as String, '0.00')]);
    });

    testWidgets('letters and a missing amount are refused before sending', (
      tester,
    ) async {
      final rig = RealRig();
      final pad = seedProduct(rig.server, sku: 'BP-1', name: 'Колодки');
      rig.server.toCompleteData.add(waiting(pad));
      await openList(tester, rig);
      await tapKey(tester, 'complete-save-BP-1');
      await settle(tester);
      expect(
        find.text('Введите цену продажи или закупочную цену.'),
        findsOneWidget,
      );
      await tester.enterText(key('complete-cost-BP-1'), '12.345');
      await tapKey(tester, 'complete-save-BP-1');
      await settle(tester);
      expect(find.text('Некорректное значение.'), findsOneWidget);
      expect(rig.server.costsSet, isEmpty);
    });

    testWidgets('a server refusal is shown on the row and nothing disappears', (
      tester,
    ) async {
      final rig = RealRig();
      final pad = seedProduct(rig.server, sku: 'BP-1', name: 'Колодки');
      rig.server.toCompleteData.add(waiting(pad));
      rig.server.costFails = 'permission_denied';
      await openList(tester, rig);
      await tester.enterText(key('complete-cost-BP-1'), '60');
      await tapKey(tester, 'complete-save-BP-1');
      await settle(tester);
      expect(key('complete-error-BP-1'), findsOneWidget);
      expect(key('complete-BP-1'), findsOneWidget);
    });

    testWidgets('an empty list says everything is filled in', (tester) async {
      final rig = RealRig();
      final pad = seedProduct(rig.server, sku: 'BP-1', name: 'Колодки');
      rig.server.toCompleteData.add(waiting(pad));
      await openList(tester, rig);
      rig.server.toCompleteData.clear();
      await goBack(tester);
      await tapKey(tester, 'nav-products');
      await settle(tester);
      await tapKey(tester, 'catalog-to-complete');
      await settle(tester);
      expect(key('complete-none'), findsOneWidget);
    });

    for (final size in [const Size(360, 800), const Size(800, 1100)]) {
      testWidgets('it fits $size with long names and doubled text', (
        tester,
      ) async {
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final rig = RealRig();
        final pad = seedProduct(
          rig.server,
          sku: 'LONG-ARTICLE-NUMBER-1',
          name: 'Очень длинное название товара для проверки переноса строк',
        );
        rig.server.toCompleteData.add(waiting(pad, price: true));
        await rig.launch(tester, size: size);
        await rig.signIn(tester);
        if (size.width < 600) {
          await tester.tap(find.byTooltip('Меню'));
          await settle(tester, ms: 400);
          await tester.scrollUntilVisible(
            key('nav-products'),
            200,
            scrollable: find.descendant(
              of: find.byType(Drawer),
              matching: find.byType(Scrollable),
            ),
          );
        }
        await tapKey(tester, 'nav-products');
        await settle(tester);
        if (size.width < 600) {
          // On a phone this action sits behind the "more" menu.
          await tapKey(tester, 'catalog-more');
          await settle(tester);
        }
        await tapKey(tester, 'catalog-to-complete');
        await settle(tester);
        expect(tester.takeException(), isNull);
        // With doubled text the explanation fills the first screen: scroll to the row.
        await tester.scrollUntilVisible(
          key('complete-LONG-ARTICLE-NUMBER-1'),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        expect(key('complete-LONG-ARTICLE-NUMBER-1'), findsOneWidget);
      });
    }
  });

  group('honest profit in the reports', () {
    testWidgets('the summary says what the profit leaves out', (tester) async {
      final rig = RealRig();
      rig.server.reports.withoutCost = '200.00';
      rig.server.reports.withoutCostLines = 2;
      await rig.launchSignedIn(tester);
      await tapKey(tester, 'nav-reports');
      await settle(tester);
      expect(key('rep-without-cost-note'), findsOneWidget);
      expect(
        find.textContaining('В прибыль не вошли продажи без закупочной цены'),
        findsOneWidget,
      );
      await tapKey(tester, 'reports-tab-sales');
      await settle(tester);
      expect(key('rep-sales-without-cost-note'), findsOneWidget);
    });

    testWidgets('no note when every sale has a known cost', (tester) async {
      final rig = RealRig();
      await rig.launchSignedIn(tester);
      await tapKey(tester, 'nav-reports');
      await settle(tester);
      expect(key('rep-without-cost-note'), findsNothing);
    });

    testWidgets('the dashboard says it too, to people who see profit', (
      tester,
    ) async {
      final rig = RealRig();
      rig.server.reports.withoutCost = '120.00';
      await rig.launchSignedIn(tester);
      expect(key('dash-without-cost-note'), findsOneWidget);
    });
  });
}
