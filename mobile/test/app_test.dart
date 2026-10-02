import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:erp_system/main.dart';
import 'package:erp_system/demo/demo_store.dart';

Future<SharedPreferences> preferences() async {
  SharedPreferences.setMockInitialValues({});
  return SharedPreferences.getInstance();
}

void main() {
  testWidgets(
    'language switch persists and preserves cart while all destinations render',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final prefs = await preferences();
      final store = DemoStore();
      addTearDown(store.dispose);
      await tester.pumpWidget(ErpApp(preferences: prefs, store: store));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('nav-sales')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('add-filter')));
      await tester.pumpAndSettle();
      expect(store.cartCount, 1);

      await tester.tap(find.byKey(const ValueKey('language-selector')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Türkmençe').last);
      await tester.pumpAndSettle();
      expect(prefs.getString('language'), 'tk');
      expect(store.cartCount, 1);
      expect(find.text('Satuwlar'), findsWidgets);
      expect(tester.takeException(), isNull);

      for (final page in [
        'dashboard',
        'products',
        'inventory',
        'purchasing',
        'sales',
        'expenses',
        'warranties',
        'reports',
        'administration',
      ]) {
        await tester.tap(find.byKey(ValueKey('nav-$page')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: page);
      }
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(ErpApp(preferences: prefs, store: store));
      await tester.pumpAndSettle();
      expect(find.text('Syn'), findsWidgets);
    },
  );

  testWidgets('search and receiving dialog update the correct demo product', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final store = DemoStore();
    addTearDown(store.dispose);
    await tester.pumpWidget(
      ErpApp(preferences: await preferences(), store: store),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('nav-inventory')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('product-search')),
      'FLT-001',
    );
    await tester.pumpAndSettle();
    expect(find.text('Тормозные колодки'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('receive-filter')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('stock-quantity')), '5');
    await tester.tap(find.byKey(const ValueKey('confirm-stock')));
    await tester.pumpAndSettle();
    expect(store.stock(store.product('filter')), 29);
    expect(tester.takeException(), isNull);
  });

  for (final size in [
    const Size(360, 800),
    const Size(800, 1100),
    const Size(1400, 1000),
  ]) {
    testWidgets('dashboard adapts at $size with enlarged text', (tester) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final prefs = await preferences();
      await tester.pumpWidget(ErpApp(preferences: prefs));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView).last, const Offset(0, -450));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
