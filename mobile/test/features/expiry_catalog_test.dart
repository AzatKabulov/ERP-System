import 'package:flutter_test/flutter_test.dart';

import '../support/real_rig.dart';
import 'catalog_test.dart' show seedProduct, openCatalog, typeSearch;

void main() {
  testWidgets(
    'gallery and scanned search show remaining quantity and batch warnings',
    (tester) async {
      final rig = RealRig();
      final p = seedProduct(
        rig.server,
        sku: 'EXP-1',
        name: 'Oil',
        barcodes: ['12345'],
      );
      p['stock'] = {'on_hand': '50.000', 'minimum': '0.000'};
      p['expiry'] = {
        'date': '2026-11-01',
        'quantity': '12.000',
        'status': 'soon',
      };
      await openCatalog(tester, rig);
      expect(find.text('Остаток: 50 шт'), findsOneWidget);
      expect(find.text('До 01.11.2026: 12 шт'), findsOneWidget);
      expect(key('catalog-expiry-alert'), findsOneWidget);
      await typeSearch(tester, '12345');
      expect(find.text('Остаток: 50 шт'), findsOneWidget);
      await tapKey(tester, 'product-EXP-1');
      await settle(tester);
      expect(find.text('Остаток: 50 шт'), findsOneWidget);
    },
  );

  testWidgets('expiry filters combine with search and can be cleared', (
    tester,
  ) async {
    final rig = RealRig();
    final soon = seedProduct(rig.server, sku: 'SOON', name: 'Soon oil');
    soon['expiry'] = {
      'date': '2026-11-01',
      'quantity': '2.000',
      'status': 'soon',
    };
    final old = seedProduct(rig.server, sku: 'OLD', name: 'Old oil');
    old['expiry'] = {
      'date': '2026-10-01',
      'quantity': '3.000',
      'status': 'expired',
    };
    seedProduct(rig.server, sku: 'UNKNOWN', name: 'Unknown date');
    await openCatalog(tester, rig);
    await tapKey(tester, 'catalog-expiry-soon');
    await settle(tester);
    expect(key('product-SOON'), findsOneWidget);
    expect(key('product-OLD'), findsNothing);
    await typeSearch(tester, 'absent');
    expect(key('product-SOON'), findsNothing);
    await typeSearch(tester, '');
    await tapKey(tester, 'catalog-expiry-expired');
    await settle(tester);
    expect(key('product-OLD'), findsOneWidget);
    expect(key('product-SOON'), findsNothing);
    await tapKey(tester, 'catalog-expiry-expired');
    await settle(tester);
    expect(key('product-UNKNOWN'), findsOneWidget);
  });
}
