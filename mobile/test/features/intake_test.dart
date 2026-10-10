import 'package:erp_system/features/catalog/catalog_models.dart' show UnitRef;
import 'package:erp_system/features/intake/intake_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_scanner.dart';
import '../support/real_rig.dart';
import 'catalog_test.dart' show seedProduct;
import 'phase4_layout_test.dart' show navigate;
import 'stock_ops_test.dart' show fieldNames, idOf;

const store = 'l-1'; // Esasy dükan, where the signed-in user starts

({RealRig rig, FakeScanner scanner, Map<String, dynamic> bushing}) intakeRig() {
  final scanner = FakeScanner();
  final rig = RealRig(scanner: scanner);
  // the part number is printed as the barcode text: the product has no barcode of its own
  final bushing = seedProduct(
    rig.server,
    sku: 'MB-025153',
    name: 'Сайлентблок рессоры Canter',
  );
  seedProduct(
    rig.server,
    sku: 'KYB-444083',
    name: 'Амортизатор KYB',
    barcodes: ['444083'],
  );
  return (rig: rig, scanner: scanner, bushing: bushing);
}

Future<void> openIntake(WidgetTester tester, RealRig rig) async {
  await rig.launchSignedIn(tester);
  await tapKey(tester, 'nav-inventory');
  await settle(tester);
  await tapKey(tester, 'stock-intake');
  await settle(tester);
}

/// Types a code and presses Enter, as a hand scanner does for every item it reads.
Future<void> scanByKeyboard(WidgetTester tester, String code) async {
  await tester.enterText(key('intake-input'), code);
  await tester.testTextInput.receiveAction(TextInputAction.done);
  await settle(tester, ms: 400);
}

Future<void> sendIntake(WidgetTester tester) async {
  await tapKey(tester, 'intake-submit');
  await settle(tester, ms: 400);
  await tester.tap(find.text('Подтвердить'));
  await settle(tester);
}

String draftKey(RealRig rig) =>
    rig.prefs.getKeys().singleWhere((k) => k.startsWith('intake_draft_'));

