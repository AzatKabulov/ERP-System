import 'package:erp_system/core/money/decimal_math.dart';
import 'package:erp_system/features/scanning/scan_screen.dart';
import 'package:erp_system/l10n/app_localizations.dart';
import 'package:erp_system/l10n/turkmen_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import '../core/fake_server.dart';
import '../support/fake_scanner.dart';
import '../support/real_rig.dart';

Map<String, dynamic> seedProduct(
  FakeServer server, {
  required String sku,
  required String name,
  String price = '120.00',
  String currency = 'TMT',
  String? cost,
  List<String> barcodes = const [],
  bool active = true,
  int warrantyMonths = 0,
  String warrantyTerms = '',
}) {
  final product = {
    'id': 'p-seed-${server.productsData.length + 1}',
    'sku': sku,
    'name': name,
    'category': 'c-1',
    'brand': 'br-1',
    'unit': 'un-1',
    'price_amount': price,
    'price_currency': currency,
    'default_purchase_cost': cost,
    'warranty_months': warrantyMonths,
    'warranty_terms': warrantyTerms,
    'barcodes': [...barcodes],
    'is_active': active,
    'created_at': '2026-10-06T10:00:00Z',
    'updated_at': '2026-10-06T10:00:00Z',
  };
  server.productsData.add(product);
  return product;
}

Future<void> openCatalog(WidgetTester tester, RealRig rig) async {
  await rig.launchSignedIn(tester);
  await tapKey(tester, 'nav-products');
  await settle(tester);
}

/// The catalog's own list (the navigation drawer is a list too, and comes first).
Finder get pageScrollable => find
    .descendant(
      of: find.byType(ListView).last,
      matching: find.byType(Scrollable),
    )
    .first;

Future<void> typeSearch(WidgetTester tester, String text) async {
  await tester.enterText(key('catalog-search'), text);
  await settle(tester, ms: 600); // past the typing pause
}

