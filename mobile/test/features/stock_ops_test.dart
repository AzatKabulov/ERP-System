import 'package:erp_system/widgets/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/real_rig.dart';
import 'catalog_test.dart' show seedProduct;

/// Whether the filled button with this key can be pressed.
bool canPress(WidgetTester tester, String name) =>
    tester.widget<GradientButton>(key(name)).onPressed != null;

/// The names a screen reader gives every text field on screen.
List<String> fieldNames(WidgetTester tester) {
  final names = <String>[];
  void walk(SemanticsNode node) {
    // ignore: deprecated_member_use
    if (node.getSemanticsData().flagsCollection.isTextField) {
      names.add(node.label);
    }
    node.visitChildren((child) {
      walk(child);
      return true;
    });
  }

  // ignore: deprecated_member_use
  walk(tester.binding.pipelineOwner.semanticsOwner!.rootSemanticsNode!);
  return names;
}

const store = 'l-1'; // Esasy dükan, where the signed-in user starts
const warehouse = 'l-2'; // Ammar

({RealRig rig, Map<String, dynamic> pad}) opsRig({int stock = 10}) {
  final rig = RealRig();
  final pad = seedProduct(rig.server, sku: 'BP-1', name: 'Тормозные колодки');
  rig.server.ledger.seedStock(pad['id'] as String, store, '$stock', '50.00');
  return (rig: rig, pad: pad);
}

String idOf(Map<String, dynamic> product) => product['id'] as String;

Future<void> openStock(WidgetTester tester, RealRig rig) async {
  await rig.launchSignedIn(tester);
  await tapKey(tester, 'nav-inventory');
  await settle(tester);
}

Future<void> openTransfers(WidgetTester tester, RealRig rig) async {
  await openStock(tester, rig);
  await tapKey(tester, 'stock-transfers');
  await settle(tester);
}

Future<void> openCounts(WidgetTester tester, RealRig rig) async {
  await openStock(tester, rig);
  await tapKey(tester, 'stock-counts');
  await settle(tester);
}

/// Fills the transfer form: destination Ammar, the first product, [quantity] pieces.
Future<void> fillTransfer(WidgetTester tester, {String quantity = '4'}) async {
  await tapKey(tester, 'transfer-new');
  await settle(tester);
  await tapKey(tester, 'transfer-to');
  await settle(tester, ms: 400);
  await tester.tap(find.text('Ammar').last);
  await settle(tester, ms: 400);
  await tapKey(tester, 'transfer-add-line');
  await settle(tester, ms: 600);
  await tester.tap(key('picker-BP-1'));
  await settle(tester, ms: 400);
  await tester.enterText(key('transfer-qty-0'), quantity);
  await tester.pump();
}

Future<void> sendTransfer(WidgetTester tester, {String quantity = '4'}) async {
  await fillTransfer(tester, quantity: quantity);
  await tapKey(tester, 'transfer-submit');
  await settle(tester);
}

Future<void> openFirstTransfer(WidgetTester tester) async {
  await tapKey(tester, 'transfer-T-0001');
  await settle(tester);
}

