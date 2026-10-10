import 'dart:convert';
import 'dart:typed_data';

import 'package:erp_system/core/files/file_services.dart';
import 'package:erp_system/core/money/decimal_math.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_files.dart';
import '../support/real_rig.dart';
import 'stock_ops_test.dart' show canPress, fieldNames;

/// A real (1 x 1 pixel) PNG: the fake server tells file types by their first bytes.
final png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

String day(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

Future<void> openExpenses(WidgetTester tester, RealRig rig) async {
  await rig.launchSignedIn(tester);
  await tapKey(tester, 'nav-expenses');
  await settle(tester);
}

Future<void> chooseCategory(WidgetTester tester, String name) async {
  await tapKey(tester, 'ef-category');
  await settle(tester, ms: 400);
  await tester.tap(find.text(name).last);
  await settle(tester, ms: 400);
}

/// Fills the form (category Аренда, 1 500,50, a description) without saving.
Future<void> fillExpense(WidgetTester tester) async {
  await tapKey(tester, 'expense-add');
  await settle(tester);
  await chooseCategory(tester, 'Аренда');
  await tester.enterText(key('ef-amount'), '1 500,50');
  await tester.enterText(key('ef-description'), 'Аренда за октябрь');
  await tester.pump();
}

void main() {
  group('expenses', () {
    testWidgets('an expense with a photo of the receipt is saved and shown', (
      tester,
    ) async {
      final rig = RealRig();
      await openExpenses(tester, rig);
      expect(key('expenses-empty'), findsOneWidget);
      await fillExpense(tester);
      rig.picking.nextFile = PickedFile(name: 'check.png', bytes: png);
      await tapKey(tester, 'ef-choose-file');
      await settle(tester);
      expect(find.text('Чек приложен: check.png'), findsOneWidget);
      await tapKey(tester, 'ef-save');
      await settle(tester);
      final office = rig.server.office;
      expect(office.expensesCreated, 1);
      final stored = office.expenses.single;
      expect(stored['amount'], 150050);
      expect(stored['attachment'], isNotNull);
      expect(find.text('Расход сохранён.'), findsOneWidget);
      expect(
        find.text('Всего за период: ${formatMoney(150050, 'TMT')}'),
        findsOneWidget,
      );
      await tapKey(tester, 'expense-${stored['id']}');
      await settle(tester);
      expect(key('ed-receipt-image'), findsOneWidget);
      await tapKey(tester, 'ed-share-receipt');
      await settle(tester);
      expect(rig.sharing.shared.single.name, 'check.png');
      expect(rig.sharing.shared.single.mimeType, 'image/png');
    });

    testWidgets('a photo can be taken with the camera when there is one', (
      tester,
    ) async {
      final rig = RealRig();
      await openExpenses(tester, rig);
      await tapKey(tester, 'expense-add');
      await settle(tester);
      rig.picking.nextPhoto = PickedFile(name: 'cam.png', bytes: png);
      await tapKey(tester, 'ef-take-photo');
      await settle(tester);
      expect(rig.picking.photoRequests, ['camera']);
      expect(find.text('Чек приложен: cam.png'), findsOneWidget);
      await tapKey(tester, 'ef-remove-receipt');
      await tester.pump();
      expect(find.text('Чек не приложен'), findsOneWidget);
    });

    testWidgets('without a camera only the file choice is offered', (
      tester,
    ) async {
      final rig = RealRig(picking: FakeFilePicking(hasCamera: false));
      await openExpenses(tester, rig);
      await tapKey(tester, 'expense-add');
      await settle(tester);
      expect(key('ef-take-photo'), findsNothing);
      expect(key('ef-choose-file'), findsOneWidget);
    });

    testWidgets('a file that is not a photo or a PDF is refused', (
      tester,
    ) async {
      final rig = RealRig();
      await openExpenses(tester, rig);
      await tapKey(tester, 'expense-add');
      await settle(tester);
      rig.picking.nextFile = PickedFile(
        name: 'virus.jpg',
        bytes: Uint8List.fromList(utf8.encode('just some text')),
      );
      await tapKey(tester, 'ef-choose-file');
      await settle(tester);
      expect(
        find.text('Подходят фото JPEG, PNG, WebP и файлы PDF.'),
        findsOneWidget,
      );
      expect(rig.server.office.files, isEmpty);
      expect(find.textContaining('Чек приложен'), findsNothing);
    });

    testWidgets('a file that is too large is refused', (tester) async {
      final rig = RealRig();
      rig.server.office.maxUpload = 10;
      await openExpenses(tester, rig);
      await tapKey(tester, 'expense-add');
      await settle(tester);
      rig.picking.nextFile = PickedFile(name: 'big.png', bytes: png);
      await tapKey(tester, 'ef-choose-file');
      await settle(tester);
      expect(
        find.text('Файл слишком большой (не больше 5 МБ).'),
        findsOneWidget,
      );
    });

    testWidgets('the amount and the category are required', (tester) async {
      final rig = RealRig();
      await openExpenses(tester, rig);
      await tapKey(tester, 'expense-add');
      await settle(tester);
      await tapKey(tester, 'ef-save');
      await settle(tester, ms: 200);
      expect(find.text('Обязательное поле.'), findsOneWidget);
      expect(find.text('Некорректное значение.'), findsOneWidget);
      expect(rig.server.office.expensesCreated, 0);
    });

    testWidgets('a new category can be added on the spot', (tester) async {
      final rig = RealRig();
      await openExpenses(tester, rig);
      await tapKey(tester, 'expense-add');
      await settle(tester);
      await chooseCategory(tester, 'Новая категория…');
      await tester.enterText(key('ef-new-category-name'), 'Ремонт');
      await tapKey(tester, 'ef-new-category-save');
      await settle(tester);
      expect(
        rig.server.office.categories.map((c) => c['name']),
        contains('Ремонт'),
      );
      expect(find.text('Ремонт'), findsWidgets); // chosen in the box
    });

    testWidgets('an expense can be corrected, and voided with a reason', (
      tester,
    ) async {
      final rig = RealRig();
      final office = rig.server.office;
      final seeded = office.seedExpense(
        category: 'xc-1',
        amountMinor: 100000,
        spentOn: day(DateTime.now()),
        description: 'Аренда',
      );
      await openExpenses(tester, rig);
      expect(
        find.text('Всего за период: ${formatMoney(100000, 'TMT')}'),
        findsOneWidget,
      );
      await tapKey(tester, 'expense-${seeded['id']}');
      await settle(tester);
      await tapKey(tester, 'ed-edit');
      await settle(tester);
      await tester.enterText(key('ef-amount'), '1200');
      await tapKey(tester, 'ef-save');
      await settle(tester);
      expect(office.expenses.single['amount'], 120000);
      expect(find.text(formatMoney(120000, 'TMT')), findsWidgets);
      await tapKey(tester, 'ed-void');
      await settle(tester, ms: 400);
      expect(canPress(tester, 'ed-edit'), isTrue);
      await tester.enterText(key('ed-void-reason'), 'Ошибка ввода');
      await tester.pump();
      await tester.tap(key('ed-void-confirm'));
      await settle(tester);
      expect(office.expenses.single['voided'], true);
      expect(key('ed-voided'), findsOneWidget);
      expect(key('ed-edit'), findsNothing); // a voided expense is final
      await goBack(tester);
      await settle(tester);
      expect(
        find.text('Всего за период: ${formatMoney(0, 'TMT')}'),
        findsOneWidget,
      );
    });

    testWidgets('the period and the category narrow the list and the totals', (
      tester,
    ) async {
      final rig = RealRig();
      final office = rig.server.office;
      final old = DateTime.now().subtract(const Duration(days: 75));
      office.seedExpense(
        category: 'xc-2',
        amountMinor: 50000,
        spentOn: day(old),
        description: 'Старая зарплата',
      );
      office.seedExpense(
        category: 'xc-1',
        amountMinor: 20000,
        spentOn: day(DateTime.now()),
        description: 'Аренда сейчас',
      );
      await openExpenses(tester, rig);
      expect(find.text('Аренда сейчас'), findsOneWidget);
      expect(find.text('Старая зарплата'), findsNothing);
      await tapKey(tester, 'expense-period-all');
      await settle(tester);
      expect(find.text('Старая зарплата'), findsOneWidget);
      expect(
        find.text('Всего за период: ${formatMoney(70000, 'TMT')}'),
        findsOneWidget,
      );
      await tapKey(tester, 'expense-category-filter');
      await settle(tester, ms: 400);
      await tester.tap(find.text('Зарплата').last);
      await settle(tester);
      expect(find.text('Аренда сейчас'), findsNothing);
      expect(
        find.text('Всего за период: ${formatMoney(50000, 'TMT')}'),
        findsOneWidget,
      );
    });

    testWidgets(
      'only owners and managers see expenses; others cannot change them',
      (tester) async {
        final seller = RealRig();
        seller.server.role = 'sales';
        seller.server.permissions = [
          'catalog.view',
          'sales.view',
          'sales.create',
        ];
        await seller.launchSignedIn(tester);
        expect(key('nav-expenses'), findsNothing);
        await tester.pumpWidget(const SizedBox());
        final viewer = RealRig();
        viewer.server.permissions = [
          'catalog.view',
          'expense.view',
          'attachment.view',
        ];
        final e = viewer.server.office.seedExpense(
          category: 'xc-1',
          amountMinor: 1000,
          spentOn: day(DateTime.now()),
        );
        await openExpenses(tester, viewer);
        expect(key('expense-add'), findsNothing);
        await tapKey(tester, 'expense-${e['id']}');
        await settle(tester);
        expect(key('ed-edit'), findsNothing);
        expect(key('ed-void'), findsNothing);
      },
    );

    testWidgets('every text field keeps its own name for a screen reader', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final rig = RealRig();
      await openExpenses(tester, rig);
      await tapKey(tester, 'expense-add');
      await settle(tester);
      expect(fieldNames(tester), ['Сумма, TMT', 'Описание']);
      handle.dispose();
    });

    for (final size in [const Size(360, 800), const Size(800, 1100)]) {
      testWidgets('expenses fit at $size with doubled text', (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final rig = RealRig();
        rig.server.office.seedExpense(
          category: 'xc-1',
          amountMinor: 123456,
          spentOn: day(DateTime.now()),
          description: 'Аренда помещения за октябрь, длинное описание',
        );
        await rig.launch(tester, size: size);
        await rig.signIn(tester);
        if (size.width < 600) {
          await tester.tap(find.byTooltip('Меню'));
          await settle(tester, ms: 400);
          await tester.scrollUntilVisible(
            key('nav-expenses'),
            200,
            scrollable: find.descendant(
              of: find.byType(Drawer),
              matching: find.byType(Scrollable),
            ),
          );
        }
        await tapKey(tester, 'nav-expenses');
        await settle(tester);
        expect(tester.takeException(), isNull, reason: 'list');
        await tapKey(tester, 'expense-add');
        await settle(tester);
        expect(tester.takeException(), isNull, reason: 'form');
      });
    }
  });
}
