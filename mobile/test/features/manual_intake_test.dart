import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/real_rig.dart';
import 'intake_test.dart'
    show intakeRig, openIntake, scanByKeyboard, sendIntake;

String textValue(WidgetTester tester, String id) =>
    tester.widget<TextField>(key(id)).controller!.text;

void main() {
  for (final lang in ['ru', 'tk']) {
    testWidgets('manual name-only product has no invented barcode ($lang)', (
      tester,
    ) async {
      final t = intakeRig();
      await openIntake(tester, t.rig);
      if (lang == 'tk') {
        await goBack(tester);
        await tapKey(tester, 'language-tk');
        await settle(tester);
        await tapKey(tester, 'stock-intake');
        await settle(tester);
      }
      await tapKey(tester, 'intake-manual');
      await settle(tester);
      expect(textValue(tester, 'intake-new-sku'), '');
      await tester.enterText(key('intake-new-name'), 'Фильтр ÄŇŞ без кода');
      await tester.enterText(key('intake-edit-qty'), '50');
      await tapKey(tester, 'intake-new-save');
      await settle(tester);
      final p = t.rig.server.productsData.last;
      expect(p['barcodes'], isEmpty);
      expect(p['name'], 'Фильтр ÄŇŞ без кода');
      expect(p['sku'], startsWith('M-'));
      expect(p['warranty_months'], 0);
      expect(t.rig.server.log.where((s) => s.contains('barcodes/')), isEmpty);
      if (lang == 'ru') {
        await sendIntake(tester);
        expect(t.rig.server.ledger.intakes.single['lines'], [
          {'product': p['id'], 'quantity': '50.000'},
        ]);
      }
    });
  }

  testWidgets(
    'optional warranty and expiry validate, survive restart and post the batch date',
    (tester) async {
      final t = intakeRig();
      await openIntake(tester, t.rig);
      await tapKey(tester, 'intake-manual');
      await settle(tester);
      await tester.enterText(key('intake-new-name'), 'Lubricant');
      await tester.enterText(key('intake-warranty-months'), '121');
      await tester.enterText(key('intake-expiry-date'), '31.02.2030');
      await tapKey(tester, 'intake-new-save');
      await settle(tester);
      expect(t.rig.server.productWrites, 0);
      await tester.enterText(key('intake-warranty-months'), '12');
      await tapKey(tester, 'intake-new-save');
      await settle(tester);
      expect(
        t.rig.server.productWrites,
        0,
      ); // impossible date never normalizes into March
      await tester.enterText(key('intake-expiry-date'), '30.06.2030');
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
      final add = find.byWidgetPredicate(
        (w) =>
            w.key is ValueKey<String> &&
            (w.key! as ValueKey<String>).value.startsWith('intake-add-manual-'),
      );
      await tester.ensureVisible(add);
      await tester.tap(add);
      await settle(tester);
      expect(textValue(tester, 'intake-new-name'), 'Lubricant');
      expect(textValue(tester, 'intake-warranty-months'), '12');
      expect(textValue(tester, 'intake-expiry-date'), '30.06.2030');
      await tapKey(tester, 'intake-new-save');
      await settle(tester);
      expect(t.rig.server.productsData.last['warranty_months'], 12);
      await sendIntake(tester);
      final line =
          (t.rig.server.ledger.intakes.single['lines'] as List).single as Map;
      expect(line['expiry_date'], '2030-06-30');
    },
  );

  testWidgets(
    'known warranty is prefilled and an explicitly cleared expiry stays empty',
    (tester) async {
      final t = intakeRig();
      t.bushing['warranty_months'] = 18;
      await openIntake(tester, t.rig);
      await scanByKeyboard(tester, 'MB-025153', review: true);
      expect(textValue(tester, 'intake-warranty-months'), '18');
      await tester.enterText(key('intake-expiry-date'), '30.06.2030');
      await settle(tester);
      await tapKey(tester, 'intake-expiry-clear');
      await tapKey(tester, 'intake-edit-save');
      await settle(tester);
      await sendIntake(tester);
      expect(
        (t.rig.server.ledger.intakes.single['lines'] as List).single,
        isNot(contains('expiry_date')),
      );
      expect(t.bushing['warranty_months'], 18);
    },
  );
}
