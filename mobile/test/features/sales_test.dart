import 'package:erp_system/core/money/decimal_math.dart';
import 'package:erp_system/widgets/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_scanner.dart';
import '../support/real_rig.dart';
import 'catalog_test.dart' show seedProduct;

const store = 'l-1'; // Esasy dükan, the signed-in user's starting location

String tmt(int minor) => formatMoney(minor, 'TMT');

/// Whether the filled button with this key can be pressed.
bool canPress(WidgetTester tester, String name) =>
    tester.widget<GradientButton>(key(name)).onPressed != null;

/// What is typed in the text field with this key.
String typed(WidgetTester tester, String name) =>
    tester.widget<TextField>(key(name)).controller!.text;

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

/// A rig with one product at 100,00 and [stock] pieces on the shelf of the current location.
({RealRig rig, Map<String, dynamic> pad}) deskRig({
  int stock = 10,
  String price = '100.00',
  RealRig? rig,
}) {
  final r = rig ?? RealRig();
  final pad = seedProduct(
    r.server,
    sku: 'BP-1',
    name: 'Тормозные колодки',
    price: price,
    barcodes: ['4006381333931'],
  );
  r.server.ledger.seedStock(pad['id'] as String, store, '$stock', '50.00');
  return (rig: r, pad: pad);
}

Future<void> openSales(WidgetTester tester, RealRig rig) async {
  await rig.launchSignedIn(tester);
  await tapKey(tester, 'nav-sales');
  await settle(tester);
}

/// Searches and taps the result, which puts one unit in the cart.
Future<void> addToCart(
  WidgetTester tester, {
  String query = 'колодки',
  String sku = 'BP-1',
}) async {
  await tester.enterText(key('sales-search'), query);
  await settle(tester, ms: 600);
  await tapKey(tester, 'sell-$sku');
  await settle(tester, ms: 400);
}

Future<void> setQuantity(
  WidgetTester tester,
  String text, {
  int line = 0,
}) async {
  await tester.enterText(key('cart-qty-$line'), text);
  await tester.pump();
}

Future<void> setPrice(WidgetTester tester, String text, {int line = 0}) async {
  await tester.enterText(key('cart-price-$line'), text);
  await tester.pump();
}

/// "Continue" on the cart: opens the last step, where the customer's payment is chosen.
Future<void> checkout(WidgetTester tester) async {
  await tapKey(tester, 'cart-checkout');
  await settle(tester);
}

Future<void> confirm(WidgetTester tester) async {
  await tapKey(tester, 'checkout-confirm');
  await settle(tester);
}

