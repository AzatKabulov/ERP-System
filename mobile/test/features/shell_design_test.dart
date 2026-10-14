import 'package:erp_system/widgets/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/real_rig.dart';

void main() {
  group('navigation follows the width', () {
    testWidgets(
      'a phone has a bottom bar of four modules and a menu for the rest',
      (tester) async {
        final rig = RealRig();
        await rig.launch(tester, size: const Size(360, 800));
        await rig.signIn(tester);
        expect(key('phone-navigation'), findsOneWidget);
        expect(key('nav-administration'), findsNothing);

        // The bar leads somewhere: the sales tab opens the sales page.
        await tester.tap(key('tab-sales'));
        await settle(tester);
        expect(key('phone-navigation'), findsOneWidget);
        expect(key('sales-search'), findsOneWidget);

        // The menu button reaches every other module, and sign-out.
        await tester.tap(find.byTooltip('Меню'));
        await settle(tester, ms: 400);
        expect(key('nav-administration'), findsOneWidget);
        expect(key('sidebar-sign-out'), findsOneWidget);
      },
    );

    testWidgets('a tablet has the side navigation and no bottom bar', (
      tester,
    ) async {
      final rig = RealRig();
      await rig.launch(tester, size: const Size(800, 1100));
      await rig.signIn(tester);
      expect(key('phone-navigation'), findsNothing);
      expect(key('nav-administration'), findsOneWidget);
      expect(key('sidebar-sign-out'), findsOneWidget);
    });

    testWidgets(
      'a wide screen has the side navigation with the signed-in person',
      (tester) async {
        final rig = RealRig();
        await rig.launchSignedIn(tester);
        expect(key('phone-navigation'), findsNothing);
        expect(key('sidebar-sign-out'), findsOneWidget);
        expect(key('role-control'), findsOneWidget);
      },
    );

    testWidgets('the bottom bar steps aside while the keyboard is open', (
      tester,
    ) async {
      final rig = RealRig();
      await rig.launch(tester, size: const Size(360, 800));
      await rig.signIn(tester);
      expect(key('phone-navigation'), findsOneWidget);
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetViewInsets);
      await settle(tester);
      expect(key('phone-navigation'), findsNothing);
    });
  });

  group('language switch', () {
    testWidgets('RU | TM changes the page language and keeps the page', (
      tester,
    ) async {
      final rig = RealRig();
      await rig.launchSignedIn(tester);
      expect(key('language-selector'), findsOneWidget);
      await tester.tap(key('language-tk'));
      await settle(tester, ms: 400);
      expect(find.text('Syn'), findsWidgets); // the overview, in Turkmen
      await tester.tap(key('language-ru'));
      await settle(tester, ms: 400);
      expect(find.text('Обзор'), findsWidgets);
    });
  });

  group('dashboard', () {
    testWidgets(
      'today\'s sales are the one ink spotlight, the rest are plain cards',
      (tester) async {
        final rig = RealRig();
        await rig.launchSignedIn(tester);
        expect(
          find.descendant(
            of: key('dash-sales-today'),
            matching: find.byType(SpotlightCard),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: key('dash-sales-month'),
            matching: find.byType(SpotlightCard),
          ),
          findsNothing,
        );
      },
    );
  });
}
