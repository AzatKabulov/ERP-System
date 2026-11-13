import 'package:flutter_test/flutter_test.dart';

import '../support/real_rig.dart';
import 'catalog_test.dart' show openCatalog, seedProduct;

void main() {
  group('one business is one shop', () {
    testWidgets('with a single place the header shows its name, not a menu', (
      tester,
    ) async {
      final rig = RealRig();
      final locations =
          (rig.server.me['memberships'] as List).first['locations'] as List;
      locations.removeLast(); // only "Esasy dükan" is left
      await rig.launchSignedIn(tester);
      expect(key('location-selector'), findsNothing);
      expect(key('location-label'), findsOneWidget);
      expect(find.text('Esasy dükan'), findsWidgets);
      // moving goods between places needs two places
      await tapKey(tester, 'nav-inventory');
      await settle(tester);
      expect(key('stock-tab-transfers'), findsNothing);
    });

    testWidgets('with two places the menu and the transfers tab remain', (
      tester,
    ) async {
      final rig = RealRig();
      await rig.launchSignedIn(tester);
      expect(key('location-selector'), findsOneWidget);
      expect(key('location-label'), findsNothing);
    });
  });

  group('categories', () {
    testWidgets(
      'the filter lists the categories and can create a new one in place',
      (tester) async {
        final rig = RealRig();
        seedProduct(rig.server, sku: 'BP-1', name: 'Колодки');
        await openCatalog(tester, rig);
        await tapKey(tester, 'catalog-category-filter');
        await settle(tester, ms: 300);
        expect(key('category-all'), findsOneWidget);
        expect(key('category-Тормоза'), findsOneWidget);
        // an unknown name is offered as "Create «…»" and becomes the filter
        await tester.enterText(key('category-search'), 'Фильтры');
        await tester.pump();
        expect(find.text('Создать «Фильтры»'), findsOneWidget);
        await tapKey(tester, 'category-create');
        await settle(tester, ms: 400);
        expect(
          rig.server.categoriesData.map((c) => c['name']),
          contains('Фильтры'),
        );
        expect(find.textContaining('Фильтры'), findsOneWidget);
      },
    );

    testWidgets('choosing an existing category filters, "all" clears it', (
      tester,
    ) async {
      final rig = RealRig();
      seedProduct(rig.server, sku: 'BP-1', name: 'Колодки');
      await openCatalog(tester, rig);
      await tapKey(tester, 'catalog-category-filter');
      await settle(tester, ms: 300);
      await tapKey(tester, 'category-Тормоза');
      await settle(tester, ms: 300);
      expect(find.textContaining('Тормоза'), findsOneWidget);
      await tapKey(tester, 'catalog-category-filter');
      await settle(tester, ms: 300);
      await tapKey(tester, 'category-all');
      await settle(tester, ms: 300);
      expect(find.textContaining('Все категории'), findsOneWidget);
    });

    testWidgets('typing a name that exists offers no duplicate', (
      tester,
    ) async {
      final rig = RealRig();
      await openCatalog(tester, rig);
      await tapKey(tester, 'catalog-category-filter');
      await settle(tester, ms: 300);
      await tester.enterText(key('category-search'), 'тормоза');
      await tester.pump();
      expect(find.textContaining('Создать «'), findsNothing);
      expect(key('category-Тормоза'), findsOneWidget);
    });
  });

  group('adding a product by hand', () {
    testWidgets(
      'the stock page has an Add product button that opens the form',
      (tester) async {
        final rig = RealRig();
        await rig.launchSignedIn(tester);
        await tapKey(tester, 'nav-inventory');
        await settle(tester);
        await tapKey(tester, 'stock-add-manual');
        await settle(tester, ms: 500);
        // straight to the form for a product with no barcode
        expect(key('intake-new-name'), findsOneWidget);
        expect(find.text('Товар без штрих-кода'), findsWidgets);
      },
    );
  });
}