void main() {
  group('the cart', () {
    testWidgets('every text field keeps its own name for a screen reader', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final t = deskRig();
      await openSales(tester, t.rig);
      expect(fieldNames(tester), ['Название, артикул или штрихкод']);
      await addToCart(tester);
      expect(fieldNames(tester), [
        'Название, артикул или штрихкод',
        'Количество',
        'Цена за единицу, TMT',
      ]);
      await checkout(tester);
      expect(fieldNames(tester), isEmpty); // the last step has no typing at all
      handle.dispose();
    });

    testWidgets('starts empty, with a hint and no demo data', (tester) async {
      final t = deskRig();
      await openSales(tester, t.rig);
      expect(key('sales-start'), findsOneWidget);
      expect(key('cart-empty'), findsOneWidget);
      expect(find.text('Завершить демо-продажу'), findsNothing);
      expect(key('cart-checkout'), findsNothing);
      expect(key('sales-history'), findsOneWidget);
    });

    testWidgets(
      'search finds a product; adding it shows the price to change and what is in stock',
      (tester) async {
        final t = deskRig();
        await openSales(tester, t.rig);
        await addToCart(tester);
        expect(key('cart-qty-0'), findsOneWidget);
        expect(
          typed(tester, 'cart-price-0'),
          '100,00',
        ); // the catalog price, editable
        expect(find.textContaining('В наличии здесь: 10 шт'), findsOneWidget);
        expect(
          find.textContaining('В каталоге: ${tmt(10000)}'),
          findsOneWidget,
        );
        expect(find.text('Итого: ${tmt(10000)}'), findsOneWidget);
        expect(find.text('Добавлено: Тормозные колодки'), findsOneWidget);
        expect(t.rig.server.ledger.salesRecorded, 0); // adding sells nothing
        await tester.enterText(key('sales-search'), 'ничего подобного');
        await settle(tester, ms: 600);
        expect(key('sales-no-match'), findsOneWidget);
      },
    );

    testWidgets(
      'quantity buttons and typing follow the unit; totals use exact maths',
      (tester) async {
        final t = deskRig();
        await openSales(tester, t.rig);
        await addToCart(tester);
        await tapKey(tester, 'cart-plus-0');
        await tapKey(tester, 'cart-plus-0');
        expect(find.text('Итого: ${tmt(30000)}'), findsOneWidget);
        await tapKey(tester, 'cart-minus-0');
        expect(find.text('Итого: ${tmt(20000)}'), findsOneWidget);
        await setQuantity(tester, '1,5'); // pieces are whole
        expect(key('cart-problem-0'), findsOneWidget);
        expect(
          find.text(
            'Для этой единицы допускается меньше знаков после запятой.',
          ),
          findsOneWidget,
        );
        expect(canPress(tester, 'cart-checkout'), isFalse);
      },
    );

    testWidgets(
      'more than is on the shelf is flagged, and the next step stays off',
      (tester) async {
        final t = deskRig(stock: 10);
        await openSales(tester, t.rig);
        await addToCart(tester);
        await setQuantity(tester, '11');
        expect(find.text('Больше, чем в наличии (10 шт).'), findsOneWidget);
        expect(canPress(tester, 'cart-checkout'), isFalse);
      },
    );

    testWidgets('the seller can charge any price: lower, higher or nothing', (
      tester,
    ) async {
      final t = deskRig();
      await openSales(tester, t.rig);
      await addToCart(tester);
      await setQuantity(tester, '3');
      await setPrice(tester, '60');
      expect(find.text('Итого: ${tmt(18000)}'), findsOneWidget);
      await setPrice(tester, '150,50');
      expect(find.text('Итого: ${tmt(45150)}'), findsOneWidget);
      await setPrice(tester, '0');
      expect(find.text('Итого: ${tmt(0)}'), findsOneWidget);
      expect(
        canPress(tester, 'cart-checkout'),
        isTrue,
      ); // a free item is allowed
      await setPrice(tester, '');
      expect(key('cart-problem-0'), findsOneWidget);
      expect(canPress(tester, 'cart-checkout'), isFalse);
      await setPrice(tester, '12,345'); // not a price: more than two decimals
      expect(key('cart-problem-0'), findsOneWidget);
      expect(canPress(tester, 'cart-checkout'), isFalse);
      await setPrice(tester, '-5');
      expect(canPress(tester, 'cart-checkout'), isFalse);
    });

    testWidgets('adding the same product again adds a unit, not a price', (
      tester,
    ) async {
      final t = deskRig();
      await openSales(tester, t.rig);
      await addToCart(tester);
      await setPrice(tester, '80');
      await addToCart(tester); // the same product once more
      expect(typed(tester, 'cart-qty-0'), '2');
      expect(typed(tester, 'cart-price-0'), '80'); // the seller's price is kept
      expect(find.text('Итого: ${tmt(16000)}'), findsOneWidget);
    });

    testWidgets('scanning puts the product in the cart and sells nothing', (
      tester,
    ) async {
      final scanner = FakeScanner(results: ['4006381333931', '0000000000000']);
      final t = deskRig(rig: RealRig(scanner: scanner));
      await openSales(tester, t.rig);
      await tapKey(tester, 'scan-button');
      await settle(tester);
      expect(key('cart-qty-0'), findsOneWidget);
      expect(find.text('Итого: ${tmt(10000)}'), findsOneWidget);
      await tapKey(tester, 'scan-button'); // a code nobody has
      await settle(tester);
      expect(
        find.text('Товар с кодом 0000000000000 не найден.'),
        findsOneWidget,
      );
      expect(key('cart-qty-1'), findsNothing);
      expect(t.rig.server.ledger.salesRecorded, 0);
    });

    testWidgets(
      'a hand scanner that types the code and presses Enter fills the cart',
      (tester) async {
        final t = deskRig();
        await openSales(tester, t.rig);
        Future<void> scan(String code) async {
          await tester.enterText(key('sales-search'), code);
          await tester.testTextInput.receiveAction(TextInputAction.done);
          await settle(tester, ms: 500);
        }

        await scan('4006381333931'); // the barcode
        expect(typed(tester, 'cart-qty-0'), '1');
        await scan('bp-1'); // the article number, any letter case
        expect(typed(tester, 'cart-qty-0'), '2');
        expect(find.text('Итого: ${tmt(20000)}'), findsOneWidget);
        expect(typed(tester, 'sales-search'), ''); // ready for the next item
        await scan('колодки'); // a name is an ordinary search, nothing is added
        expect(typed(tester, 'cart-qty-0'), '2');
        expect(key('sell-BP-1'), findsOneWidget);
        await scan(
          '0000000000000',
        ); // a code nobody has: a search, no complaint, nothing added
        expect(key('cart-qty-1'), findsNothing);
        expect(t.rig.server.ledger.salesRecorded, 0);
      },
    );

    testWidgets(
      'a USD-priced product with no rate is sold at the price the seller types',
      (tester) async {
        final rig = RealRig();
        final usd = seedProduct(
          rig.server,
          sku: 'USD-1',
          name: 'Imported filter',
          price: '10.00',
          currency: 'USD',
        );
        rig.server.ledger.seedStock(usd['id'] as String, store, '5', '20');
        await openSales(tester, rig);
        await addToCart(tester, query: 'imported', sku: 'USD-1');
        expect(
          typed(tester, 'cart-price-0'),
          '',
        ); // no rate: nothing to suggest
        expect(canPress(tester, 'cart-checkout'), isFalse);
        await setPrice(tester, '35');
        expect(canPress(tester, 'cart-checkout'), isTrue);
        await checkout(tester);
        await confirm(tester);
        expect(key('sale-done'), findsOneWidget);
        final line =
            (rig.server.ledger.sales.single['lines'] as List).single as Map;
        expect(line['unit_price'], 3500);
      },
    );

    testWidgets('the cart survives a page change and a language change', (
      tester,
    ) async {
      final t = deskRig();
      await openSales(tester, t.rig);
      await addToCart(tester);
      await setPrice(tester, '90');
      await tapKey(tester, 'nav-inventory');
      await settle(tester);
      await tapKey(tester, 'nav-sales');
      await settle(tester);
      expect(key('cart-qty-0'), findsOneWidget);
      expect(
        typed(tester, 'cart-price-0'),
        '90',
      ); // the typed price is kept too
      await tapKey(tester, 'language-selector');
      await settle(tester, ms: 400);
      await tester.tap(find.text('Türkmençe').last);
      await settle(tester, ms: 600);
      expect(key('cart-qty-0'), findsOneWidget);
      expect(
        find.text('Sebet'),
        findsOneWidget,
      ); // the cart title, now in Turkmen
      expect(find.text('Jemi: ${tmt(9000)}'), findsOneWidget);
    });

    testWidgets('leaving with a cart asks before switching location', (
      tester,
    ) async {
      final t = deskRig();
      await openSales(tester, t.rig);
      await addToCart(tester);
      await tapKey(tester, 'location-selector');
      await settle(tester, ms: 400);
      await tester.tap(find.text('Ammar').last);
      await settle(tester, ms: 400);
      expect(find.text('Подтвердить'), findsOneWidget);
      await tester.tap(find.text('Подтвердить'));
      await settle(tester, ms: 600);
      expect(
        key('cart-empty'),
        findsOneWidget,
      ); // a cart belongs to one location
    });
  });

  group('saving a sale', () {
    testWidgets(
      'the price typed by the seller is what is saved; cash is the default; stock falls once',
      (tester) async {
        final t = deskRig();
        await openSales(tester, t.rig);
        await addToCart(tester);
        await setQuantity(tester, '3');
        await setPrice(tester, '90');
        await checkout(tester);
        expect(find.text('Итого: ${tmt(27000)}'), findsWidgets);
        expect(
          tester.widget<ChoiceChip>(key('pay-cash')).selected,
          isTrue,
        ); // cash unless said otherwise
        await confirm(tester);
        expect(key('sale-done'), findsOneWidget);
        expect(find.text('Продажа S-000001 оформлена'), findsOneWidget);
        expect(
          find.textContaining('Сдача'),
          findsNothing,
        ); // no change to work out
        expect(t.rig.server.ledger.salesRecorded, 1);
        expect(
          t.rig.server.ledger.quantityOf(t.pad['id'] as String, store),
          7000,
        );
        expect(key('cart-empty'), findsOneWidget);
        expect(t.rig.store.backing, isEmpty);
        final sale = t.rig.server.ledger.sales.single;
        expect((sale['total'], sale['payment_method']), (27000, 'cash'));
        // what was sent: the seller's price and how it was paid, nothing else about money
        final sent = t.rig.server.records.values.single;
        expect(sent.status, 201);
        expect(sent.body['payment_method'], 'cash');
        expect(sent.body.containsKey('payments'), isFalse);
        expect(sent.body.containsKey('expected_total'), isFalse);
        final line = ((sent.body['lines'] as List).single as Map);
        expect(line['quantity'], '3.000');
        expect(line['unit_price'], '90.00');
        expect(line.containsKey('discount'), isFalse);
      },
    );

    testWidgets('card can be chosen instead', (tester) async {
      final t = deskRig();
      await openSales(tester, t.rig);
      await addToCart(tester);
      await checkout(tester);
      await tapKey(tester, 'pay-card');
      expect(tester.widget<ChoiceChip>(key('pay-card')).selected, isTrue);
      expect(tester.widget<ChoiceChip>(key('pay-cash')).selected, isFalse);
      await confirm(tester);
      expect(t.rig.server.ledger.sales.single['payment_method'], 'card');
    });

    testWidgets('a free sale (price zero) can be saved', (tester) async {
      final t = deskRig();
      await openSales(tester, t.rig);
      await addToCart(tester);
      await setPrice(tester, '0');
      await checkout(tester);
      await confirm(tester);
      expect(key('sale-done'), findsOneWidget);
      expect(t.rig.server.ledger.sales.single['total'], 0);
    });

    testWidgets(
      'selling more than another tablet left is refused, naming the product',
      (tester) async {
        final t = deskRig();
        await openSales(tester, t.rig);
        await addToCart(tester);
        await setQuantity(tester, '3');
        await checkout(tester);
        // meanwhile another tablet sold 8: two are left
        t.rig.server.ledger.seedStock(t.pad['id'] as String, store, '-8', '0');
        await confirm(tester);
        expect(
          find.text('Недостаточно товара «Тормозные колодки»: в наличии 2 шт.'),
          findsOneWidget,
        );
        expect(t.rig.server.ledger.salesRecorded, 0);
        expect(
          t.rig.server.ledger.quantityOf(t.pad['id'] as String, store),
          2000,
        );
        expect(t.rig.store.backing, isEmpty); // a refusal is definite
        expect(
          key('checkout-confirm'),
          findsOneWidget,
        ); // still here to go back and fix it
      },
    );

    testWidgets('the customer chosen on the sale goes on it', (tester) async {
      final t = deskRig();
      t.rig.server.ledger.customers.add({
        'id': 'cu-seed',
        'name': 'Ýusup Ataýew',
        'phone': '+993 65',
        'notes': '',
        'is_active': true,
        'created_at': '2026-10-06T10:00:00Z',
      });
      await openSales(tester, t.rig);
      await addToCart(tester);
      await tapKey(tester, 'cart-customer');
      await settle(tester, ms: 600);
      await tester.tap(key('customer-Ýusup Ataýew'));
      await settle(tester, ms: 400);
      expect(find.text('Ýusup Ataýew'), findsWidgets);
      await checkout(tester);
      expect(key('checkout-customer'), findsOneWidget);
      await confirm(tester);
      expect(t.rig.server.ledger.sales.single['customer_name'], 'Ýusup Ataýew');
    });

    testWidgets('a new customer can be created on the spot', (tester) async {
      final t = deskRig();
      await openSales(tester, t.rig);
      await addToCart(tester);
      await tapKey(tester, 'cart-customer');
      await settle(tester, ms: 600);
      await tapKey(tester, 'customer-new');
      await tester.enterText(key('customer-name'), 'Иван Петров');
      await tapKey(tester, 'customer-save');
      await settle(tester, ms: 600);
      expect(t.rig.server.ledger.customers.single['name'], 'Иван Петров');
      expect(find.text('Иван Петров'), findsWidgets);
    });
  });

  group('the receipt', () {
    Future<void> sellOne(WidgetTester tester, RealRig rig) async {
      await openSales(tester, rig);
      await addToCart(tester);
      await checkout(tester);
      await confirm(tester);
    }

    testWidgets('print and share the receipt through the device', (
      tester,
    ) async {
      final t = deskRig();
      await sellOne(tester, t.rig);
      await tapKey(tester, 'doc-receipt-print');
      await settle(tester, ms: 400);
      await tapKey(tester, 'doc-receipt-share');
      await settle(tester, ms: 400);
      final docs = t.rig.documents;
      expect(docs.printed.single.name, 'receipt-S-000001');
      expect(
        String.fromCharCodes(docs.printed.single.bytes),
        startsWith('%PDF'),
      );
      expect(docs.shared.single.name, 'receipt-S-000001');
      // the language is the business's setting: the app does not choose one
      expect(t.rig.server.ledger.documentRequests.map((r) => r['lang']), [
        '',
        '',
      ]);
    });

    testWidgets('there is only a receipt: no invoice, no language to pick', (
      tester,
    ) async {
      final t = deskRig();
      await sellOne(tester, t.rig);
      expect(key('doc-receipt-print'), findsOneWidget);
      expect(key('doc-invoice-print'), findsNothing);
      expect(key('doc-lang'), findsNothing);
      expect(find.textContaining('Накладная'), findsNothing);
    });

    testWidgets('a receipt that cannot be fetched says so', (tester) async {
      final t = deskRig();
      await sellOne(tester, t.rig);
      t.rig.server.reachable = false;
      await tapKey(tester, 'doc-receipt-print');
      await settle(tester, ms: 400);
      expect(
        find.text('Не удалось получить документ. Попробуйте ещё раз.'),
        findsOneWidget,
      );
      expect(t.rig.documents.printed, isEmpty);
    });

    testWidgets('after a sale a new one starts with an empty cart', (
      tester,
    ) async {
      final t = deskRig();
      await sellOne(tester, t.rig);
      await tapKey(tester, 'sale-new');
      expect(key('sale-done'), findsNothing);
      expect(key('cart-empty'), findsOneWidget);
    });
  });

  group('lost answers and restarts', () {
    Future<void> prepare(WidgetTester tester, RealRig rig) async {
      await openSales(tester, rig);
      await addToCart(tester);
      await setQuantity(tester, '3');
      await checkout(tester);
    }

    testWidgets(
      'answer lost: the cart is not sold again, the key is kept, a retry changes nothing',
      (tester) async {
        final t = deskRig();
        await prepare(tester, t.rig);
        t.rig.server.dropResponseAfterCommit = 1;
        await confirm(tester);
        expect(find.textContaining('Ответ сервера не получен'), findsOneWidget);
        expect(key('pending-banner'), findsOneWidget);
        expect(
          key('cart-empty'),
          findsOneWidget,
        ); // the saved record owns that sale now
        expect(
          key('sale-done'),
          findsNothing,
        ); // success is never claimed without the server
        expect(t.rig.server.ledger.salesRecorded, 1);
        expect(t.rig.store.backing.single.action, 'sale_complete');
        final pendingKey = t.rig.store.backing.single.key;
        await tapKey(tester, 'pending-review');
        await settle(tester, ms: 400);
        expect(find.textContaining('Продажа · ${tmt(30000)}'), findsOneWidget);
        await tapKey(tester, 'pending-retry-$pendingKey');
        await settle(tester);
        expect(
          t.rig.server.ledger.salesRecorded,
          1,
        ); // answered from the server's record
        expect(
          t.rig.server.ledger.quantityOf(t.pad['id'] as String, store),
          7000,
        );
        expect(t.rig.store.backing, isEmpty);
      },
    );

    testWidgets('answer lost then the tablet restarts: exactly one sale', (
      tester,
    ) async {
      final t = deskRig();
      await prepare(tester, t.rig);
      t.rig.server.dropResponseAfterCommit = 1;
      await confirm(tester);
      expect(t.rig.store.backing, hasLength(1));
      await tester.pumpWidget(const SizedBox());
      await t.rig.launch(tester); // a fresh app on the same device storage
      await settle(tester);
      expect(
        key('pending-banner'),
        findsNothing,
      ); // the server confirmed the saved key
      expect(t.rig.store.backing, isEmpty);
      expect(t.rig.server.ledger.salesRecorded, 1);
      expect(t.rig.server.ledger.sales.single['number'], 1);
      // and it is in the history
      await tapKey(tester, 'nav-sales');
      await settle(tester);
      await tapKey(tester, 'sales-history');
      await settle(tester);
      expect(key('sale-S-000001'), findsOneWidget);
    });

    testWidgets(
      'a sale the server never saw is sent again with the same key after a restart',
      (tester) async {
        final t = deskRig();
        await prepare(tester, t.rig);
        t.rig.server.failBeforeCommit = 1; // a 5xx before anything was recorded
        await confirm(tester);
        expect(t.rig.server.ledger.salesRecorded, 0);
        final pendingKey = t.rig.store.backing.single.key;
        await tester.pumpWidget(const SizedBox());
        await t.rig.launch(tester);
        await settle(tester);
        expect(
          key('pending-banner'),
          findsOneWidget,
        ); // not confirmed: still listed
        await tapKey(tester, 'pending-review');
        await settle(tester, ms: 400);
        await tapKey(tester, 'pending-retry-$pendingKey');
        await settle(tester);
        expect(t.rig.server.ledger.salesRecorded, 1);
        expect(t.rig.server.records.keys, [pendingKey]); // one key, one sale
        expect(t.rig.store.backing, isEmpty);
      },
    );
  });

  group('history and roles', () {
    testWidgets(
      'history lists sales, searches by number, and shows the detail with cost for an owner',
      (tester) async {
        final t = deskRig();
        await openSales(tester, t.rig);
        for (var i = 0; i < 2; i++) {
          await addToCart(tester);
          await checkout(tester);
          await confirm(tester);
          await tapKey(tester, 'sale-new');
        }
        await tapKey(tester, 'sales-history');
        await settle(tester);
        expect(key('sale-S-000001'), findsOneWidget);
        expect(key('sale-S-000002'), findsOneWidget);
        await tester.enterText(key('history-search'), 'S-000002');
        await settle(tester, ms: 600);
        expect(key('sale-S-000001'), findsNothing);
        await tapKey(tester, 'sale-S-000002');
        await settle(tester);
        expect(key('sd-number'), findsOneWidget);
        expect(find.text('Итого: ${tmt(10000)}'), findsOneWidget);
        expect(find.text('Оплата: Наличные'), findsOneWidget);
        expect(find.text('Себестоимость: ${tmt(5000)}'), findsOneWidget);
        expect(find.text('Прибыль: ${tmt(5000)}'), findsOneWidget);
        expect(key('doc-receipt-print'), findsOneWidget);
      },
    );

    testWidgets('a sale below cost still goes through, and the owner sees it', (
      tester,
    ) async {
      final t = deskRig();
      await openSales(tester, t.rig);
      await addToCart(tester);
      await setPrice(tester, '30'); // the shelf cost is 50
      await checkout(tester);
      await confirm(tester);
      expect(t.rig.server.ledger.sales.single['total'], 3000);
      await tapKey(tester, 'sales-history');
      await settle(tester);
      await tapKey(tester, 'sale-S-000001');
      await settle(tester);
      expect(find.text('Себестоимость: ${tmt(5000)}'), findsOneWidget);
      expect(
        find.text('Прибыль: ${tmt(-2000)}'),
        findsOneWidget,
      ); // a loss of 20
    });

    testWidgets('a salesperson sells and sees no cost', (tester) async {
      final t = deskRig();
      t.rig.server.role = 'sales';
      t.rig.server.permissions = [
        'catalog.view',
        'stock.view',
        'location.view',
        'sales.view',
        'sales.create',
        'customer.view',
        'customer.manage',
      ];
      await openSales(tester, t.rig);
      await addToCart(tester);
      await setPrice(tester, '70'); // any seller may set the price
      await checkout(tester);
      await confirm(tester);
      expect(t.rig.server.ledger.sales.single['total'], 7000);
      await tapKey(tester, 'sales-history');
      await settle(tester);
      await tapKey(tester, 'sale-S-000001');
      await settle(tester);
      expect(key('sd-total'), findsOneWidget);
      expect(key('sd-cost'), findsNothing);
      expect(key('sd-profit'), findsNothing);
    });

    testWidgets(
      'a user who may only view sales sees the history but cannot sell',
      (tester) async {
        final t = deskRig();
        t.rig.server.permissions = [
          'catalog.view',
          'location.view',
          'sales.view',
        ];
        await openSales(tester, t.rig);
        expect(key('sales-no-permission'), findsOneWidget);
        expect(key('sales-search'), findsNothing);
        expect(key('sales-history'), findsOneWidget);
      },
    );

    testWidgets('the warehouse role has no sales page', (tester) async {
      final t = deskRig();
      t.rig.server.role = 'warehouse';
      t.rig.server.permissions = [
        'catalog.view',
        'stock.view',
        'location.view',
      ];
      await t.rig.launchSignedIn(tester);
      expect(key('nav-sales'), findsNothing);
    });
  });

  for (final size in [const Size(360, 800), const Size(800, 1100)]) {
    testWidgets('selling fits at $size with doubled text', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final t = deskRig();
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
      expect(tester.takeException(), isNull);
      await addToCart(tester);
      expect(tester.takeException(), isNull);
      await tapKey(tester, 'cart-checkout');
      await settle(tester);
      expect(tester.takeException(), isNull);
      await tapKey(tester, 'pay-card');
      await tapKey(tester, 'checkout-confirm');
      await settle(tester);
      expect(tester.takeException(), isNull);
      expect(key('sale-done'), findsOneWidget);
    });
  }
}