void main() {
  group('scanning goods in', () {
    testWidgets('every scan adds one, and one tap puts the box on the shelf', (
      tester,
    ) async {
      final t = intakeRig();
      await openIntake(tester, t.rig);
      expect(key('intake-empty'), findsOneWidget);
      for (final code in ['MB-025153', 'MB-025153', 'mb-025153', '444083']) {
        await scanByKeyboard(tester, code);
      }
      // the same code in any letter case is one line; a barcode finds its product
      expect(find.text('3 шт'), findsOneWidget);
      expect(find.text('1 шт'), findsOneWidget);
      expect(find.text('Сайлентблок рессоры Canter'), findsOneWidget);
      expect(find.text('Амортизатор KYB'), findsOneWidget);
      expect(find.text('Позиций: 2, всего: 4'), findsWidgets);

      await sendIntake(tester);
      final ledger = t.rig.server.ledger;
      expect(ledger.intakesPosted, 1);
      expect(ledger.quantityOf(idOf(t.bushing), store), 3000);
      expect(
        ledger.movements.where((m) => m['movement_type'] == 'intake'),
        hasLength(2),
      );
      expect(find.text('Проведено.'), findsOneWidget);
      expect(t.rig.store.backing, isEmpty);
      expect(
        t.rig.prefs.getKeys().any((k) => k.startsWith('intake_draft_')),
        false,
      );
    });

    testWidgets('the camera stays open and counts item after item', (
      tester,
    ) async {
      final t = intakeRig();
      await openIntake(tester, t.rig);
      t.scanner.continuous.addAll(['MB-025153', 'MB-025153', '444083']);
      await tapKey(tester, 'intake-camera');
      await settle(tester);
      expect(t.scanner.opened, 1);
      expect(find.text('2 шт'), findsOneWidget);
      expect(find.text('1 шт'), findsOneWidget);
    });

    testWidgets('two codes of one product end up on one line', (tester) async {
      final t = intakeRig();
      seedProduct(
        t.rig.server,
        sku: 'A-1',
        name: 'С двумя кодами',
        barcodes: ['999'],
      );
      await openIntake(tester, t.rig);
      for (final code in ['A-1', 'A-1', '999']) {
        await scanByKeyboard(tester, code);
      }
      expect(find.text('С двумя кодами'), findsOneWidget);
      expect(find.text('3 шт'), findsOneWidget);
      expect(find.text('Позиций: 1, всего: 3'), findsWidgets);
    });

    testWidgets('minus and plus change the count, never below one', (
      tester,
    ) async {
      final t = intakeRig();
      await openIntake(tester, t.rig);
      await scanByKeyboard(tester, 'MB-025153');
      await tapKey(tester, 'intake-plus-MB-025153');
      await tapKey(tester, 'intake-plus-MB-025153');
      expect(find.text('3 шт'), findsOneWidget);
      await tapKey(tester, 'intake-minus-MB-025153');
      await tapKey(tester, 'intake-minus-MB-025153');
      await tapKey(tester, 'intake-minus-MB-025153');
      expect(find.text('1 шт'), findsOneWidget);
      await tapKey(tester, 'intake-remove-MB-025153');
      expect(key('intake-empty'), findsOneWidget);
    });

    testWidgets('an exact count can be typed', (tester) async {
      final t = intakeRig();
      await openIntake(tester, t.rig);
      await scanByKeyboard(tester, 'MB-025153');
      await tapKey(tester, 'intake-qty-MB-025153');
      await settle(tester, ms: 400);
      await tester.enterText(key('intake-edit-qty'), '15');
      await tapKey(tester, 'intake-edit-save');
      await settle(tester, ms: 400);
      expect(find.text('15 шт'), findsOneWidget);
      await tapKey(tester, 'intake-qty-MB-025153');
      await settle(tester, ms: 400);
      await tester.enterText(key('intake-edit-qty'), '1,5'); // pieces are whole
      await tapKey(tester, 'intake-edit-save');
      await settle(tester, ms: 200);
      expect(find.textContaining('меньше знаков'), findsOneWidget);
    });
  });

  group('codes the catalog does not know', () {
    testWidgets('a name is enough to add the product and count it', (
      tester,
    ) async {
      final t = intakeRig();
      await openIntake(tester, t.rig);
      await scanByKeyboard(tester, 'MH044089');
      await scanByKeyboard(tester, 'MH044089');
      expect(find.textContaining('нет в каталоге'), findsOneWidget);
      await tapKey(tester, 'intake-add-MH044089');
      await settle(tester, ms: 600);
      expect(find.text('Код: MH044089'), findsOneWidget);
      await tester.enterText(key('intake-new-name'), 'Подшипник КПП');
      await tapKey(tester, 'intake-new-save');
      await settle(tester);
      final created = t.rig.server.productsData.last;
      expect(created['sku'], 'MH044089');
      expect(created['name'], 'Подшипник КПП');
      expect(created['barcodes'], ['MH044089']);
      expect(created['price_amount'], '0.00'); // prices are typed at the sale
      expect(find.text('Подшипник КПП'), findsOneWidget);
      expect(find.text('2 шт'), findsOneWidget);
      // the next scan of that code finds the product by itself
      await scanByKeyboard(tester, 'MH044089');
      expect(find.text('3 шт'), findsOneWidget);
      await sendIntake(tester);
      expect(t.rig.server.ledger.quantityOf(idOf(created), store), 3000);
    });

    testWidgets('a QR code with a web address needs the article typed', (
      tester,
    ) async {
      final t = intakeRig();
      await openIntake(tester, t.rig);
      const link = 'https://example.com/p/9f8e7d6c';
      await scanByKeyboard(tester, link);
      await tapKey(tester, 'intake-add-$link');
      await settle(tester, ms: 600);
      await tester.enterText(key('intake-new-name'), 'Фильтр масляный');
      await tapKey(tester, 'intake-new-save');
      await settle(tester, ms: 300);
      expect(find.text('Обязательное поле.'), findsOneWidget); // no article yet
      await tester.enterText(key('intake-new-sku'), 'JX1008A');
      await tapKey(tester, 'intake-new-save');
      await settle(tester);
      final created = t.rig.server.productsData.last;
      expect(created['sku'], 'JX1008A');
      expect(
        created['barcodes'],
        isEmpty,
      ); // a link is not a barcode to remember
      expect(find.text('Фильтр масляный'), findsOneWidget);
    });

    testWidgets('an article number that is taken is explained', (tester) async {
      final t = intakeRig();
      await openIntake(tester, t.rig);
      await scanByKeyboard(tester, 'NEW-1');
      await tapKey(tester, 'intake-add-NEW-1');
      await settle(tester, ms: 600);
      await tester.enterText(key('intake-new-name'), 'Другая вещь');
      await tester.enterText(key('intake-new-sku'), 'KYB-444083');
      await tapKey(tester, 'intake-new-save');
      await settle(tester);
      expect(find.text('Этот артикул уже используется.'), findsOneWidget);
      expect(
        find.text('Другая вещь'),
        findsOneWidget,
      ); // what was typed is kept
      expect(
        t.rig.server.productsData.where((p) => p['name'] == 'Другая вещь'),
        isEmpty,
      );
    });

    testWidgets('the box cannot be received while a line has no product', (
      tester,
    ) async {
      final t = intakeRig();
      await openIntake(tester, t.rig);
      await scanByKeyboard(tester, 'MB-025153');
      await scanByKeyboard(tester, 'UNKNOWN-1');
      await tapKey(tester, 'intake-submit');
      await settle(tester, ms: 300);
      expect(key('intake-error'), findsOneWidget);
      expect(find.textContaining('без товара'), findsOneWidget);
      expect(t.rig.server.ledger.intakesPosted, 0);
    });
  });

  group('nothing is lost', () {
    testWidgets('the list survives leaving the screen and restarting', (
      tester,
    ) async {
      final t = intakeRig();
      await openIntake(tester, t.rig);
      await scanByKeyboard(tester, 'MB-025153');
      await scanByKeyboard(tester, 'MB-025153');
      await scanByKeyboard(tester, '444083');
      await goBack(tester);
      await tapKey(tester, 'stock-intake');
      await settle(tester);
      expect(key('intake-resumed'), findsOneWidget);
      expect(
        find.text('Продолжаем незавершённую приёмку: 2 поз.'),
        findsOneWidget,
      );
      expect(find.text('2 шт'), findsOneWidget);

      // the tablet is switched off and on again: a fresh app, the same storage
      final saved = t.rig.prefs.getString(draftKey(t.rig))!;
      final name = draftKey(t.rig);
      await tester.pumpWidget(const SizedBox());
      await t.rig.launch(tester, prefsValues: {name: saved});
      await settle(tester);
      await tapKey(tester, 'nav-inventory');
      await settle(tester);
      await tapKey(tester, 'stock-intake');
      await settle(tester);
      expect(key('intake-resumed'), findsOneWidget);
      expect(find.text('Сайлентблок рессоры Canter'), findsOneWidget);
      expect(find.text('2 шт'), findsOneWidget);
      await sendIntake(tester);
      expect(t.rig.server.ledger.intakesPosted, 1);
    });

    testWidgets('start over asks first and then forgets the list', (
      tester,
    ) async {
      final t = intakeRig();
      await openIntake(tester, t.rig);
      await scanByKeyboard(tester, 'MB-025153');
      await goBack(tester);
      await tapKey(tester, 'stock-intake');
      await settle(tester);
      await tapKey(tester, 'intake-start-over');
      await settle(tester, ms: 400);
      await tester.tap(find.text('Подтвердить'));
      await settle(tester, ms: 400);
      expect(key('intake-empty'), findsOneWidget);
      expect(
        t.rig.prefs.getKeys().any((k) => k.startsWith('intake_draft_')),
        false,
      );
    });

    testWidgets('answer lost then the tablet restarts: exactly one receipt', (
      tester,
    ) async {
      final t = intakeRig();
      await openIntake(tester, t.rig);
      await scanByKeyboard(tester, 'MB-025153');
      await scanByKeyboard(tester, 'MB-025153');
      t.rig.server.dropResponseAfterCommit = 1;
      await sendIntake(tester);
      expect(find.textContaining('Ответ сервера не получен'), findsOneWidget);
      expect(t.rig.store.backing.single.action, 'stock_intake');
      expect(t.rig.server.ledger.intakesPosted, 1);
      await tester.pumpWidget(const SizedBox());
      await t.rig.launch(tester);
      await settle(tester);
      expect(
        key('pending-banner'),
        findsNothing,
      ); // the server confirmed the key
      expect(t.rig.store.backing, isEmpty);
      expect(t.rig.server.ledger.intakesPosted, 1);
      expect(t.rig.server.ledger.quantityOf(idOf(t.bushing), store), 2000);
      // and the list was not kept: the box is already on the shelf
      await tapKey(tester, 'nav-inventory');
      await settle(tester);
      await tapKey(tester, 'stock-intake');
      await settle(tester);
      expect(key('intake-empty'), findsOneWidget);
    });

    testWidgets('lines that could not be looked up retry when asked', (
      tester,
    ) async {
      final t = intakeRig();
      await openIntake(tester, t.rig);
      t.rig.server.reachable = false;
      await scanByKeyboard(tester, 'MB-025153');
      expect(find.textContaining('Нет связи'), findsWidgets);
      t.rig.server.reachable = true;
      if (key('intake-retry-MB-025153').evaluate().isNotEmpty) {
        await tapKey(tester, 'intake-retry-MB-025153');
      }
      await settle(tester);
      expect(find.text('Сайлентблок рессоры Canter'), findsOneWidget);
    });
  });

  group('costs and rights', () {
    testWidgets('an owner can add a cost, and it becomes the layer cost', (
      tester,
    ) async {
      final t = intakeRig();
      await openIntake(tester, t.rig);
      await scanByKeyboard(tester, 'MB-025153');
      expect(
        key('intake-cost-note'),
        findsOneWidget,
      ); // no cost yet: says what that means
      await tapKey(tester, 'intake-qty-MB-025153');
      await settle(tester, ms: 400);
      await tester.enterText(key('intake-edit-qty'), '10');
      await tester.enterText(key('intake-edit-cost'), '35,50');
      await tapKey(tester, 'intake-edit-save');
      await settle(tester, ms: 400);
      expect(find.textContaining('35,50'), findsOneWidget);
      expect(key('intake-cost-note'), findsNothing);
      await sendIntake(tester);
      final move = t.rig.server.ledger.movements.firstWhere(
        (m) => m['movement_type'] == 'intake',
      );
      expect(move['unit_cost'], '35.50');
      expect(move['quantity'], '10.000');
    });

    testWidgets('a keeper sees no cost field and sends none', (tester) async {
      final t = intakeRig();
      t.rig.server.permissions.remove('stock.cost.view');
      await openIntake(tester, t.rig);
      await scanByKeyboard(tester, 'MB-025153');
      expect(key('intake-cost-note'), findsNothing);
      await tapKey(tester, 'intake-qty-MB-025153');
      await settle(tester, ms: 400);
      expect(key('intake-edit-cost'), findsNothing);
      await tester.enterText(key('intake-edit-qty'), '4');
      await tapKey(tester, 'intake-edit-save');
      await settle(tester, ms: 400);
      await sendIntake(tester);
      expect(t.rig.server.ledger.quantityOf(idOf(t.bushing), store), 4000);
      final move = t.rig.server.ledger.movements.firstWhere(
        (m) => m['movement_type'] == 'intake',
      );
      expect(move['unit_cost'], '0.00');
    });

    testWidgets('without the right the button is not offered', (tester) async {
      final t = intakeRig();
      t.rig.server.permissions.remove('intake.create');
      await t.rig.launchSignedIn(tester);
      await tapKey(tester, 'nav-inventory');
      await settle(tester);
      expect(key('stock-intake'), findsNothing);
    });
  });

  group('for people who use the screen', () {
    testWidgets('the fields have names a screen reader can say', (
      tester,
    ) async {
      final t = intakeRig();
      await openIntake(tester, t.rig);
      await scanByKeyboard(tester, 'MB-025153');
      expect(fieldNames(tester), contains(startsWith('Код товара')));
      expect(fieldNames(tester), contains('Примечание'));
    });

    for (final size in [const Size(360, 740), const Size(800, 1100)]) {
      testWidgets('it fits $size with a long list and doubled text', (
        tester,
      ) async {
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final t = intakeRig();
        await t.rig.launch(tester, size: size);
        await t.rig.signIn(tester);
        await navigate(tester, 'nav-inventory', size);
        await tapKey(tester, 'stock-intake');
        await settle(tester);
        for (final code in ['MB-025153', '444083', 'UNKNOWN-1']) {
          await scanByKeyboard(tester, code);
        }
        expect(tester.takeException(), isNull);
        await tapKey(tester, 'intake-add-UNKNOWN-1');
        await settle(tester, ms: 600);
        expect(tester.takeException(), isNull);
        expect(key('intake-new-name'), findsOneWidget);
      });
    }
  });

  group('codes', () {
    test(
      'a quickly added product counts pieces when the business has such a unit',
      () {
        UnitRef unit(String name, String symbol, int decimals) => UnitRef(
          id: name,
          name: name,
          symbol: symbol,
          decimalPlaces: decimals,
        );
        final set = [
          unit('Комплект', 'компл', 0), // first alphabetically, but not pieces
          unit('Литр', 'л', 2),
          unit('Штука', 'шт', 0),
        ];
        expect(defaultPieceUnit(set)?.name, 'Штука');
        expect(
          defaultPieceUnit([
            unit('Toplum', 'top', 0),
            unit('Sany', 'sany', 0),
          ])?.name,
          'Sany',
        );
        expect(
          defaultPieceUnit([
            unit('Коробка', 'кор', 0),
            unit('Литр', 'л', 2),
          ])?.name,
          'Коробка',
        );
        expect(defaultPieceUnit([unit('Литр', 'л', 2)])?.name, 'Литр');
        expect(defaultPieceUnit(const []), isNull);
      },
    );

    test('only a short single token can be an article number', () {
      expect(codeFitsAsArticle('MH044089'), isTrue);
      expect(codeFitsAsArticle('8-97096777-0'), isTrue);
      expect(codeFitsAsArticle('https://example.com/x'), isFalse);
      expect(codeFitsAsArticle('two words'), isFalse);
      expect(codeFitsAsArticle('A' * 65), isFalse);
      expect(codeFitsAsArticle(''), isFalse);
    });
  });
}
