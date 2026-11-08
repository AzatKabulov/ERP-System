import 'dart:async';

import 'package:erp_system/features/shared/loading_skeletons.dart';
import 'package:erp_system/widgets/skeleton.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/real_rig.dart';
import 'platform_test.dart' show makeOperator;
import 'expenses_test.dart' show png;

const business = '/api/v1/businesses/b-1';

/// Gate real repository HTTP calls, not widget state or elapsed-time placeholders.
Future<void> pendingRead(
  WidgetTester tester,
  RealRig rig,
  String path,
  Future<void> Function() navigate,
) async {
  final gate = Completer<void>();
  rig.server.readWaits[path] = gate.future;
  final before = rig.server.readPaths.where((p) => p == path).length;
  await navigate();
  await settle(tester, ms: 250);
  expect(
    rig.server.readPaths.where((p) => p == path).length,
    greaterThan(before),
    reason: path,
  );
  expect(find.byType(SkeletonRegion), findsWidgets, reason: path);
  final searchBefore = path == '$business/products/'
      ? tester.getRect(key('catalog-search'))
      : null;
  await settle(tester, ms: 1000);
  expect(
    find.byType(SkeletonRegion),
    findsWidgets,
    reason: 'stay until $path completes',
  );
  expect(tester.takeException(), isNull, reason: path);
  rig.server.readWaits.remove(path);
  gate.complete();
  await settle(tester);
  expect(find.byType(SkeletonRegion), findsNothing, reason: 'settled $path');
  if (searchBefore != null) {
    expect(
      tester.getRect(key('catalog-search')),
      searchBefore,
      reason: 'delayed result count must not move the catalog toolbar',
    );
  }
  expect(tester.takeException(), isNull, reason: path);
}

