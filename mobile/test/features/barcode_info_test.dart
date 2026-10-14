import 'package:erp_system/features/catalog/catalog_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_scanner.dart';
import '../support/real_rig.dart';
import 'intake_test.dart'
    show intakeRig, openIntake, scanByKeyboard, sendIntake;
import 'stock_ops_test.dart' show idOf;

const cerave = '3337875597470';

void know(RealRig rig, {String quantity = '454 g'}) {
  rig.server.externalInfo[cerave] = {
    'name': 'Cerave Moisturising Cream',
    'brand': 'Cerave',
    'quantity': quantity,
  };
}

void main() {
  group('the name offered for a barcode', () {
    test('the brand and the size are added only when the name lacks them', () {
      const info = ExternalInfo(
        name: 'moisturising cream',
        brand: 'CeraVe',
        quantity: '454 g',
        source: 'Open Beauty Facts',
      );
      expect(info.displayName, 'CeraVe moisturising cream 454 g');
      const complete = ExternalInfo(
        name: 'CeraVe Moisturising Cream 454 g',
        brand: 'cerave',
        quantity: '454 g',
        source: '',
      );
      expect(complete.displayName, 'CeraVe Moisturising Cream 454 g');
      const bare = ExternalInfo(
        name: 'Soap',
        brand: '',
        quantity: '',
        source: '',
      );
      expect(bare.displayName, 'Soap');
    });

    test('only digits of a barcode length are asked about', () {
      for (final good in ['3337875597470', '40058153', '036000291452']) {
        expect(looksLikeGtin(good), isTrue, reason: good);
      }
      for (final bad in [
        'BP-100',
        '12345',
        'MH044089',
        '',
        'https://x.test/q',
      ]) {
        expect(looksLikeGtin(bad), isFalse, reason: bad);
      }
    });

    test('a miss is nothing and a hit has its name', () {
      expect(ExternalInfo.fromJson({'found': false}), isNull);
      expect(ExternalInfo.fromJson({'found': true, 'name': '  '}), isNull);
      final info = ExternalInfo.fromJson({
        'found': true,
        'name': ' Soap ',
        'brand': 'X',
        'quantity': '1',
        'source': 'S',
      });
      expect((info!.name, info.brand, info.source), ('Soap', 'X', 'S'));
    });
  });

  group('receiving goods whose barcode is known online', () {
    testWidgets('the name shows on the line and one tap adds the product', (
      tester,
    ) async {
      final t = intakeRig();
      know(t.rig);
      await openIntake(tester, t.rig);
      await scanByKeyboard(tester, cerave);
      await scanByKeyboard(tester, cerave);
      expect(
        find.text('Нашли в интернете: Cerave Moisturising Cream 454 g'),
        findsOneWidget,
      );
      expect(t.rig.server.externalAsked, [
        cerave,
      ], reason: 'asked once, not per scan');
      await tapKey(tester, 'intake-add-found-$cerave');
      await settle(tester);
      final created = t.rig.server.productsData.last;
      expect(created['name'], 'Cerave Moisturising Cream 454 g');
      expect(created['sku'], cerave);
      expect(created['barcodes'], [
        cerave,
      ]); // the barcode is remembered for good
      expect(created['price_amount'], '0.00'); // prices are filled in later
      expect(find.text('2 шт'), findsOneWidget);
      // the next box with the same code needs no question and no typing
      await scanByKeyboard(tester, cerave);
      expect(find.text('3 шт'), findsOneWidget);
      expect(t.rig.server.externalAsked.length, 1);
      await sendIntake(tester);
      expect(t.rig.server.ledger.quantityOf(idOf(created), 'l-1'), 3000);
    });

    testWidgets('the name can be changed before adding', (tester) async {
      final t = intakeRig();
      know(t.rig);
      await openIntake(tester, t.rig);
      await scanByKeyboard(tester, cerave);
      await tapKey(tester, 'intake-add-$cerave');
      await settle(tester, ms: 600);
      final field = tester.widget<TextField>(
        find.byKey(const ValueKey('intake-new-name')),
      );
      expect(field.controller!.text, 'Cerave Moisturising Cream 454 g');
      await tester.enterText(key('intake-new-name'), 'Увлажняющий крем CeraVe');
      await tapKey(tester, 'intake-new-save');
      await settle(tester);
      expect(t.rig.server.productsData.last['name'], 'Увлажняющий крем CeraVe');
    });

    testWidgets('a code nobody knows still works by typing the name', (
      tester,
    ) async {
      final t = intakeRig(); // nothing known online
      await openIntake(tester, t.rig);
      await scanByKeyboard(tester, cerave);
      expect(t.rig.server.externalAsked, [cerave]);
      expect(find.textContaining('нет в каталоге'), findsOneWidget);
      expect(key('intake-add-found-$cerave'), findsNothing);
      await tapKey(tester, 'intake-add-$cerave');
      await settle(tester, ms: 600);
      final field = tester.widget<TextField>(
        find.byKey(const ValueKey('intake-new-name')),
      );
      expect(field.controller!.text, '');
      await tester.enterText(key('intake-new-name'), 'Saturday Cream');
      await tapKey(tester, 'intake-new-save');
      await settle(tester);
      expect(t.rig.server.productsData.last['name'], 'Saturday Cream');
      expect(t.rig.server.productsData.last['barcodes'], [cerave]);
    });

    testWidgets('the internet failing changes nothing for the worker', (
      tester,
    ) async {
      final t = intakeRig();
      know(t.rig);
      t.rig.server.externalFails = true;
      await openIntake(tester, t.rig);
      await scanByKeyboard(tester, cerave);
      expect(find.textContaining('нет в каталоге'), findsOneWidget);
      expect(key('intake-add-found-$cerave'), findsNothing);
      expect(key('intake-add-$cerave'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a code that cannot be a barcode number is never sent out', (
      tester,
    ) async {
      final t = intakeRig();
      await openIntake(tester, t.rig);
      await scanByKeyboard(tester, 'MH044089');
      await scanByKeyboard(tester, 'https://example.test/qr?x=1');
      await scanByKeyboard(tester, '12345');
      expect(t.rig.server.externalAsked, isEmpty);
    });

    testWidgets('a product the catalog already has is not asked about', (
      tester,
    ) async {
      final t = intakeRig();
      know(t.rig);
      t.rig.server.productsData.add({
        ...t.bushing,
        'id': 'p-known',
        'sku': 'CERAVE-1',
        'barcodes': [cerave],
      });
      await openIntake(tester, t.rig);
      await scanByKeyboard(tester, cerave);
      expect(t.rig.server.externalAsked, isEmpty);
    });

    testWidgets(
      'a scanned code in the catalog offers the name in the new product form',
      (tester) async {
        final rig = RealRig(scanner: FakeScanner(results: [cerave]));
        know(rig);
        await rig.launchSignedIn(tester);
        await tapKey(tester, 'nav-products');
        await settle(tester);
        await tapKey(tester, 'scan-button');
        await settle(tester);
        await tapKey(tester, 'catalog-add-scanned');
        await settle(tester);
        expect(
          rig.server.productWrites,
          0,
          reason: 'a suggestion saves nothing',
        );
        final name = tester.widget<TextField>(
          find.byKey(const ValueKey('pf-name')),
        );
        expect(name.controller!.text, 'Cerave Moisturising Cream 454 g');
        expect(
          find.textContaining(
            'Название найдено в интернете (Open Beauty Facts)',
          ),
          findsOneWidget,
        );
        expect(key('pf-barcode-chip-$cerave'), findsOneWidget);
      },
    );

    testWidgets('a name the person already typed is not replaced', (
      tester,
    ) async {
      final rig = RealRig(scanner: FakeScanner(results: [cerave]));
      know(rig);
      await rig.launchSignedIn(tester);
      await tapKey(tester, 'nav-products');
      await settle(tester);
      await tapKey(tester, 'scan-button');
      await settle(tester);
      // the answer is already in by the time the form shows; typing over it is what counts
      await tapKey(tester, 'catalog-add-scanned');
      await settle(tester);
      await tester.enterText(key('pf-name'), 'My own name');
      await settle(tester);
      final name = tester.widget<TextField>(
        find.byKey(const ValueKey('pf-name')),
      );
      expect(name.controller!.text, 'My own name');
    });
  });
}
