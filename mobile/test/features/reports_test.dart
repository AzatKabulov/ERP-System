import 'package:erp_system/core/money/decimal_math.dart';
import 'package:erp_system/features/reports/reports_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/real_rig.dart';
import 'stock_ops_test.dart' show fieldNames;

String tm(int minor) => formatMoney(minor, 'TMT');

Future<void> openReports(
  WidgetTester tester,
  RealRig rig, {
  String tab = 'summary',
}) async {
  await rig.launchSignedIn(tester);
  await tapKey(tester, 'nav-reports');
  await settle(tester);
  if (tab != 'summary') {
    await tapKey(tester, 'reports-tab-$tab');
    await settle(tester);
  }
}

/// The reports requests made so far, as "path" (query).
Iterable<({String path, Map<String, String> query})> asked(
  RealRig rig,
  String path,
) => rig.server.reports.requests.where((r) => r.path == path);

void main() {
  group('dashboard', () {
    testWidgets(
      'the owner sees today, the month, costs, stock and recent activity',
      (tester) async {
        final rig = RealRig();
        await rig.launchSignedIn(tester);
        expect(key('welcome'), findsOneWidget);
        expect(find.text(tm(30000)), findsOneWidget); // today
        expect(find.text('Продажи сегодня (2)'), findsOneWidget);
        expect(find.text(tm(54000)), findsOneWidget); // the month
        expect(find.text(tm(17000)), findsOneWidget); // gross profit
        expect(find.text(tm(15000)), findsOneWidget); // expenses
        expect(find.text(tm(133000)), findsOneWidget); // inventory value
        expect(key('dash-low-stock'), findsOneWidget);
        expect(key('dash-reorder'), findsOneWidget);
        expect(key('dash-open-orders'), findsOneWidget);
        expect(key('dash-open-claims'), findsOneWidget);
        await tester.ensureVisible(key('dash-activity-a-100'));
        expect(find.text('Оформлена продажа'), findsWidgets);
        expect(key('dash-open-reports'), findsOneWidget);
      },
    );

    testWidgets(
      'a seller sees sales only: no costs, no stock value, no reports',
      (tester) async {
        final rig = RealRig();
        rig.server.role = 'sales';
        rig.server.permissions = [
          'catalog.view',
          'sales.view',
          'sales.create',
          'dashboard.view',
        ];
        await rig.launchSignedIn(tester);
        expect(key('dash-sales-today'), findsOneWidget);
        expect(key('dash-sales-month'), findsOneWidget);
        for (final hidden in [
          'dash-profit-month',
          'dash-expenses-month',
          'dash-inventory',
          'dash-low-stock',
          'dash-open-orders',
          'dash-open-reports',
        ]) {
          expect(key(hidden), findsNothing, reason: hidden);
        }
        expect(key('nav-reports'), findsNothing);
      },
    );

    testWidgets('a keeper sees stock and orders, never sales or money', (
      tester,
    ) async {
      final rig = RealRig();
      rig.server.role = 'warehouse';
      rig.server.permissions = [
        'catalog.view',
        'stock.view',
        'purchasing.view',
        'dashboard.view',
      ];
      await rig.launchSignedIn(tester);
      expect(key('dash-low-stock'), findsOneWidget);
      expect(key('dash-open-orders'), findsOneWidget);
      expect(key('dash-sales-today'), findsNothing);
      expect(key('dash-inventory'), findsNothing);
      expect(find.textContaining('TMT'), findsNothing);
    });

    testWidgets('a role with nothing to show is told so', (tester) async {
      final rig = RealRig();
      rig.server.permissions = ['catalog.view', 'dashboard.view'];
      await rig.launchSignedIn(tester);
      expect(key('dash-nothing'), findsOneWidget);
    });

    testWidgets('without the dashboard right nothing is even asked for', (
      tester,
    ) async {
      final rig = RealRig();
      rig.server.permissions = ['catalog.view'];
      await rig.launchSignedIn(tester);
      expect(key('welcome'), findsOneWidget);
      expect(asked(rig, 'dashboard/'), isEmpty);
    });

    testWidgets('the button opens the reports page', (tester) async {
      final rig = RealRig();
      await rig.launchSignedIn(tester);
      await tapKey(tester, 'dash-open-reports');
      await settle(tester);
      expect(key('reports-tab-summary'), findsOneWidget);
    });
  });

  group('reports', () {
    testWidgets('the summary shows every measure separately, with the note', (
      tester,
    ) async {
      final rig = RealRig();
      await openReports(tester, rig);
      expect(find.text(tm(54000)), findsOneWidget); // revenue
      expect(find.text(tm(12000)), findsOneWidget); // refunds
      expect(find.text(tm(42000)), findsOneWidget); // net sales
      expect(find.text(tm(25000)), findsOneWidget); // cost of goods
      expect(find.text(tm(17000)), findsOneWidget); // gross profit
      expect(find.text(tm(15000)), findsOneWidget); // expenses
      expect(find.text(tm(2000)), findsOneWidget); // the result
      expect(find.text(tm(133000)), findsOneWidget); // inventory value
      expect(find.text('Продаж: 3 · Возвратов: 1'), findsOneWidget);
      expect(
        find.text(
          'Результат = валовая прибыль минус расходы. Это не бухгалтерская прибыль.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('figures the server leaves out are not shown', (tester) async {
      final rig = RealRig();
      rig.server.permissions = [
        for (final p in rig.server.permissions)
          if (p != 'sales.cost.view' && p != 'stock.cost.view') p,
      ];
      await openReports(tester, rig);
      expect(find.text(tm(54000)), findsOneWidget);
      for (final hidden in [
        'rep-cost',
        'rep-profit',
        'rep-result',
        'rep-inventory',
      ]) {
        expect(key(hidden), findsNothing, reason: hidden);
      }
      expect(key('rep-expenses'), findsOneWidget);
    });

    testWidgets('the period and the location go to the server', (tester) async {
      final rig = RealRig();
      await openReports(tester, rig);
      var last = asked(rig, 'reports/summary/').last.query;
      final now = DateTime.now();
      expect(last['date_from'], reportDay(DateTime(now.year, now.month, 1)));
      expect(last['date_to'], reportDay(now));
      expect(last.containsKey('location'), isFalse);

      await tapKey(tester, 'reports-period-week');
      await settle(tester);
      last = asked(rig, 'reports/summary/').last.query;
      expect(
        last['date_from'],
        reportDay(DateTime(now.year, now.month, now.day - 6)),
      );

      await tapKey(tester, 'reports-period-today');
      await settle(tester);
      last = asked(rig, 'reports/summary/').last.query;
      expect(last['date_from'], reportDay(now));
      expect(last['date_to'], reportDay(now));

      await tapKey(tester, 'reports-period-lastMonth');
      await settle(tester);
      last = asked(rig, 'reports/summary/').last.query;
      expect(
        last['date_from'],
        reportDay(DateTime(now.year, now.month - 1, 1)),
      );
      expect(last['date_to'], reportDay(DateTime(now.year, now.month, 0)));

      await tapKey(tester, 'reports-location');
      await settle(tester, ms: 400);
      await tester.tap(find.text('Ammar').last);
      await settle(tester);
      expect(asked(rig, 'reports/summary/').last.query['location'], 'l-2');
    });

    testWidgets('sales: totals, how they paid, every day, the best products', (
      tester,
    ) async {
      final rig = RealRig();
      await openReports(tester, rig, tab: 'sales');
      expect(find.text('Выручка: ${tm(54000)}'), findsOneWidget);
      expect(find.text('Возвраты денег: ${tm(12000)}'), findsOneWidget);
      expect(find.text('Чистые продажи: ${tm(42000)}'), findsOneWidget);
      expect(find.text('Валовая прибыль: ${tm(17000)}'), findsOneWidget);
      expect(find.text('Наличные: 2 · ${tm(30000)}'), findsOneWidget);
      expect(find.text('Карта: 1 · ${tm(24000)}'), findsOneWidget);
      expect(
        find.text(
          '2026-10-07: 2 · выручка ${tm(30000)} · возвраты ${tm(12000)}',
        ),
        findsOneWidget,
      );
      expect(find.text('Тормозные колодки · BP-100'), findsOneWidget);
    });

    testWidgets(
      'stock: below the minimum, the value by place, every kind of movement',
      (tester) async {
        final rig = RealRig();
        await openReports(tester, rig, tab: 'stock');
        expect(find.text('Тормозные колодки · BP-100'), findsOneWidget);
        expect(
          find.text('Esasy dükan: есть 1 шт, минимум 5 шт'),
          findsOneWidget,
        );
        expect(find.text('Стоимость склада: ${tm(133000)}'), findsOneWidget);
        expect(find.text('Ammar: ${tm(133000)}'), findsOneWidget);
        // the movement types have their own names (not "Движение")
        expect(find.text('Продажа: 3 · приход 0 · расход 5'), findsOneWidget);
        expect(
          find.text('Возврат от покупателя: 1 · приход 1 · расход 0'),
          findsOneWidget,
        );
      },
    );

    testWidgets('stock without cost rights shows no value at all', (
      tester,
    ) async {
      final rig = RealRig();
      rig.server.permissions = [
        for (final p in rig.server.permissions)
          if (p != 'stock.cost.view') p,
      ];
      await openReports(tester, rig, tab: 'stock');
      expect(key('rep-stock-value'), findsNothing);
      expect(find.text('Тормозные колодки · BP-100'), findsOneWidget);
    });

    testWidgets('purchasing, returns and expenses show their figures', (
      tester,
    ) async {
      final rig = RealRig();
      await openReports(tester, rig, tab: 'purchasing');
      expect(find.text('Заказов создано: 2'), findsOneWidget);
      expect(find.text('Сумма заказов: ${tm(183000)}'), findsOneWidget);
      expect(find.text('Принято на сумму: ${tm(50000)}'), findsOneWidget);
      expect(find.text('Принят полностью: 1'), findsOneWidget);
      expect(
        find.text('Ашхабад Запчасти: заказов 2, принято на ${tm(50000)}'),
        findsOneWidget,
      );
      expect(
        find.text('Возвраты поставщикам: 1, зачёт ${tm(5000)}'),
        findsOneWidget,
      );

      await tapKey(tester, 'reports-tab-returns');
      await settle(tester);
      expect(find.text('Возвращено покупателям: ${tm(12000)}'), findsOneWidget);
      expect(find.text('Годный к продаже: 1 · ${tm(12000)}'), findsOneWidget);
      expect(
        find.text('Не подошли по размеру: 1 · ${tm(12000)}'),
        findsOneWidget,
      );

      await tapKey(tester, 'reports-tab-expenses');
      await settle(tester);
      expect(find.text('Всего: ${tm(15000)}'), findsOneWidget);
      expect(find.text('Аренда: ${tm(15000)} (1)'), findsOneWidget);
    });

    testWidgets('a keeper-style role gets no cost columns on purchasing', (
      tester,
    ) async {
      final rig = RealRig();
      rig.server.permissions = [
        for (final p in rig.server.permissions)
          if (p != 'purchasing.cost.view') p,
      ];
      await openReports(tester, rig, tab: 'purchasing');
      expect(key('rep-ordered-total'), findsNothing);
      expect(key('rep-received-value'), findsNothing);
      expect(find.text('Возвраты поставщикам: 1'), findsOneWidget);
    });

    testWidgets('the expenses tab needs the expenses right', (tester) async {
      final rig = RealRig();
      rig.server.permissions = [
        for (final p in rig.server.permissions)
          if (p != 'expense.view' && p != 'expense.manage') p,
      ];
      await openReports(tester, rig);
      expect(key('reports-tab-expenses'), findsNothing);
      expect(key('rep-expenses'), findsNothing);
    });

    testWidgets('each report can be exported and shared as a file', (
      tester,
    ) async {
      final rig = RealRig();
      await openReports(tester, rig, tab: 'sales');
      await tapKey(tester, 'report-export');
      await settle(tester);
      final shared = rig.sharing.shared.single;
      final q = asked(rig, 'reports/sales/export/').single.query;
      expect(shared.name, 'sales-${q['date_from']}-${q['date_to']}.csv');
      expect(shared.mimeType, 'text/csv');
      expect(shared.bytes.take(3).toList(), [0xEF, 0xBB, 0xBF]);
      expect(find.text('Файл отчёта готов.'), findsOneWidget);
    });

    testWidgets('a failed load says so and can be retried', (tester) async {
      final rig = RealRig();
      rig.server.reports.failWith = 500;
      await openReports(tester, rig, tab: 'sales');
      expect(key('retry-load'), findsOneWidget);
      rig.server.reports.failWith = null;
      await tapKey(tester, 'retry-load');
      await settle(tester);
      expect(find.text('Выручка: ${tm(54000)}'), findsOneWidget);
    });

    testWidgets('a seller has no reports page', (tester) async {
      final rig = RealRig();
      rig.server.role = 'sales';
      rig.server.permissions = ['catalog.view', 'sales.view', 'sales.create'];
      await rig.launchSignedIn(tester);
      expect(key('nav-reports'), findsNothing);
    });
  });

  group('activity history', () {
    testWidgets('lists the newest first in the interface language, in pages', (
      tester,
    ) async {
      final rig = RealRig();
      await openReports(tester, rig, tab: 'activity');
      expect(key('activity-row-a-100'), findsOneWidget);
      expect(find.text('Оформлена продажа'), findsWidgets);
      expect(find.text('Возврат от покупателя'), findsWidgets);
      // an action this app has no name for is shown by its code, never hidden
      expect(find.text('something.new'), findsOneWidget);
      // a system action has no person
      expect(find.textContaining('Система ·'), findsOneWidget);
      expect(asked(rig, 'audit/').last.query['limit'], '30');
      await tapKey(tester, 'activity-more');
      await settle(tester);
      expect(asked(rig, 'audit/').last.query['offset'], '30');
      expect(key('activity-row-a-56'), findsOneWidget); // the 45th row
      expect(key('activity-more'), findsNothing); // everything is loaded
    });

    testWidgets('can be narrowed to one action and by a word', (tester) async {
      final rig = RealRig();
      await openReports(tester, rig, tab: 'activity');
      await tapKey(tester, 'activity-action');
      await settle(tester, ms: 400);
      await tester.tap(find.text('Оформлена продажа').last);
      await settle(tester);
      expect(asked(rig, 'audit/').last.query['action'], 'sale.completed');
      expect(key('activity-row-a-100'), findsOneWidget);
      expect(key('activity-row-a-99'), findsNothing);

      await tapKey(tester, 'activity-action');
      await settle(tester, ms: 400);
      await tester.tap(find.text('Все действия').last);
      await settle(tester);
      await tester.enterText(key('activity-search'), 'id-7');
      await tapKey(tester, 'activity-search-go');
      await settle(tester);
      expect(asked(rig, 'audit/').last.query['q'], 'id-7');
      expect(key('activity-row-a-93'), findsOneWidget);
      expect(key('activity-row-a-100'), findsNothing);

      await tester.enterText(key('activity-search'), 'nothing like this');
      await tapKey(tester, 'activity-search-go');
      await settle(tester);
      expect(key('activity-empty'), findsOneWidget);
    });

    testWidgets('follows the chosen period', (tester) async {
      final rig = RealRig();
      await openReports(tester, rig, tab: 'activity');
      final now = DateTime.now();
      expect(
        asked(rig, 'audit/').last.query['date_from'],
        reportDay(DateTime(now.year, now.month, 1)),
      );
      await tapKey(tester, 'reports-period-today');
      await settle(tester);
      expect(asked(rig, 'audit/').last.query['date_from'], reportDay(now));
    });

    testWidgets('is only offered with the audit right', (tester) async {
      final rig = RealRig();
      rig.server.permissions = [
        for (final p in rig.server.permissions)
          if (p != 'audit.view') p,
      ];
      await openReports(tester, rig);
      expect(key('reports-tab-activity'), findsNothing);
      expect(key('dash-activity-a-100'), findsNothing);
    });

    testWidgets('the search field has its own name for a screen reader', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final rig = RealRig();
      await openReports(tester, rig, tab: 'activity');
      expect(fieldNames(tester), ['Действие или объект']);
      handle.dispose();
    });
  });

  for (final size in [const Size(360, 800), const Size(800, 1100)]) {
    testWidgets('dashboard and every report fit at $size with doubled text', (
      tester,
    ) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final rig = RealRig();
      await rig.launch(tester, size: size);
      await rig.signIn(tester);
      expect(tester.takeException(), isNull, reason: 'dashboard');
      if (size.width < 600) {
        await tester.tap(find.byTooltip('Меню'));
        await settle(tester, ms: 400);
        await tester.scrollUntilVisible(
          key('nav-reports'),
          200,
          scrollable: find.descendant(
            of: find.byType(Drawer),
            matching: find.byType(Scrollable),
          ),
        );
      }
      await tapKey(tester, 'nav-reports');
      await settle(tester);
      for (final tab in [
        'summary',
        'sales',
        'stock',
        'purchasing',
        'returns',
        'expenses',
        'activity',
      ]) {
        await tapKey(tester, 'reports-tab-$tab');
        await settle(tester);
        expect(tester.takeException(), isNull, reason: tab);
      }
    });
  }
}
