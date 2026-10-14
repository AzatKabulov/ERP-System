import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/real_rig.dart';
import 'catalog_test.dart' show seedProduct;

const store = 'l-1';

Future<void> navigate(WidgetTester tester, String navKey, Size size) async {
  if (size.width < 600) {
    await tester.tap(find.byTooltip('Меню'));
    await settle(tester, ms: 400);
    await tester.scrollUntilVisible(
      key(navKey),
      200,
      scrollable: find.descendant(
        of: find.byType(Drawer),
        matching: find.byType(Scrollable),
      ),
    );
  }
  await tapKey(tester, navKey);
  await settle(tester);
}

void main() {
  for (final size in [const Size(360, 800), const Size(800, 1100)]) {
    testWidgets('stock screens fit at $size with doubled text', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final rig = RealRig();
      final pad = seedProduct(
        rig.server,
        sku: 'BP-1',
        name: 'Тормозные колодки передние для длинного названия',
        cost: '50.00',
      );
      rig.server.ledger.seedStock(pad['id'] as String, store, '10', '50.00');
      await rig.launch(tester, size: size);
      await rig.signIn(tester);
      expect(tester.takeException(), isNull);

      // stock list, history, and both entry forms
      await navigate(tester, 'nav-inventory', size);
      expect(tester.takeException(), isNull);
      await tapKey(tester, 'stock-history');
      await settle(tester);
      expect(tester.takeException(), isNull);
      await goBack(tester);
      await tapKey(tester, 'stock-adjust');
      await settle(tester);
      await tapKey(tester, 'entry-add-line');
      await settle(tester, ms: 600);
      expect(tester.takeException(), isNull);
      await tester.tap(key('picker-BP-1'));
      await settle(tester, ms: 400);
      expect(tester.takeException(), isNull);
      await goBack(tester);
      await tester.tap(find.text('Подтвердить'));
      await settle(tester, ms: 400);
    });
  }
}
