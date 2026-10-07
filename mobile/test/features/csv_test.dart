import 'dart:convert';
import 'dart:typed_data';

import 'package:erp_system/core/files/file_services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/real_rig.dart';
import 'catalog_test.dart' show openCatalog, seedProduct;
import 'stock_ops_test.dart' show canPress;

const header = 'sku;name;unit;category;brand;price;currency';

PickedFile csvFile(List<String> rows, {String name = 'products.csv'}) =>
    PickedFile(
      name: name,
      bytes: Uint8List.fromList(utf8.encode([header, ...rows].join('\r\n'))),
    );

Future<void> chooseFile(
  WidgetTester tester,
  RealRig rig,
  PickedFile file,
) async {
  rig.picking.nextFile = file;
  await tapKey(tester, 'import-choose');
  await settle(tester);
}

void main() {
  RealRig rigWithProduct() {
    final rig = RealRig();
    seedProduct(rig.server, sku: 'OLD-1', name: 'Старый товар');
    return rig;
  }

  testWidgets('a file with an error shows the row and applies nothing', (
    tester,
  ) async {
    final rig = rigWithProduct();
    await openCatalog(tester, rig);
    await tapKey(tester, 'catalog-import');
    await settle(tester);
    expect(canPress(tester, 'import-choose'), isTrue);
    expect(key('import-apply'), findsNothing); // nothing to apply before a file
    await chooseFile(
      tester,
      rig,
      csvFile([
        'NEW-1;Свеча;шт;;;45,50;TMT',
        'OLD-1;Повтор;шт;;;10;TMT', // already in the catalog
        'NEW-3;Фильтр;кг;;;20;TMT', // unknown unit
      ]),
    );
    expect(rig.picking.fileRequests.single, ['csv', 'txt']);
    expect(find.text('Строк: 3, без ошибок: 1'), findsOneWidget);
    expect(key('import-row-2-sku'), findsOneWidget);
    expect(key('import-row-3-unit'), findsOneWidget);
    expect(find.textContaining('Ошибок: 2'), findsOneWidget);
    expect(
      find.text('Строка 2, sku: Такой артикул уже есть в каталоге.'),
      findsOneWidget,
    );
    expect(canPress(tester, 'import-apply'), isFalse);
    expect(rig.server.office.importsApplied, 0);
    expect(rig.server.productsData.length, 1); // the catalog did not change
  });

  testWidgets('a fixed file is checked, applied and shows in the catalog', (
    tester,
  ) async {
    final rig = rigWithProduct();
    await openCatalog(tester, rig);
    await tapKey(tester, 'catalog-import');
    await settle(tester);
    await chooseFile(
      tester,
      rig,
      csvFile([
        'NEW-1;Свеча зажигания;шт;;;45,50;TMT',
        'NEW-2;Масляный фильтр;шт;;;80;TMT',
      ]),
    );
    expect(find.text('Строк: 2, без ошибок: 2'), findsOneWidget);
    expect(key('import-ok'), findsOneWidget);
    await tapKey(tester, 'import-apply');
    await settle(tester);
    expect(find.text('Добавлено товаров: 2.'), findsOneWidget);
    expect(rig.server.office.importsApplied, 1);
    expect(rig.server.productsData.length, 3);
    // Back in the catalog the new products are listed.
    await goBack(tester);
    expect(find.text('Свеча зажигания'), findsOneWidget);
    expect(find.text('Масляный фильтр'), findsOneWidget);
  });

  testWidgets('a file that is too large asks to split it', (tester) async {
    final rig = rigWithProduct();
    rig.server.office.importLimit = 2;
    await openCatalog(tester, rig);
    await tapKey(tester, 'catalog-import');
    await settle(tester);
    await chooseFile(
      tester,
      rig,
      csvFile([
        'A-1;Один;шт;;;1;TMT',
        'A-2;Два;шт;;;1;TMT',
        'A-3;Три;шт;;;1;TMT',
      ]),
    );
    expect(find.textContaining('разделите его на части'), findsOneWidget);
    expect(key('import-apply'), findsNothing);
    expect(rig.server.productsData.length, 1);
  });

  testWidgets('wrong column names are reported', (tester) async {
    final rig = rigWithProduct();
    await openCatalog(tester, rig);
    await tapKey(tester, 'catalog-import');
    await settle(tester);
    rig.picking.nextFile = PickedFile(
      name: 'bad.csv',
      bytes: Uint8List.fromList(utf8.encode('a;b\r\n1;2')),
    );
    await tapKey(tester, 'import-choose');
    await settle(tester);
    expect(find.text('В файле неверные названия колонок.'), findsOneWidget);
  });

  testWidgets('cancelling the file dialog changes nothing', (tester) async {
    final rig = rigWithProduct();
    await openCatalog(tester, rig);
    await tapKey(tester, 'catalog-import');
    await settle(tester);
    rig.picking.nextFile = null;
    await tapKey(tester, 'import-choose');
    await settle(tester);
    expect(key('import-summary'), findsNothing);
    expect(key('import-error'), findsNothing);
  });

  testWidgets('export hands the file over for sharing', (tester) async {
    final rig = rigWithProduct();
    await openCatalog(tester, rig);
    await tapKey(tester, 'catalog-export');
    await settle(tester);
    final shared = rig.sharing.shared.single;
    expect(shared.name, 'products.csv');
    expect(shared.mimeType, 'text/csv');
    expect(shared.bytes.take(3).toList(), [
      0xEF,
      0xBB,
      0xBF,
    ]); // Excel opens the BOM
    expect(utf8.decode(shared.bytes), contains('OLD-1'));
    expect(find.text('Файл каталога готов.'), findsOneWidget);
  });

  testWidgets('a seller sees neither import nor export', (tester) async {
    final rig = rigWithProduct();
    rig.server.role = 'sales';
    rig.server.permissions = ['catalog.view', 'sales.view', 'sales.create'];
    await openCatalog(tester, rig);
    expect(key('catalog-import'), findsNothing);
    expect(key('catalog-export'), findsNothing);
  });

  for (final size in [const Size(360, 800), const Size(800, 1100)]) {
    testWidgets('import screen fits $size with doubled text', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final rig = rigWithProduct();
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
      expect(tester.takeException(), isNull, reason: 'catalog');
      await tapKey(tester, 'catalog-import');
      await settle(tester);
      await chooseFile(
        tester,
        rig,
        csvFile(['OLD-1;Повтор;шт;;;10;TMT', 'NEW-3;Фильтр;кг;;;20;TMT']),
      );
      expect(tester.takeException(), isNull, reason: 'errors');
    });
  }
}