void main() {
  for (final size in [
    const Size(390, 844),
    const Size(800, 1100),
    const Size(1280, 900),
    const Size(1920, 1080),
  ]) {
    for (final dark in [false, true]) {
      testWidgets('store route reads and shell at $size, dark=$dark', (
        tester,
      ) async {
        final rig = RealRig();
        await rig.launch(
          tester,
          size: size,
          prefsValues: {'theme.mode': dark ? 'dark' : 'light'},
        );
        await rig.signIn(tester);
        for (final (page, path) in [
          ('products', '$business/products/'),
          ('inventory', '$business/stock/'),
          ('expenses', '$business/expenses/'),
          ('warranties', '$business/warranty-register/'),
          ('reports', '$business/reports/summary/'),
          ('dashboard', '$business/dashboard/'),
        ]) {
          await pendingRead(
            tester,
            rig,
            path,
            () => tapKey(tester, 'nav-$page'),
          );
          expect(
            key(size.width < 768 ? 'tab-products' : 'nav-products'),
            findsOneWidget,
          );
        }
        await tapKey(tester, 'nav-reports');
        await settle(tester);
        for (final tab in [
          'sales',
          'stock',
          'returns',
          'expenses',
          'activity',
        ]) {
          await pendingRead(
            tester,
            rig,
            tab == 'activity' ? '$business/audit/' : '$business/reports/$tab/',
            () => tapKey(tester, 'reports-tab-$tab'),
          );
        }
        await tapKey(tester, 'nav-inventory');
        await settle(tester);
        for (final tab in ['movements', 'transfers', 'counts']) {
          await pendingRead(
            tester,
            rig,
            '$business/${tab == 'movements' ? 'stock/movements' : tab}/',
            () => tapKey(tester, 'stock-tab-$tab'),
          );
        }
        await tapKey(tester, 'nav-warranties');
        await settle(tester);
        await tapKey(tester, 'warranty-tab-claims');
        await settle(tester);
        expect(
          find.byType(SkeletonRegion),
          findsNothing,
          reason: 'cached claims do not flash',
        );
        await pendingRead(
          tester,
          rig,
          '$business/warranty-claims/',
          () => tapKey(tester, 'warranty-filter-closed'),
        );
        await tapKey(tester, 'nav-administration');
        await settle(tester);
        await pendingRead(
          tester,
          rig,
          '$business/',
          () => tapKey(tester, 'settings-tab-shop'),
        );
        await pendingRead(
          tester,
          rig,
          '$business/staff/',
          () => tapKey(tester, 'settings-tab-team'),
        );
      });
    }
  }

  for (final size in [
    const Size(390, 844),
    const Size(800, 1100),
    const Size(1280, 900),
    const Size(1920, 1080),
  ]) {
    testWidgets(
      'platform route reads, package choices and preserved drafts at $size',
      (tester) async {
        final rig = RealRig();
        makeOperator(rig.server);
        await rig.launch(tester, size: size);
        await rig.signIn(tester);
        await tester.enterText(key('sign-in-code'), '123456');
        await tapKey(tester, 'sign-in-submit');
        await settle(tester);
        for (final (page, path) in [
          ('platformClients', '/api/v1/platform/clients/'),
          ('platformSupport', '/api/v1/platform/support/'),
          ('platformNotices', '/api/v1/platform/announcements/'),
          ('platformOverview', '/api/v1/platform/overview/'),
        ]) {
          await pendingRead(
            tester,
            rig,
            path,
            () => tapKey(tester, 'nav-$page'),
          );
        }
        await tapKey(tester, 'nav-platformClients');
        await settle(tester);
        final gate = Completer<void>();
        rig.server.readWaits['/api/v1/platform/plans/'] = gate.future;
        await tapKey(tester, 'pf-new-client');
        await settle(tester);
        expect(find.byType(SkeletonForm), findsOneWidget);
        await tester.enterText(key('pf-new-store_name'), 'Keep this shop name');
        gate.complete();
        rig.server.readWaits.clear();
        await settle(tester);
        expect(find.byType(SkeletonForm), findsNothing);
        expect(find.text('Keep this shop name'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'dashboard metrics stay available while independent charts read or fail',
    (tester) async {
      final rig = RealRig();
      final gate = Completer<void>();
      rig.server.readWaits['$business/reports/sales/'] = gate.future;
      await rig.launchSignedIn(tester);
      expect(key('dash-sales-today'), findsOneWidget);
      expect(find.byType(ChartsLoadingSkeleton), findsOneWidget);
      rig.server.reachable = false;
      gate.complete();
      rig.server.readWaits.clear();
      await settle(tester);
      expect(key('dash-sales-today'), findsOneWidget);
      expect(find.byType(ChartsLoadingSkeleton), findsNothing);
      expect(key('retry-load'), findsOneWidget);
      rig.server.reachable = true;
      await tapKey(tester, 'retry-load');
      await settle(tester);
      expect(key('retry-load'), findsNothing);
      expect(key('dash-sales-today'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  for (final product in [true, false]) {
    testWidgets(
      '${product ? 'product' : 'expense'} reference read terminates on failure and retries',
      (tester) async {
        final rig = RealRig();
        await rig.launchSignedIn(tester);
        await tapKey(tester, product ? 'nav-products' : 'nav-expenses');
        await settle(tester);
        final path = '$business/${product ? 'units' : 'expense-categories'}/';
        final gate = Completer<void>();
        rig.server.readWaits[path] = gate.future;
        await tapKey(tester, product ? 'catalog-add' : 'expense-add');
        await settle(tester);
        expect(find.byType(SkeletonRegion), findsWidgets);
        rig.server.reachable = false;
        gate.complete();
        rig.server.readWaits.clear();
        await settle(tester);
        expect(find.byType(SkeletonRegion), findsNothing);
        expect(key('retry-load'), findsOneWidget);
        rig.server.reachable = true;
        await tapKey(tester, 'retry-load');
        await settle(tester);
        expect(key(product ? 'pf-name' : 'ef-amount'), findsOneWidget);
        expect(key('retry-load'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('receipt read fails and retries independently of expense facts', (
    tester,
  ) async {
    final rig = RealRig();
    final office = rig.server.office;
    office.files['receipt-1'] = (
      name: 'check.png',
      type: 'image/png',
      bytes: png,
    );
    final expense = office.seedExpense(
      category: 'xc-1',
      amountMinor: 12000,
      spentOn: DateTime.now().toIso8601String().substring(0, 10),
      description: 'Receipt retry',
    );
    expense['attachment'] = 'receipt-1';
    await rig.launchSignedIn(tester);
    await tapKey(tester, 'nav-expenses');
    await settle(tester);
    final gate = Completer<void>();
    rig.server.readWaits['$business/attachments/receipt-1/'] = gate.future;
    await tapKey(tester, 'expense-${expense['id']}');
    await settle(tester);
    expect(key('ed-amount'), findsOneWidget);
    expect(find.byType(SkeletonImage), findsOneWidget);
    rig.server.reachable = false;
    gate.complete();
    rig.server.readWaits.clear();
    await settle(tester);
    expect(key('ed-amount'), findsOneWidget);
    expect(find.byType(SkeletonRegion), findsNothing);
    expect(key('ed-receipt-retry'), findsOneWidget);
    rig.server.reachable = true;
    await tapKey(tester, 'ed-receipt-retry');
    await settle(tester);
    expect(key('ed-receipt-image'), findsOneWidget);
    expect(key('ed-receipt-retry'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
