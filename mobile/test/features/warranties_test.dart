import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/real_rig.dart';
import 'catalog_test.dart' show seedProduct;
import 'stock_ops_test.dart' show canPress, fieldNames;

const store = 'l-1';

({RealRig rig, Map<String, dynamic> pad, Map<String, dynamic> sale})
warrantyRig({int months = 12}) {
  final rig = RealRig();
  final pad = seedProduct(
    rig.server,
    sku: 'BP-1',
    name: 'Тормозные колодки',
    warrantyMonths: months,
    warrantyTerms: 'Только при установке в сервисе.',
  );
  final id = pad['id'] as String;
  rig.server.ledger.seedStock(id, store, '10', '50.00');
  final sale = rig.server.ledger.seedSale(
    productId: id,
    locationId: store,
    quantity: '4',
    price: '100.00',
  );
  return (rig: rig, pad: pad, sale: sale);
}

String idOf(Map<String, dynamic> product) => product['id'] as String;

Future<void> openSale(WidgetTester tester, RealRig rig) async {
  await rig.launchSignedIn(tester);
  await tapKey(tester, 'nav-sales');
  await settle(tester);
  await tapKey(tester, 'sales-history');
  await settle(tester);
  await tapKey(tester, 'sale-S-000001');
  await settle(tester);
}

/// From the sale: choose the line, say what is wrong, open the claim.
Future<void> openClaim(
  WidgetTester tester, {
  String quantity = '1',
  String problem = 'Скрипят при торможении',
  String? overrideNote,
}) async {
  await tapKey(tester, 'sd-warranty');
  await settle(tester);
  await tapKey(tester, 'wn-line-BP-1');
  await settle(tester, ms: 200);
  await tester.ensureVisible(key('wn-qty'));
  await tester.enterText(key('wn-qty'), quantity);
  await tester.enterText(key('wn-problem'), problem);
  if (overrideNote != null) {
    await tester.ensureVisible(key('wn-override-note'));
    await tester.enterText(key('wn-override-note'), overrideNote);
  }
  await tester.pump();
  await tapKey(tester, 'wn-open');
  await settle(tester);
}

/// Starts the app again (the session is kept) and opens the claim W-0001.
Future<void> openClaimPage(WidgetTester tester, RealRig rig) async {
  await tester.pumpWidget(const SizedBox());
  await rig.launch(tester);
  await tapKey(tester, 'nav-warranties');
  await settle(tester);
  await tapKey(tester, 'warranty-W-0001');
  await settle(tester);
}

