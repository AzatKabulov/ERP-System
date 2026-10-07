import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/real_rig.dart';
import 'catalog_test.dart' show openCatalog, seedProduct;
import 'stock_ops_test.dart' show fieldNames;

Future<void> openProduct(
  WidgetTester tester,
  RealRig rig, {
  int? returnDays,
}) async {
  seedProduct(
    rig.server,
    sku: 'BP-100',
    name: 'Тормозные колодки',
    returnDays: returnDays,
  );
  await openCatalog(tester, rig);
  await tapKey(tester, 'product-BP-100');
  await settle(tester);
}

void main() {
  group('return window on the product', () {
    testWidgets('no limit, a number of days, or never', (tester) async {
      final rig = RealRig();
      await openProduct(tester, rig);
      expect(find.text('Возврат без ограничения срока'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      final rig2 = RealRig();
      await openProduct(tester, rig2, returnDays: 14);
      expect(find.text('Возврат в течение 14 дн.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      final rig3 = RealRig();
      await openProduct(tester, rig3, returnDays: 0);
      expect(find.text('Этот товар не принимается обратно'), findsOneWidget);
    });

    testWidgets('the owner types the days by hand and can clear them', (
      tester,
    ) async {
      final rig = RealRig();
      await openProduct(tester, rig);
      await tapKey(tester, 'pd-edit');
      await settle(tester);
      await tester.ensureVisible(key('pf-return-days'));
      await tester.enterText(key('pf-return-days'), '30');
      await tapKey(tester, 'pf-save');
      await settle(tester);
      expect(rig.server.productsData.single['return_days'], 30);
      expect(find.text('Возврат в течение 30 дн.'), findsOneWidget);
      await settle(
        tester,
        ms: 5000,
      ); // the "saved" notice would cover the button
      await tapKey(tester, 'pd-edit');
      await settle(tester);
      await tester.ensureVisible(key('pf-return-days'));
      await tester.enterText(key('pf-return-days'), '');
      await tapKey(tester, 'pf-save');
      await settle(tester);
      expect(rig.server.productsData.single['return_days'], isNull);
      expect(find.text('Возврат без ограничения срока'), findsOneWidget);
    });

    testWidgets('a number out of range is refused on the form', (tester) async {
      final rig = RealRig();
      await openProduct(tester, rig);
      await tapKey(tester, 'pd-edit');
      await settle(tester);
      await tester.ensureVisible(key('pf-return-days'));
      await tester.enterText(key('pf-return-days'), '5000');
      await tapKey(tester, 'pf-save');
      await settle(tester);
      expect(find.text('Значение вне допустимого диапазона.'), findsOneWidget);
      expect(key('pf-save'), findsOneWidget); // still on the form
    });
  });

  group('minimum and target stock', () {
    testWidgets('the owner sets them per place and sees them on the product', (
      tester,
    ) async {
      final rig = RealRig();
      await openProduct(tester, rig);
      expect(key('pd-reorder-none'), findsOneWidget);
      await tester.ensureVisible(key('pd-reorder-edit'));
      await tapKey(tester, 'pd-reorder-edit');
      await settle(tester);
      await tester.enterText(key('rl-min-l-1'), '10');
      await tester.pump();
      expect(find.text('Обязательное поле.'), findsOneWidget); // target missing
      await tester.enterText(key('rl-target-l-1'), '5');
      await tester.pump();
      expect(find.text('Цель не может быть меньше минимума.'), findsOneWidget);
      await tester.enterText(key('rl-target-l-1'), '30');
      await tester.pump();
      await tapKey(tester, 'rl-save');
      await settle(tester);
      expect(rig.server.ledger.reorderLevels['p-seed-1'], [
        {'location': 'l-1', 'minimum': 10000, 'target': 30000},
      ]);
      expect(find.text('Уровни сохранены.'), findsOneWidget);
      expect(
        find.text('Esasy dükan: минимум 10 шт, цель 30 шт'),
        findsOneWidget,
      );
    });

    testWidgets('every field of the levels page keeps its own name', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final rig = RealRig();
      await openProduct(tester, rig);
      await tester.ensureVisible(key('pd-reorder-edit'));
      await tapKey(tester, 'pd-reorder-edit');
      await settle(tester);
      expect(fieldNames(tester).take(2), ['Минимум', 'Цель']);
      handle.dispose();
    });

    testWidgets('a seller sees the levels but cannot change them', (
      tester,
    ) async {
      final rig = RealRig();
      rig.server.permissions = ['catalog.view', 'stock.view', 'location.view'];
      await openProduct(tester, rig);
      expect(key('pd-reorder-none'), findsOneWidget);
      expect(key('pd-reorder-edit'), findsNothing);
    });
  });
}
