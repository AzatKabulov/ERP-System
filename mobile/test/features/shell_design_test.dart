import 'package:erp_system/widgets/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/real_rig.dart';

void main() {
  group('navigation follows the width', () {
    testWidgets(
      'a phone has a bottom bar of four modules and a labelled More tab for the rest',
      (tester) async {
        final rig = RealRig();
        await rig.launch(tester, size: const Size(360, 800));
        await rig.signIn(tester);
        expect(key('phone-navigation'), findsOneWidget);
        expect(key('nav-administration'), findsNothing);
        // no hidden hamburger: the way to the rest is a visible tab with a name
        expect(find.byTooltip('Меню'), findsNothing);
        expect(key('tab-more'), findsOneWidget);

        // The bar leads somewhere: the sales tab opens the sales page.
        await tester.tap(key('tab-sales'));
        await settle(tester);
        expect(key('phone-navigation'), findsOneWidget);
        expect(key('sales-search'), findsOneWidget);

        // The More tab lists every other module, the help and sign-out.
        await tester.tap(key('tab-more'));
        await settle(tester, ms: 400);
        expect(key('more-sheet'), findsOneWidget);
        expect(key('more-administration'), findsOneWidget);
        expect(key('more-expenses'), findsOneWidget);
        expect(key('more-help'), findsOneWidget);
        expect(key('more-sign-out'), findsOneWidget);

        // A page from the list opens, and More is then the selected tab.
        await tester.tap(key('more-administration'));
        await settle(tester);
        expect(key('more-sheet'), findsNothing);
        expect(key('settings-tab-account'), findsOneWidget);
      },
    );

    testWidgets(
      'the side menu and the bottom bar list pages in the same order',
      (tester) async {
        final rig = RealRig();
        await rig.launch(tester, size: const Size(800, 1100));
        await rig.signIn(tester);
        double top(String name) => tester.getTopLeft(key(name)).dy;
        expect(top('nav-dashboard'), lessThan(top('nav-products')));
        expect(top('nav-products'), lessThan(top('nav-sales')));
        expect(top('nav-sales'), lessThan(top('nav-inventory')));
        expect(top('nav-inventory'), lessThan(top('nav-expenses')));
      },
    );

    testWidgets(
      'a phone shows the shop once and no language switch in the bar',
      (tester) async {
        final rig = RealRig();
        await rig.launch(tester, size: const Size(360, 800));
        await rig.signIn(tester);
        expect(key('language-selector'), findsNothing);
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