void main() {
  group('catalog list', () {
    testWidgets('an empty catalog says so and offers the first product', (
      tester,
    ) async {
      final rig = RealRig();
      await openCatalog(tester, rig);
      expect(key('catalog-empty'), findsOneWidget);
      expect(find.text('Товаров пока нет'), findsOneWidget);
      expect(key('catalog-add'), findsOneWidget);
    });

    testWidgets('lists products with SKU, brand and price; opens the detail', (
      tester,
    ) async {
      final rig = RealRig();
      seedProduct(
        rig.server,
        sku: 'BP-100',
        name: 'Тормозные колодки',
        barcodes: ['4006381333931'],
        cost: '70.00',
        warrantyMonths: 6,
        warrantyTerms: 'Только при установке в сервисе.',
      );
      seedProduct(rig.server, sku: 'OIL-5', name: 'Масло 5W-30', price: '45.5');
      await openCatalog(tester, rig);
      expect(key('product-BP-100'), findsOneWidget);
      expect(key('product-OIL-5'), findsOneWidget);
      expect(find.text('BP-100 · Brembo'), findsOneWidget);
      expect(find.text(formatMoney(12000, 'TMT')), findsOneWidget);
      await tapKey(tester, 'product-BP-100');
      await settle(tester);
      expect(find.text('Карточка товара'), findsOneWidget);
      expect(key('pd-name'), findsOneWidget);
      expect(find.text('Тормозные колодки'), findsWidgets);
      expect(key('pd-cost'), findsOneWidget); // the owner may see the cost
      expect(find.text('Гарантия: 6 мес.'), findsOneWidget);
      expect(find.text('Только при установке в сервисе.'), findsOneWidget);
      expect(find.text('4006381333931'), findsOneWidget);
    });

    testWidgets(
      'search narrows by name, SKU and barcode; Turkmen letters work',
      (tester) async {
        final rig = RealRig();
        seedProduct(rig.server, sku: 'BP-100', name: 'Тормозные колодки');
        seedProduct(rig.server, sku: 'OIL-5', name: 'Ýag süzgüji');
        seedProduct(
          rig.server,
          sku: 'LMP-9',
          name: 'Lampa',
          barcodes: ['5901234123457'],
        );
        await openCatalog(tester, rig);
        await typeSearch(tester, 'колодки');
        expect(key('product-BP-100'), findsOneWidget);
        expect(key('product-OIL-5'), findsNothing);
        await typeSearch(tester, 'ýag');
        expect(key('product-OIL-5'), findsOneWidget);
        await typeSearch(tester, '5901234123457');
        expect(key('product-LMP-9'), findsOneWidget);
        await typeSearch(tester, 'nothing like this');
        expect(find.text('Товары не найдены'), findsOneWidget);
        expect(key('catalog-add-scanned'), findsNothing); // typed, not scanned
      },
    );

    testWidgets('archived products are hidden until asked for', (tester) async {
      final rig = RealRig();
      seedProduct(rig.server, sku: 'A-1', name: 'Active');
      seedProduct(rig.server, sku: 'A-2', name: 'Retired', active: false);
      await openCatalog(tester, rig);
      expect(key('product-A-1'), findsOneWidget);
      expect(key('product-A-2'), findsNothing);
      await tapKey(tester, 'catalog-archived-toggle');
      await settle(tester);
      expect(key('product-A-2'), findsOneWidget);
      expect(find.text('В архиве'), findsOneWidget);
    });

    testWidgets('a long catalog loads in pages', (tester) async {
      final rig = RealRig();
      for (var i = 1; i <= 35; i++) {
        seedProduct(
          rig.server,
          sku: 'S-${i.toString().padLeft(2, '0')}',
          name: 'Item $i',
        );
      }
      await openCatalog(tester, rig);
      await tester.scrollUntilVisible(
        key('catalog-load-more'),
        300,
        scrollable: pageScrollable,
      );
      expect(key('product-S-30'), findsOneWidget);
      expect(key('product-S-31'), findsNothing); // the first page is 30
      await tapKey(tester, 'catalog-load-more');
      await settle(tester);
      await tester.scrollUntilVisible(
        key('product-S-35'),
        300,
        scrollable: pageScrollable,
      );
      expect(key('product-S-35'), findsOneWidget);
      expect(key('catalog-load-more'), findsNothing);
    });

    testWidgets('USD prices show the TMT equivalent, or that no rate exists', (
      tester,
    ) async {
      final rig = RealRig();
      seedProduct(
        rig.server,
        sku: 'USD-1',
        name: 'Imported',
        price: '10.00',
        currency: 'USD',
      );
      await openCatalog(tester, rig);
      expect(find.text(formatMoney(1000, 'USD')), findsOneWidget);
      expect(
        find.text('Курс USD не задан: цена в TMT неизвестна.'),
        findsOneWidget,
      );
      rig.server.ratesData.add({
        'id': 'r-1',
        'currency': 'USD',
        'rate': '3.5',
        'set_by': 'aman',
        'created_at': '2026-10-06T10:00:00Z',
      });
      await tapKey(tester, 'catalog-archived-toggle'); // any reload
      await tapKey(tester, 'catalog-archived-toggle');
      await settle(tester);
      expect(find.text('≈ ${formatMoney(3500, 'TMT')} в TMT'), findsOneWidget);
    });

    testWidgets('a user who may not manage the catalog cannot add products', (
      tester,
    ) async {
      final rig = RealRig();
      rig.server.role = 'sales';
      rig.server.permissions = ['catalog.view', 'location.view'];
      seedProduct(
        rig.server,
        sku: 'BP-100',
        name: 'Тормозные колодки',
        cost: '70.00',
      );
      await openCatalog(tester, rig);
      expect(key('catalog-add'), findsNothing);
      await tapKey(tester, 'product-BP-100');
      await settle(tester);
      expect(key('pd-edit'), findsNothing);
      expect(key('pd-archive'), findsNothing);
      expect(key('pd-cost'), findsNothing);
    });
  });

  group('product form', () {
    Future<void> openForm(WidgetTester tester, RealRig rig) async {
      await openCatalog(tester, rig);
      await tapKey(tester, 'catalog-add');
      await settle(tester);
    }

    Future<void> pickUnit(WidgetTester tester, String text) async {
      await tapKey(tester, 'pf-unit');
      await settle(tester, ms: 400);
      await tester.tap(find.text(text).last);
      await settle(tester, ms: 400);
    }

    testWidgets('creates a product with a TMT price and a barcode', (
      tester,
    ) async {
      final rig = RealRig();
      await openForm(tester, rig);
      await tester.enterText(key('pf-sku'), 'BP-100');
      await tester.enterText(key('pf-name'), 'Тормозные колодки');
      await pickUnit(tester, 'Штука (шт)');
      await tester.enterText(key('pf-price'), '1 250,5');
      await tester.enterText(key('pf-cost'), '800');
      await tester.enterText(key('pf-barcode'), '4006381333931');
      await tapKey(tester, 'pf-barcode-add');
      await tester.enterText(key('pf-warranty-months'), '12');
      await tester.enterText(key('pf-warranty-terms'), 'Гарантия на дефекты.');
      await tapKey(tester, 'pf-save');
      await settle(tester);
      expect(rig.server.productsData, hasLength(1));
      final saved = rig.server.productsData.single;
      expect(saved['sku'], 'BP-100');
      expect(saved['price_amount'], '1250.50'); // exact decimal text, no float
      expect(saved['price_currency'], 'TMT');
      expect(saved['default_purchase_cost'], '800.00');
      expect(saved['barcodes'], ['4006381333931']);
      expect(saved['warranty_months'], 12);
      expect(find.text('Товар сохранён.'), findsOneWidget);
      expect(key('product-BP-100'), findsOneWidget);
    });

    testWidgets('required fields are checked before anything is sent', (
      tester,
    ) async {
      final rig = RealRig();
      await openForm(tester, rig);
      await tapKey(tester, 'pf-save');
      await settle(tester);
      expect(find.text('Обязательное поле.'), findsWidgets);
      expect(rig.server.productWrites, 0);
      expect(key('pf-save'), findsOneWidget); // still on the form
    });

    testWidgets('a duplicate SKU is reported on the field, in Russian', (
      tester,
    ) async {
      final rig = RealRig();
      seedProduct(rig.server, sku: 'BP-100', name: 'Existing');
      await openForm(tester, rig);
      await tester.enterText(key('pf-sku'), 'bp-100');
      await tester.enterText(key('pf-name'), 'Another');
      await pickUnit(tester, 'Штука (шт)');
      await tester.enterText(key('pf-price'), '10');
      await tapKey(tester, 'pf-save');
      await settle(tester);
      expect(find.text('Этот артикул уже используется.'), findsOneWidget);
      expect(find.textContaining('sku_taken'), findsNothing);
      expect(rig.server.productsData, hasLength(1));
    });

    testWidgets(
      'a USD price previews the TMT value, and warns without a rate',
      (tester) async {
        final rig = RealRig();
        await openForm(tester, rig);
        await tapKey(tester, 'pf-currency-usd');
        await tester.enterText(key('pf-price'), '10');
        await tester.pump();
        expect(key('pf-rate-missing'), findsOneWidget);
        expect(key('pf-price-preview'), findsNothing);
      },
    );

    testWidgets('a USD price previews the converted TMT price', (tester) async {
      final rig = RealRig();
      rig.server.ratesData.add({
        'id': 'r-1',
        'currency': 'USD',
        'rate': '3.5',
        'set_by': 'aman',
        'created_at': '2026-10-06T10:00:00Z',
      });
      await openForm(tester, rig);
      await tapKey(tester, 'pf-currency-usd');
      await tester.enterText(key('pf-price'), '10,10');
      await tester.pump();
      expect(key('pf-rate-missing'), findsNothing);
      // 10.10 x 3.5 = 35.35
      expect(find.text('≈ ${formatMoney(3535, 'TMT')} в TMT'), findsOneWidget);
      await pickUnit(tester, 'Штука (шт)');
      await tester.enterText(key('pf-sku'), 'U-1');
      await tester.enterText(key('pf-name'), 'Imported');
      await tapKey(tester, 'pf-save');
      await settle(tester);
      final saved = rig.server.productsData.single;
      expect(saved['price_currency'], 'USD');
      expect(saved['price_amount'], '10.10');
    });

    testWidgets('a role without cost access never sees or sends the cost', (
      tester,
    ) async {
      final rig = RealRig();
      rig.server.role = 'warehouse';
      rig.server.permissions = [
        'catalog.view',
        'catalog.manage',
        'location.view',
      ];
      await openForm(tester, rig);
      expect(key('pf-cost'), findsNothing);
      await tester.enterText(key('pf-sku'), 'W-1');
      await tester.enterText(key('pf-name'), 'Thing');
      await pickUnit(tester, 'Штука (шт)');
      await tester.enterText(key('pf-price'), '5');
      await tapKey(tester, 'pf-save');
      await settle(tester);
      expect(
        rig.server.productsData.single.containsKey('default_purchase_cost'),
        isFalse,
      );
    });

    testWidgets('leaving a form with changes asks first', (tester) async {
      final rig = RealRig();
      await openForm(tester, rig);
      await tester.enterText(key('pf-sku'), 'X-1');
      await tester.pump();
      await tester.tap(find.byType(BackButton));
      await settle(tester, ms: 400);
      expect(find.text('Подтвердить'), findsOneWidget);
      await tester.tap(find.text('Отмена'));
      await settle(tester, ms: 400);
      expect(key('pf-sku'), findsOneWidget); // stayed
      await tester.tap(find.byType(BackButton));
      await settle(tester, ms: 400);
      await tester.tap(find.text('Подтвердить'));
      await settle(tester);
      expect(key('pf-sku'), findsNothing);
      expect(rig.server.productWrites, 0);
    });

    testWidgets('editing and archiving a product', (tester) async {
      final rig = RealRig();
      seedProduct(rig.server, sku: 'BP-100', name: 'Old name');
      await openCatalog(tester, rig);
      await tapKey(tester, 'product-BP-100');
      await settle(tester);
      await tapKey(tester, 'pd-edit');
      await settle(tester);
      await tester.enterText(key('pf-name'), 'New name');
      await tapKey(tester, 'pf-save');
      await settle(tester);
      expect(rig.server.productsData.single['name'], 'New name');
      expect(find.text('New name'), findsWidgets);
      await tapKey(tester, 'pd-archive');
      await settle(tester, ms: 400);
      await tester.tap(find.text('Подтвердить'));
      await settle(tester);
      expect(rig.server.productsData.single['is_active'], isFalse);
      expect(key('pd-restore'), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await settle(tester);
      expect(key('product-BP-100'), findsNothing); // gone from the active list
    });
  });

  group('scanning', () {
    testWidgets('a scan finds the product but opens or changes nothing', (
      tester,
    ) async {
      final scanner = FakeScanner(results: ['4006381333931']);
      final rig = RealRig(scanner: scanner);
      seedProduct(
        rig.server,
        sku: 'BP-100',
        name: 'Тормозные колодки',
        barcodes: ['4006381333931'],
      );
      seedProduct(rig.server, sku: 'OIL-5', name: 'Масло');
      await openCatalog(tester, rig);
      await tapKey(tester, 'scan-button');
      await settle(tester);
      expect(scanner.opened, 1);
      expect(key('product-BP-100'), findsOneWidget);
      expect(key('product-OIL-5'), findsNothing);
      expect(rig.server.productWrites, 0);
      expect(find.text('Карточка товара'), findsNothing); // not auto-opened
    });

    testWidgets(
      'an unknown code offers to add a product, pre-filled but not saved',
      (tester) async {
        final scanner = FakeScanner(results: ['9999999999994']);
        final rig = RealRig(scanner: scanner);
        await openCatalog(tester, rig);
        await tapKey(tester, 'scan-button');
        await settle(tester);
        expect(
          find.text('Товар с таким штрихкодом не найден.'),
          findsOneWidget,
        );
        expect(find.text('Считан код: 9999999999994'), findsOneWidget);
        expect(rig.server.productWrites, 0);
        await tapKey(tester, 'catalog-add-scanned');
        await settle(tester);
        expect(key('pf-barcode-chip-9999999999994'), findsOneWidget);
        expect(rig.server.productWrites, 0); // still nothing saved
        await tester.enterText(key('pf-sku'), 'N-1');
        await tester.enterText(key('pf-name'), 'Newly scanned');
        await tapKey(tester, 'pf-unit');
        await settle(tester, ms: 400);
        await tester.tap(find.text('Штука (шт)').last);
        await settle(tester, ms: 400);
        await tester.enterText(key('pf-price'), '3');
        await tapKey(tester, 'pf-save');
        await settle(tester);
        expect(rig.server.productsData.single['barcodes'], ['9999999999994']);
      },
    );

    testWidgets('closing the camera changes nothing', (tester) async {
      final scanner = FakeScanner(results: [null]);
      final rig = RealRig(scanner: scanner);
      seedProduct(rig.server, sku: 'A-1', name: 'Item');
      await openCatalog(tester, rig);
      await tapKey(tester, 'scan-button');
      await settle(tester);
      expect(scanner.opened, 1);
      expect(key('product-A-1'), findsOneWidget);
      expect(find.textContaining('Считан код'), findsNothing);
    });

    testWidgets('a scan in the form adds the code to the draft only', (
      tester,
    ) async {
      final scanner = FakeScanner(results: ['4006381333931']);
      final rig = RealRig(scanner: scanner);
      await openCatalog(tester, rig);
      await tapKey(tester, 'catalog-add');
      await settle(tester);
      await tapKey(tester, 'scan-button');
      await settle(tester);
      expect(key('pf-barcode-chip-4006381333931'), findsOneWidget);
      expect(rig.server.productWrites, 0);
    });

    testWidgets('without a camera there is no scan button, only typing', (
      tester,
    ) async {
      final rig = RealRig(scanner: FakeScanner(available: false));
      await openCatalog(tester, rig);
      expect(key('scan-button'), findsNothing);
      expect(key('catalog-search'), findsOneWidget);
    });

    for (final locale in ['ru', 'tk']) {
      testWidgets('the camera error panel explains itself in $locale', (
        tester,
      ) async {
        var manual = 0;
        for (final denied in [true, false]) {
          await tester.pumpWidget(
            MaterialApp(
              locale: Locale(locale),
              localizationsDelegates: const [
                AppLocalizations.delegate,
                TurkmenMaterialDelegate(),
                TurkmenCupertinoDelegate(),
                TurkmenWidgetsDelegate(),
                GlobalMaterialLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
              ],
              supportedLocales: AppLocalizations.supportedLocales,
              home: Scaffold(
                body: ScanErrorPanel(denied: denied, onManual: () => manual++),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final l = await AppLocalizations.delegate.load(Locale(locale));
          expect(
            find.text(denied ? l.cameraDenied : l.cameraUnavailable),
            findsOneWidget,
          );
          await tester.tap(find.byKey(const ValueKey('scan-error-manual')));
        }
        expect(manual, 2);
      });
    }
  });

  group('exchange rate', () {
    Future<void> openAdmin(WidgetTester tester, RealRig rig) async {
      await rig.launchSignedIn(tester);
      await tapKey(tester, 'nav-administration');
      await settle(tester);
    }

    testWidgets('shows that no rate exists, then records one with history', (
      tester,
    ) async {
      final rig = RealRig();
      await openAdmin(tester, rig);
      expect(key('rate-none'), findsOneWidget);
      await tester.enterText(key('rate-input'), '3,5');
      await tapKey(tester, 'rate-save');
      await settle(tester);
      expect(find.text('Текущий курс: 1 USD = 3,50 TMT'), findsOneWidget);
      expect(rig.server.ratesData.single['rate'], '3.500000');
      await tester.enterText(key('rate-input'), '3,62');
      await tapKey(tester, 'rate-save');
      await settle(tester);
      expect(find.text('Текущий курс: 1 USD = 3,62 TMT'), findsOneWidget);
      expect(find.text('История курса'), findsOneWidget);
      expect(rig.server.ratesData, hasLength(2)); // appended, never replaced
    });

    testWidgets('rejects a rate that is not a positive number', (tester) async {
      final rig = RealRig();
      await openAdmin(tester, rig);
      await tester.enterText(key('rate-input'), 'abc');
      await tapKey(tester, 'rate-save');
      await settle(tester);
      expect(rig.server.ratesData, isEmpty);
      expect(find.text('Некорректное значение.'), findsOneWidget);
    });

    testWidgets('a user who may only view the rate cannot change it', (
      tester,
    ) async {
      final rig = RealRig();
      rig.server.permissions = ['business.view', 'exchange_rate.view'];
      await openAdmin(tester, rig);
      expect(key('rate-none'), findsOneWidget);
      expect(key('rate-input'), findsNothing);
      expect(key('rate-save'), findsNothing);
    });
  });
}
