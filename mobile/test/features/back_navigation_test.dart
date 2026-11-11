import 'package:erp_system/widgets/app_navigation.dart';
import 'package:erp_system/widgets/app_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../support/real_rig.dart';
import 'catalog_test.dart' show seedProduct;

void main() {
  testWidgets('browser back preserves a dirty form and its confirmation', (
    tester,
  ) async {
    final navigation = AppNavigation()
      ..home = const Scaffold(body: Text('root'));
    await tester.pumpWidget(
      MaterialApp.router(
        routerDelegate: navigation,
        routeInformationParser: const AppRouteParser(),
      ),
    );
    await tester.pumpAndSettle();
    navigation.navigatorKey.currentState!.push<void>(
      appRoute<void>(
        builder: (context) => PopScope<void>(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) {
              showDialog<void>(
                context: context,
                builder: (_) => const AlertDialog(title: Text('Keep changes?')),
              );
            }
          },
          child: const Scaffold(body: Text('dirty form')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await navigation.setNewRoutePath('/');
    await tester.pumpAndSettle();
    expect(find.text('Keep changes?'), findsOneWidget);
    expect(navigation.navigatorKey.currentState!.canPop(), isTrue);
    navigation.navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.text('dirty form'), findsOneWidget);
    navigation.reset();
    await tester.pumpAndSettle();
    expect(find.text('root'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    navigation.dispose();
  });

  testWidgets('iPhone edge swipe closes product without reloading the app', (
    tester,
  ) async {
    final rig = RealRig();
    seedProduct(rig.server, sku: 'SWIPE', name: 'Ýag süzgüji Ё');
    await rig.launch(tester, size: const Size(390, 844), reduceMotion: false);
    await rig.signIn(tester);
    await tapKey(tester, 'nav-products');
    await settle(tester);
    await tapKey(tester, 'product-SWIPE');
    await settle(tester);
    expect(key('pd-name'), findsOneWidget);
    final refreshes = rig.server.refreshCalls;
    await tester.timedDragFrom(
      const Offset(2, 400),
      const Offset(330, 0),
      const Duration(milliseconds: 300),
    );
    await settle(tester);
    expect(key('pd-name'), findsNothing);
    expect(key('catalog-scroll'), findsOneWidget);
    expect(rig.server.refreshCalls, refreshes);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('100 push/back cycles preserve root and return default results', (
    tester,
  ) async {
    final navigation = AppNavigation()
      ..home = const Scaffold(body: Text('root'));
    await tester.pumpWidget(
      MaterialApp.router(
        routerDelegate: navigation,
        routeInformationParser: const AppRouteParser(),
      ),
    );
    await tester.pumpAndSettle();
    for (var i = 0; i < 100; i++) {
      final result = navigation.navigatorKey.currentState!.push<bool>(
        appRoute<bool>(
          builder: (_) => const AppRouteResult<bool>(
            result: true,
            child: Scaffold(body: Text('detail')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(navigation.currentConfiguration, startsWith('/s'));
      await navigation.setNewRoutePath('/');
      await tester.pumpAndSettle();
      expect(await result, isTrue);
      expect(navigation.currentConfiguration, '/');
    }
    expect(find.text('root'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    navigation.dispose();
  });
}
