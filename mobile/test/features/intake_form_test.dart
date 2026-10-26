import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../support/real_rig.dart';
import 'intake_test.dart'
    show intakeRig, openIntake, scanByKeyboard, sendIntake;
import 'stock_ops_test.dart' show idOf;

String value(WidgetTester tester, String id) =>
    tester.widget<TextField>(key(id)).controller!.text;
const code = '3337875597470';

void main() {
  testWidgets('one form prefills online data while leaving both prices blank', (
    tester,
  ) async {
    final t = intakeRig();
    t.rig.server.externalInfo[code] = {
      'name': 'Oil filter',
      'brand': 'Parts maker',
      'quantity': '1 pc',
      'category': 'Filters',
    };
    await openIntake(tester, t.rig);
    await scanByKeyboard(tester, code, review: true);
    expect(value(tester, 'intake-new-name'), 'Parts maker Oil filter 1 pc');
    expect(value(tester, 'intake-new-brand'), 'Parts maker');
    expect(value(tester, 'intake-new-category'), 'Filters');
    expect(value(tester, 'intake-new-price'), '');
    expect(value(tester, 'intake-edit-cost'), '');
    expect(value(tester, 'intake-edit-qty'), '1');
    expect(t.rig.server.productWrites, 0);
    await tester.enterText(key('intake-edit-qty'), '50');
    await tester.enterText(key('intake-edit-cost'), '60,25');
    await tester.enterText(key('intake-new-price'), '100,50');
    await tapKey(tester, 'intake-new-save');
    await settle(tester);
    final p = t.rig.server.productsData.last;
    expect(p['price_amount'], '100.50');
    expect(p['brand'], t.rig.server.brandsData.last['id']);
    expect(p['category'], t.rig.server.categoriesData.last['id']);
    expect(t.rig.server.ledger.quantityOf(idOf(p), 'l-1'), 0);
    await sendIntake(tester);
    expect(t.rig.server.ledger.quantityOf(idOf(p), 'l-1'), 50000);
    expect(t.rig.server.ledger.movements.last['unit_cost'], '60.25');
  });

  testWidgets(
    'a late internet answer does not replace typed or cleared fields or prices',
    (tester) async {
      final t = intakeRig();
      final wait = Completer<void>();
      t.rig.server.externalWait = wait.future;
      t.rig.server.externalInfo[code] = {
        'name': 'Online name',
        'brand': 'Online brand',
        'category': 'Online category',
      };
      await openIntake(tester, t.rig);
      await scanByKeyboard(tester, code, review: true);
      await tester.enterText(key('intake-new-name'), 'My filter');
      await tester.enterText(key('intake-new-brand'), 'Temporary');
      await tester.enterText(key('intake-new-brand'), '');
      await tester.enterText(key('intake-new-price'), '120');
      await tester.enterText(key('intake-edit-cost'), '75');
      wait.complete();
      await settle(tester);
      expect(value(tester, 'intake-new-name'), 'My filter');
      expect(value(tester, 'intake-new-brand'), '');
      expect(value(tester, 'intake-new-category'), 'Online category');
      expect(value(tester, 'intake-new-price'), '120');
      expect(value(tester, 'intake-edit-cost'), '75');
      expect(t.rig.server.productWrites, 0);
    },
  );

  testWidgets('invalid money and a refused save keep the editable form', (
    tester,
  ) async {
    final t = intakeRig();
    await openIntake(tester, t.rig);
    await scanByKeyboard(tester, 'FILTER-1', review: true);
    await tester.enterText(key('intake-new-name'), 'Filter');
    await tester.enterText(key('intake-edit-qty'), '50');
    await tester.enterText(key('intake-new-price'), '1,234');
    await tapKey(tester, 'intake-new-save');
    await settle(tester);
    expect(t.rig.server.productWrites, 0);
    expect(key('intake-new-save'), findsOneWidget);
    await tester.enterText(key('intake-new-price'), '100');
    await tester.enterText(key('intake-edit-cost'), '75');
    t.rig.server.reachable = false;
    await tapKey(tester, 'intake-new-save');
    await settle(tester);
    expect(key('intake-new-error'), findsOneWidget);
    expect(value(tester, 'intake-edit-qty'), '50');
    expect(value(tester, 'intake-new-price'), '100');
    t.rig.server.reachable = true;
    await tapKey(tester, 'intake-new-save');
    await settle(tester);
    expect(
      t.rig.server.productsData.where((p) => p['sku'] == 'FILTER-1'),
      hasLength(1),
    );
    expect(t.rig.server.ledger.intakesPosted, 0);
  });

  testWidgets('the form restores unsaved fields after a restart', (
    tester,
  ) async {
    final t = intakeRig();
    await openIntake(tester, t.rig);
    await scanByKeyboard(tester, 'PART-XY', review: true);
    await tester.enterText(key('intake-new-name'), 'Фильтр ÄŇŞ');
    await tester.enterText(key('intake-new-brand'), 'Maker');
    await tester.enterText(key('intake-edit-qty'), '50');
    await tester.enterText(key('intake-edit-cost'), '45');
    await tester.enterText(key('intake-new-price'), '90');
    final saved = {
      for (final k in t.rig.prefs.getKeys()) k: t.rig.prefs.get(k)!,
    };
    await tester.pumpWidget(const SizedBox());
    await t.rig.launch(tester, prefsValues: saved);
    await settle(tester);
    await tapKey(tester, 'nav-inventory');
    await settle(tester);
    await tapKey(tester, 'stock-intake');
    await settle(tester);
    await tapKey(tester, 'intake-add-PART-XY');
    await settle(tester);
    expect(value(tester, 'intake-new-name'), 'Фильтр ÄŇŞ');
    expect(value(tester, 'intake-new-brand'), 'Maker');
    expect(value(tester, 'intake-edit-qty'), '50');
    expect(value(tester, 'intake-edit-cost'), '45');
    expect(value(tester, 'intake-new-price'), '90');
  });

  testWidgets(
    'known product keeps its catalog prices and history when money is blank',
    (tester) async {
      final t = intakeRig();
      await openIntake(tester, t.rig);
      await scanByKeyboard(tester, 'MB-025153', review: true);
      expect(value(tester, 'intake-new-name'), t.bushing['name']);
      expect(value(tester, 'intake-new-price'), '');
      expect(value(tester, 'intake-edit-cost'), '');
      await tester.enterText(key('intake-edit-qty'), '50');
      await tapKey(tester, 'intake-edit-save');
      await settle(tester);
      expect(t.rig.server.externalAsked, isEmpty);
      expect(t.rig.server.productWrites, 0);
      expect(t.rig.server.ledger.intakesPosted, 0);
    },
  );

  testWidgets(
    'a warehouse user can count known stock but cannot edit catalog or costs',
    (tester) async {
      final t = intakeRig();
      t.rig.server.permissions.removeWhere(
        (p) => ['catalog.manage', 'stock.cost.view'].contains(p),
      );
      await openIntake(tester, t.rig);
      await scanByKeyboard(tester, 'MB-025153', review: true);
      expect(key('intake-edit-cost'), findsNothing);
      expect(key('intake-new-price'), findsNothing);
      expect(tester.widget<TextField>(key('intake-new-name')).enabled, false);
      await tester.enterText(key('intake-edit-qty'), '50');
      await tapKey(tester, 'intake-edit-save');
      await settle(tester);
      await sendIntake(tester);
      expect(t.rig.server.ledger.quantityOf(idOf(t.bushing), 'l-1'), 50000);
      expect(t.rig.server.productWrites, 0);
    },
  );
}