void main() {
  group('opening a claim', () {
    testWidgets('from the sale: the warranty shows and the claim is opened', (
      tester,
    ) async {
      final t = warrantyRig();
      await openSale(tester, t.rig);
      await tapKey(tester, 'sd-warranty');
      await settle(tester);
      expect(
        find.textContaining('Гарантия до'),
        findsOneWidget,
      ); // the date the server computed from the sale
      await tapKey(tester, 'wn-line-BP-1');
      await settle(tester, ms: 200);
      await tester.ensureVisible(key('wn-qty'));
      expect(canPress(tester, 'wn-open'), isFalse);
      await tester.enterText(key('wn-qty'), '1');
      await tester.enterText(key('wn-problem'), 'Скрипят');
      await tester.pump();
      await tapKey(tester, 'wn-open');
      await settle(tester);
      expect(t.rig.server.office.claimsOpened, 1);
      expect(find.text('Обращение W-0001 открыто.'), findsOneWidget);
      final claim = t.rig.server.office.claims.single;
      expect(claim['out_of_warranty'], false);
      expect(claim['quantity'], 1000);
    });

    testWidgets('a seller cannot accept a claim after the warranty is over', (
      tester,
    ) async {
      final t = warrantyRig();
      final line = (t.sale['lines'] as List).first as Map<String, dynamic>;
      line['warranty_until'] = '2020-01-01';
      t.rig.server.role = 'sales';
      t.rig.server.permissions = [
        'catalog.view',
        'sales.view',
        'sales.create',
        'warranty.view',
        'warranty.open',
      ];
      await openSale(tester, t.rig);
      await tapKey(tester, 'sd-warranty');
      await settle(tester);
      await tapKey(tester, 'wn-line-BP-1');
      await settle(tester, ms: 200);
      expect(find.textContaining('Гарантия закончилась'), findsOneWidget);
      await tester.ensureVisible(key('wn-blocked'));
      expect(key('wn-blocked'), findsOneWidget);
      await tester.enterText(key('wn-qty'), '1');
      await tester.enterText(key('wn-problem'), 'x');
      await tester.pump();
      expect(canPress(tester, 'wn-open'), isFalse);
      expect(t.rig.server.office.claimsOpened, 0);
    });

    testWidgets('an owner can accept it as an exception, with a reason', (
      tester,
    ) async {
      final t = warrantyRig(months: 0); // this product never had a warranty
      await openSale(tester, t.rig);
      await tapKey(tester, 'sd-warranty');
      await settle(tester);
      expect(find.text('Без гарантии'), findsOneWidget);
      await tapKey(tester, 'wn-line-BP-1');
      await settle(tester, ms: 200);
      await tester.ensureVisible(key('wn-qty'));
      await tester.enterText(key('wn-qty'), '1');
      await tester.enterText(key('wn-problem'), 'Сломалось');
      await tester.pump();
      expect(key('wn-override-hint'), findsOneWidget);
      expect(canPress(tester, 'wn-open'), isFalse); // the reason is needed
      await tester.enterText(key('wn-override-note'), 'Постоянный клиент');
      await tester.pump();
      await tapKey(tester, 'wn-open');
      await settle(tester);
      final claim = t.rig.server.office.claims.single;
      expect(claim['out_of_warranty'], true);
      expect((claim['events'] as List).first['note'], 'Постоянный клиент');
    });

    testWidgets('only what is left of the sale can be claimed', (tester) async {
      final t = warrantyRig();
      await openSale(tester, t.rig);
      await tapKey(tester, 'sd-warranty');
      await settle(tester);
      await tapKey(tester, 'wn-line-BP-1');
      await settle(tester, ms: 200);
      await tester.ensureVisible(key('wn-qty'));
      await tester.enterText(key('wn-qty'), '5'); // 4 were sold
      await tester.pump();
      expect(find.text('Некорректное значение.'), findsOneWidget);
    });

    testWidgets(
      'the claim can be started from the Warranties page by searching for the sale',
      (tester) async {
        final t = warrantyRig();
        await t.rig.launchSignedIn(tester);
        await tapKey(tester, 'nav-warranties');
        await settle(tester);
        expect(key('warranties-empty'), findsOneWidget);
        await tapKey(tester, 'warranty-new');
        await settle(tester);
        await tapKey(tester, 'wn-sale-S-000001');
        await settle(tester);
        expect(key('wn-sale'), findsOneWidget);
        await tapKey(tester, 'wn-line-BP-1');
        await settle(tester, ms: 200);
        await tester.ensureVisible(key('wn-qty'));
        await tester.enterText(key('wn-qty'), '2');
        await tester.enterText(key('wn-problem'), 'Стучит');
        await tester.pump();
        await tapKey(tester, 'wn-open');
        await settle(tester);
        expect(key('warranty-W-0001'), findsOneWidget);
      },
    );
  });

  group('closing a claim', () {
    Future<void> closeWith(
      WidgetTester tester,
      String outcome, {
      String note = '',
    }) async {
      await tester.ensureVisible(key('wd-outcome-$outcome'));
      await tapKey(tester, 'wd-outcome-$outcome');
      if (note.isNotEmpty) {
        await tester.enterText(key('wd-close-note'), note);
      }
      await tester.pump();
      await tapKey(tester, 'wd-close');
      await settle(tester, ms: 400);
      await tester.tap(find.text('Подтвердить').last);
      await settle(tester);
    }

    testWidgets('repair changes no stock and closes the claim', (tester) async {
      final t = warrantyRig();
      await openSale(tester, t.rig);
      await openClaim(tester);
      await openClaimPage(tester, t.rig);
      expect(key('wd-number'), findsOneWidget);
      await closeWith(tester, 'repair', note: 'Заменили колодки в сервисе');
      final office = t.rig.server.office;
      expect(office.claimsClosed, 1);
      expect(office.claims.single['outcome'], 'repair');
      expect(
        t.rig.server.ledger.quantityOf(idOf(t.pad), store),
        6000,
      ); // 10 - 4 sold; untouched
      expect(find.text('Обращение закрыто.'), findsOneWidget);
      expect(key('wd-close'), findsNothing); // a closed claim is final
    });

    testWidgets(
      'replacement gives a new piece and takes the defective one back',
      (tester) async {
        final t = warrantyRig();
        await openSale(tester, t.rig);
        await openClaim(tester);
        await openClaimPage(tester, t.rig);
        await closeWith(tester, 'replacement');
        final ledger = t.rig.server.ledger;
        expect(ledger.quantityOf(idOf(t.pad), store), 5000);
        expect(ledger.quantityOf(idOf(t.pad), store, 'damaged'), 1000);
      },
    );

    testWidgets('a refund returns the money through an ordinary return', (
      tester,
    ) async {
      final t = warrantyRig();
      await openSale(tester, t.rig);
      await openClaim(tester);
      await openClaimPage(tester, t.rig);
      await closeWith(tester, 'refund');
      final ledger = t.rig.server.ledger;
      expect(ledger.returnsRecorded, 1);
      expect(ledger.saleReturns.single['refund'], 10000); // 1 x 100,00
      expect(ledger.quantityOf(idOf(t.pad), store, 'damaged'), 1000);
      expect(find.text('Деньги возвращены: возврат R-0001'), findsOneWidget);
    });

    testWidgets('a rejection needs a reason', (tester) async {
      final t = warrantyRig();
      await openSale(tester, t.rig);
      await openClaim(tester);
      await openClaimPage(tester, t.rig);
      await tester.ensureVisible(key('wd-outcome-rejected'));
      await tapKey(tester, 'wd-outcome-rejected');
      await tester.pump();
      expect(canPress(tester, 'wd-close'), isFalse);
      await tester.enterText(key('wd-close-note'), 'Следы удара');
      await tester.pump();
      expect(canPress(tester, 'wd-close'), isTrue);
    });

    testWidgets('notes are added to the history of an open claim', (
      tester,
    ) async {
      final t = warrantyRig();
      await openSale(tester, t.rig);
      await openClaim(tester);
      await openClaimPage(tester, t.rig);
      await tester.enterText(key('wd-note'), 'Звонил клиенту');
      await tester.pump();
      await tapKey(tester, 'wd-add-note');
      await settle(tester);
      expect(find.text('Звонил клиенту'), findsOneWidget);
    });

    testWidgets('answer lost then the tablet restarts: closed exactly once', (
      tester,
    ) async {
      final t = warrantyRig();
      await openSale(tester, t.rig);
      await openClaim(tester);
      await openClaimPage(tester, t.rig);
      t.rig.server.dropResponseAfterCommit = 1;
      await closeWith(tester, 'replacement');
      expect(find.textContaining('Ответ сервера не получен'), findsOneWidget);
      expect(t.rig.store.backing.single.action, 'warranty_resolve');
      expect(t.rig.server.office.claimsClosed, 1);
      await tester.pumpWidget(const SizedBox());
      await t.rig.launch(tester);
      await settle(tester);
      expect(key('pending-banner'), findsNothing);
      expect(t.rig.store.backing, isEmpty);
      expect(t.rig.server.office.claimsClosed, 1);
      expect(t.rig.server.ledger.quantityOf(idOf(t.pad), store), 5000);
    });

    testWidgets('a seller can open and follow claims but not close them', (
      tester,
    ) async {
      final t = warrantyRig();
      await openSale(tester, t.rig);
      await openClaim(tester);
      await tester.pumpWidget(const SizedBox());
      t.rig.server.role = 'sales';
      t.rig.server.permissions = [
        'catalog.view',
        'sales.view',
        'warranty.view',
        'warranty.open',
      ];
      await openClaimPage(tester, t.rig);
      expect(key('wd-note'), findsOneWidget);
      expect(key('wd-close'), findsNothing);
    });

    testWidgets('every text field keeps its own name for a screen reader', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final t = warrantyRig();
      await openSale(tester, t.rig);
      await tapKey(tester, 'sd-warranty');
      await settle(tester);
      await tapKey(tester, 'wn-line-BP-1');
      await settle(tester, ms: 200);
      expect(fieldNames(tester), ['Количество', 'Что случилось (обязательно)']);
      handle.dispose();
    });

    for (final size in [const Size(360, 800), const Size(800, 1100)]) {
      testWidgets('warranty screens fit at $size with doubled text', (
        tester,
      ) async {
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final t = warrantyRig();
        await t.rig.launch(tester, size: size);
        await t.rig.signIn(tester);
        if (size.width < 600) {
          await tester.tap(find.byTooltip('Меню'));
          await settle(tester, ms: 400);
          await tester.scrollUntilVisible(
            key('nav-sales'),
            200,
            scrollable: find.descendant(
              of: find.byType(Drawer),
              matching: find.byType(Scrollable),
            ),
          );
        }
        await tapKey(tester, 'nav-sales');
        await settle(tester);
        await tapKey(tester, 'sales-history');
        await settle(tester);
        await tapKey(tester, 'sale-S-000001');
        await settle(tester);
        expect(tester.takeException(), isNull, reason: 'sale');
        await tapKey(tester, 'sd-warranty');
        await settle(tester);
        expect(tester.takeException(), isNull, reason: 'lines');
        await tapKey(tester, 'wn-line-BP-1');
        await settle(tester, ms: 300);
        expect(tester.takeException(), isNull, reason: 'form');
      });
    }
  });
}