void main() {
  group('transfers', () {
    testWidgets('sending goods takes them out and leaves them in transit', (
      tester,
    ) async {
      final t = opsRig();
      await openTransfers(tester, t.rig);
      expect(key('transfers-empty'), findsOneWidget);
      await sendTransfer(tester);
      final ledger = t.rig.server.ledger;
      expect(find.text('Перемещение отправлено.'), findsOneWidget);
      expect(ledger.transfersDispatched, 1);
      expect(ledger.quantityOf(idOf(t.pad), store), 6000);
      expect(
        ledger.quantityOf(idOf(t.pad), warehouse),
        0,
      ); // not sellable there yet
      expect(ledger.quantityOf(idOf(t.pad), warehouse, 'in_transit'), 4000);
      expect(key('transfer-T-0001'), findsOneWidget);
      expect(find.text('В пути'), findsWidgets);
      expect(t.rig.store.backing, isEmpty);
    });

    testWidgets('the form needs a destination and valid quantities', (
      tester,
    ) async {
      final t = opsRig();
      await openTransfers(tester, t.rig);
      await tapKey(tester, 'transfer-new');
      await settle(tester);
      await tapKey(tester, 'transfer-submit');
      expect(key('transfer-needs-lines'), findsOneWidget);
      expect(t.rig.server.ledger.transfersDispatched, 0);
      await tapKey(tester, 'transfer-add-line');
      await settle(tester, ms: 600);
      await tester.tap(key('picker-BP-1'));
      await settle(tester, ms: 400);
      await tester.enterText(key('transfer-qty-0'), '1,5'); // pieces are whole
      await tester.pump();
      await tapKey(tester, 'transfer-submit');
      expect(
        find.text('Для этой единицы допускается меньше знаков после запятой.'),
        findsOneWidget,
      );
      expect(t.rig.server.ledger.transfersDispatched, 0);
    });

    testWidgets('more than is on the shelf is refused, naming the product', (
      tester,
    ) async {
      final t = opsRig(stock: 2);
      await openTransfers(tester, t.rig);
      await sendTransfer(tester, quantity: '5');
      expect(
        find.text('Недостаточно товара «Тормозные колодки»: в наличии 2 шт.'),
        findsOneWidget,
      );
      expect(t.rig.server.ledger.transfersDispatched, 0);
      expect(t.rig.server.ledger.quantityOf(idOf(t.pad), store), 2000);
      expect(t.rig.store.backing, isEmpty); // a refusal is definite
    });

    testWidgets('receiving everything makes the goods sellable there', (
      tester,
    ) async {
      final t = opsRig();
      await openTransfers(tester, t.rig);
      await sendTransfer(tester);
      await openFirstTransfer(tester);
      expect(
        find.text('Товар в пути и пока не доступен для продажи.'),
        findsOneWidget,
      );
      await tapKey(tester, 'td-receive');
      await settle(tester);
      await tapKey(tester, 'receive-confirm');
      await settle(tester);
      expect(find.text('Перемещение принято.'), findsOneWidget);
      expect(find.text('Принято'), findsWidgets);
      final ledger = t.rig.server.ledger;
      expect(ledger.quantityOf(idOf(t.pad), warehouse), 4000);
      expect(ledger.quantityOf(idOf(t.pad), warehouse, 'in_transit'), 0);
      expect(key('td-receive'), findsNothing); // done: nothing more to do
    });

    testWidgets(
      'arriving short needs a reason; the missing goods are written off',
      (tester) async {
        final t = opsRig();
        await openTransfers(tester, t.rig);
        await sendTransfer(tester);
        await openFirstTransfer(tester);
        await tapKey(tester, 'td-receive');
        await settle(tester);
        expect(
          key('receive-reason'),
          findsNothing,
        ); // everything arrives: no reason
        final line =
            (t.rig.server.ledger.transfers.single['lines'] as List).single
                as Map;
        await tester.enterText(key('receive-qty-${line['id']}'), '3');
        await tester.pump();
        expect(key('receive-reason'), findsOneWidget);
        expect(canPress(tester, 'receive-confirm'), isFalse); // no reason yet
        await tester.enterText(
          key('receive-reason'),
          'Одна коробка повреждена',
        );
        await tester.pump();
        expect(canPress(tester, 'receive-confirm'), isTrue);
        await tapKey(tester, 'receive-confirm');
        await settle(tester);
        expect(find.text('Принято не полностью'), findsWidgets);
        expect(find.textContaining('Одна коробка повреждена'), findsOneWidget);
        final ledger = t.rig.server.ledger;
        expect(ledger.quantityOf(idOf(t.pad), warehouse), 3000);
        expect(ledger.quantityOf(idOf(t.pad), warehouse, 'in_transit'), 0);
      },
    );

    testWidgets('cancelling needs a reason and sends everything back', (
      tester,
    ) async {
      final t = opsRig();
      await openTransfers(tester, t.rig);
      await sendTransfer(tester);
      await openFirstTransfer(tester);
      await tapKey(tester, 'td-cancel');
      await settle(tester, ms: 400);
      final confirm = tester.widget<FilledButton>(key('reason-confirm'));
      expect(confirm.onPressed, isNull); // a reason is required
      await tester.enterText(key('reason-field'), 'Не в тот магазин');
      await tester.pump();
      await tester.tap(key('reason-confirm'));
      await settle(tester);
      expect(
        find.text('Перемещение отменено, товар вернулся.'),
        findsOneWidget,
      );
      expect(find.text('Отменено'), findsWidgets);
      final ledger = t.rig.server.ledger;
      expect(ledger.quantityOf(idOf(t.pad), store), 10000);
      expect(ledger.quantityOf(idOf(t.pad), warehouse, 'in_transit'), 0);
    });

    testWidgets('answer lost then the tablet restarts: exactly one transfer', (
      tester,
    ) async {
      final t = opsRig();
      await openTransfers(tester, t.rig);
      t.rig.server.dropResponseAfterCommit = 1;
      await sendTransfer(tester);
      expect(find.textContaining('Ответ сервера не получен'), findsOneWidget);
      expect(t.rig.store.backing.single.action, 'transfer_dispatch');
      expect(t.rig.server.ledger.transfersDispatched, 1);
      await tester.pumpWidget(const SizedBox());
      await t.rig.launch(tester); // a fresh app on the same device storage
      await settle(tester);
      expect(
        key('pending-banner'),
        findsNothing,
      ); // the server confirmed the key
      expect(t.rig.store.backing, isEmpty);
      expect(t.rig.server.ledger.transfersDispatched, 1);
      expect(
        t.rig.server.ledger.quantityOf(idOf(t.pad), warehouse, 'in_transit'),
        4000,
      );
    });

    testWidgets('a receipt whose answer was lost is not applied twice', (
      tester,
    ) async {
      final t = opsRig();
      await openTransfers(tester, t.rig);
      await sendTransfer(tester);
      await openFirstTransfer(tester);
      await tapKey(tester, 'td-receive');
      await settle(tester);
      t.rig.server.dropResponseAfterCommit = 1;
      await tapKey(tester, 'receive-confirm');
      await settle(tester);
      expect(t.rig.server.ledger.transfersReceived, 1);
      expect(t.rig.store.backing.single.action, 'transfer_receive');
      final pendingKey = t.rig.store.backing.single.key;
      await tapKey(tester, 'pending-review');
      await settle(tester, ms: 400);
      await tapKey(tester, 'pending-retry-$pendingKey');
      await settle(tester);
      expect(
        t.rig.server.ledger.transfersReceived,
        1,
      ); // answered from the record
      expect(t.rig.server.ledger.quantityOf(idOf(t.pad), warehouse), 4000);
      expect(t.rig.store.backing, isEmpty);
    });

    testWidgets('every text field keeps its own name for a screen reader', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final t = opsRig();
      await openTransfers(tester, t.rig);
      await fillTransfer(tester);
      expect(fieldNames(tester), ['Количество', 'Примечание']);
      await tapKey(tester, 'transfer-submit');
      await settle(tester);
      await openFirstTransfer(tester);
      await tapKey(tester, 'td-receive');
      await settle(tester);
      expect(fieldNames(tester), ['Пришло']);
      handle.dispose();
    });

    testWidgets('a salesperson has no transfers or counts', (tester) async {
      final t = opsRig();
      t.rig.server.role = 'sales';
      t.rig.server.permissions = [
        'catalog.view',
        'stock.view',
        'location.view',
        'sales.view',
        'sales.create',
      ];
      await openStock(tester, t.rig);
      expect(key('stock-transfers'), findsNothing);
      expect(key('stock-counts'), findsNothing);
    });
  });

  group('stock counts', () {
    Future<void> startFull(WidgetTester tester) async {
      await tapKey(tester, 'count-new');
      await settle(tester);
      await tapKey(tester, 'count-start');
      await settle(tester);
    }

    Future<void> enter(WidgetTester tester, String sku, String text) async {
      await tester.enterText(key('count-counted-$sku'), text);
      await tester.pump();
    }

    testWidgets('start, count, send for approval, approve: stock is corrected', (
      tester,
    ) async {
      final t = opsRig();
      await openCounts(tester, t.rig);
      expect(key('counts-empty'), findsOneWidget);
      await startFull(tester);
      expect(find.text('Инвентаризация C-0001'), findsOneWidget);
      expect(find.text('В системе: 10 шт'), findsOneWidget);
      expect(canPress(tester, 'count-submit'), isFalse); // nothing counted yet
      await enter(tester, 'BP-1', '8');
      expect(find.text('Разница: −2 шт'), findsOneWidget);
      await tapKey(tester, 'count-save');
      await settle(tester);
      expect(find.text('Подсчёт сохранён.'), findsOneWidget);
      await tapKey(tester, 'count-submit');
      await settle(tester);
      expect(find.text('Отправлено на утверждение.'), findsOneWidget);
      expect(find.text('Ждёт утверждения'), findsWidgets);
      // the owner approves: an explanation is needed because something differs
      expect(find.text('Расхождений: 1'), findsOneWidget);
      expect(canPress(tester, 'count-approve'), isFalse);
      await tester.enterText(key('count-reason'), 'Две колодки были сломаны');
      await tester.pump();
      await tapKey(tester, 'count-approve');
      await settle(tester);
      expect(
        find.text('Инвентаризация утверждена, остатки исправлены.'),
        findsOneWidget,
      );
      expect(find.text('Утверждена'), findsWidgets);
      expect(t.rig.server.ledger.countsApproved, 1);
      expect(t.rig.server.ledger.quantityOf(idOf(t.pad), store), 8000);
      expect(t.rig.store.backing, isEmpty);
    });

    testWidgets('a count with no differences needs no explanation', (
      tester,
    ) async {
      final t = opsRig();
      await openCounts(tester, t.rig);
      await startFull(tester);
      await enter(tester, 'BP-1', '10');
      await tapKey(tester, 'count-submit');
      await settle(tester);
      expect(find.text('Расхождений нет.'), findsOneWidget);
      expect(key('count-reason'), findsNothing);
      await tapKey(tester, 'count-approve');
      await settle(tester);
      expect(find.text('Утверждена'), findsWidgets);
      expect(t.rig.server.ledger.quantityOf(idOf(t.pad), store), 10000);
    });

    testWidgets('sales during the count are kept and the line is flagged', (
      tester,
    ) async {
      final t = opsRig();
      await openCounts(tester, t.rig);
      await startFull(tester);
      // a sale happens while the keeper is counting: 3 pieces leave the shelf
      t.rig.server.ledger.seedStock(idOf(t.pad), store, '-3', '0');
      await enter(tester, 'BP-1', '9');
      await tapKey(tester, 'count-save');
      await settle(tester);
      expect(key('count-moved-BP-1'), findsOneWidget);
      await tapKey(tester, 'count-submit');
      await settle(tester);
      await tester.enterText(key('count-reason'), 'Одной не хватает');
      await tester.pump();
      await tapKey(tester, 'count-approve');
      await settle(tester);
      // 10 on the shelf at the start, 3 sold, one missing: 6 are left
      expect(t.rig.server.ledger.quantityOf(idOf(t.pad), store), 6000);
    });

    testWidgets('a product that was not on the list can be added and counted', (
      tester,
    ) async {
      final t = opsRig();
      final oil = seedProduct(t.rig.server, sku: 'OIL-1', name: 'Масло');
      await openCounts(tester, t.rig);
      await startFull(tester);
      expect(key('count-counted-OIL-1'), findsNothing); // nothing on its shelf
      await tapKey(tester, 'count-add-line');
      await settle(tester, ms: 600);
      await tester.tap(key('picker-OIL-1'));
      await settle(tester, ms: 400);
      await enter(tester, 'OIL-1', '4');
      await tapKey(tester, 'count-save');
      await settle(tester);
      expect(find.text('В системе: 0 шт'), findsOneWidget);
      expect(find.text('Разница: +4 шт'), findsOneWidget);
      expect(idOf(oil), isNotEmpty);
    });

    testWidgets('a partial count lists only the chosen products', (
      tester,
    ) async {
      final t = opsRig();
      seedProduct(t.rig.server, sku: 'OIL-1', name: 'Масло');
      await openCounts(tester, t.rig);
      await tapKey(tester, 'count-new');
      await settle(tester);
      await tapKey(tester, 'count-scope-partial');
      expect(
        canPress(tester, 'count-start'),
        isFalse,
      ); // choose at least one product
      await tapKey(tester, 'count-add-product');
      await settle(tester, ms: 600);
      await tester.tap(key('picker-OIL-1'));
      await settle(tester, ms: 400);
      await tapKey(tester, 'count-start');
      await settle(tester);
      expect(key('count-counted-OIL-1'), findsOneWidget);
      expect(key('count-counted-BP-1'), findsNothing);
    });

    testWidgets('the counting fields keep their own names too', (tester) async {
      final handle = tester.ensureSemantics();
      final t = opsRig();
      await openCounts(tester, t.rig);
      await startFull(tester);
      expect(fieldNames(tester), ['Посчитано']);
      handle.dispose();
    });

    testWidgets('a count can be cancelled and then changes nothing', (
      tester,
    ) async {
      final t = opsRig();
      await openCounts(tester, t.rig);
      await startFull(tester);
      await enter(tester, 'BP-1', '2');
      await tapKey(tester, 'count-cancel');
      await settle(tester, ms: 400);
      await tester.tap(key('reason-confirm'));
      await settle(tester);
      expect(find.text('Инвентаризация отменена.'), findsOneWidget);
      expect(find.text('Отменена'), findsWidgets);
      expect(key('count-approve'), findsNothing);
      expect(t.rig.server.ledger.quantityOf(idOf(t.pad), store), 10000);
    });

    testWidgets('a keeper counts but cannot approve', (tester) async {
      final t = opsRig();
      t.rig.server.role = 'warehouse';
      t.rig.server.permissions = [
        'catalog.view',
        'stock.view',
        'location.view',
        'count.view',
        'count.perform',
      ];
      await openCounts(tester, t.rig);
      await startFull(tester);
      await enter(tester, 'BP-1', '9');
      await tapKey(tester, 'count-submit');
      await settle(tester);
      expect(find.text('Ждёт утверждения'), findsWidgets);
      expect(key('count-approve'), findsNothing);
      expect(t.rig.server.ledger.quantityOf(idOf(t.pad), store), 10000);
    });

    testWidgets('approval answer lost then the tablet restarts: posted once', (
      tester,
    ) async {
      final t = opsRig();
      await openCounts(tester, t.rig);
      await startFull(tester);
      await enter(tester, 'BP-1', '8');
      await tapKey(tester, 'count-submit');
      await settle(tester);
      await tester.enterText(key('count-reason'), 'Сломаны');
      await tester.pump();
      t.rig.server.dropResponseAfterCommit = 1;
      await tapKey(tester, 'count-approve');
      await settle(tester);
      expect(t.rig.server.ledger.countsApproved, 1);
      expect(t.rig.store.backing.single.action, 'count_approve');
      await tester.pumpWidget(const SizedBox());
      await t.rig.launch(tester);
      await settle(tester);
      expect(key('pending-banner'), findsNothing);
      expect(t.rig.store.backing, isEmpty);
      expect(t.rig.server.ledger.countsApproved, 1);
      expect(t.rig.server.ledger.quantityOf(idOf(t.pad), store), 8000);
    });

    testWidgets('approval is refused when the goods were sold meanwhile', (
      tester,
    ) async {
      final t = opsRig();
      await openCounts(tester, t.rig);
      await startFull(tester);
      await enter(tester, 'BP-1', '4'); // six fewer than shown
      await tapKey(tester, 'count-submit');
      await settle(tester);
      t.rig.server.ledger.seedStock(
        idOf(t.pad),
        store,
        '-8',
        '0',
      ); // sold: 2 left
      await tester.enterText(key('count-reason'), 'Не хватает');
      await tester.pump();
      await tapKey(tester, 'count-approve');
      await settle(tester);
      expect(
        find.text('Недостаточно товара «Тормозные колодки»: в наличии 2 шт.'),
        findsOneWidget,
      );
      expect(t.rig.server.ledger.quantityOf(idOf(t.pad), store), 2000);
      expect(t.rig.server.ledger.countsApproved, 0);
    });
  });

  for (final size in [const Size(360, 800), const Size(800, 1100)]) {
    testWidgets('transfers and counts fit at $size with doubled text', (
      tester,
    ) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final t = opsRig();
      await t.rig.launch(tester, size: size);
      await t.rig.signIn(tester);
      if (size.width < 600) {
        await tester.tap(find.byTooltip('Меню'));
        await settle(tester, ms: 400);
        await tester.scrollUntilVisible(
          key('nav-inventory'),
          200,
          scrollable: find.descendant(
            of: find.byType(Drawer),
            matching: find.byType(Scrollable),
          ),
        );
      }
      await tapKey(tester, 'nav-inventory');
      await settle(tester);
      await tapKey(tester, 'stock-transfers');
      await settle(tester);
      expect(tester.takeException(), isNull);
      await fillTransfer(tester);
      expect(tester.takeException(), isNull);
      await tapKey(tester, 'transfer-submit');
      await settle(tester);
      expect(tester.takeException(), isNull);
      await openFirstTransfer(tester);
      expect(tester.takeException(), isNull);
      await tapKey(tester, 'td-receive');
      await settle(tester);
      expect(tester.takeException(), isNull);
      await goBack(tester);
      await goBack(tester);
      await goBack(tester);
      await tapKey(tester, 'stock-counts');
      await settle(tester);
      await tapKey(tester, 'count-new');
      await settle(tester);
      await tapKey(tester, 'count-start');
      await settle(tester);
      expect(tester.takeException(), isNull);
      // the list is lazy: scroll the line into view as a person would
      await tester.scrollUntilVisible(
        key('count-counted-BP-1'),
        200,
        scrollable: find
            .descendant(
              of: find.byType(ListView).last,
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.enterText(key('count-counted-BP-1'), '3');
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  }
}
