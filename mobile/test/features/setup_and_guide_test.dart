import 'package:erp_system/features/guide/coach_guide.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/real_rig.dart';

void main() {
  tearDown(() => Guides.enabled = false);

  group('the owner of a new shop is asked about it', () {
    Future<RealRig> pendingShop(WidgetTester tester) async {
      final rig = RealRig();
      ((rig.server.me['memberships'] as List).first['business']
              as Map)['setup_status'] =
          'pending';
      await rig.launchSignedIn(tester);
      return rig;
    }

    testWidgets('step by step, then the shop opens', (tester) async {
      final rig = await pendingShop(tester);
      expect(find.text('Давайте настроим ваш магазин'), findsOneWidget);
      expect(key('nav-products'), findsNothing);

      await tapKey(tester, 'setup-next');
      await settle(tester);
      expect(find.byKey(const ValueKey('setup-name')), findsOneWidget);
      await tapKey(tester, 'setup-next');
      await settle(tester);

      await tapKey(tester, 'setup-add-person');
      await settle(tester);
      await tester.enterText(key('setup-person-name-0'), 'Aman');
      await tester.enterText(key('setup-person-pay-0'), '2500');
      await tapKey(tester, 'setup-next');
      await settle(tester);

      await tester.enterText(key('setup-rent'), '8000');
      await tapKey(tester, 'setup-next');
      await settle(tester);

      expect(find.text('Готово!'), findsOneWidget);
      expect(rig.server.teamData.single['name'], 'Aman');
      expect(rig.server.teamData.single['monthly_pay'], '2500');
      expect(rig.server.businessData['monthly_rent'], '8000');
      expect(rig.server.businessData['setup_status'], 'done');

      await tapKey(tester, 'setup-next');
      await settle(tester);
      expect(key('nav-products'), findsOneWidget);
      expect(find.text('Давайте настроим ваш магазин'), findsNothing);
    });

    testWidgets(
      'skipping goes straight to the shop and is remembered on the server',
      (tester) async {
        final rig = await pendingShop(tester);
        await tapKey(tester, 'setup-skip');
        await settle(tester);
        expect(key('nav-products'), findsOneWidget);
        expect(rig.server.businessData['setup_status'], 'skipped');
        expect(rig.server.teamData, isEmpty);
      },
    );

    testWidgets('a shop that is already set up is not asked', (tester) async {
      final rig = RealRig();
      await rig.launchSignedIn(tester);
      expect(key('setup-next'), findsNothing);
      expect(key('nav-products'), findsOneWidget);
    });

    testWidgets('the questions can be opened again from Settings', (
      tester,
    ) async {
      final rig = RealRig();
      await rig.launchSignedIn(tester);
      await tapKey(tester, 'nav-administration');
      await settle(tester);
      await tapKey(tester, 'settings-tab-shop');
      await settle(tester);
      await tapKey(tester, 'settings-setup');
      await settle(tester);
      expect(key('setup-name'), findsOneWidget);
      await tapKey(tester, 'setup-skip'); // "Close" when opened from Settings
      await settle(tester);
      expect(key('settings-setup'), findsOneWidget);
    });
  });

  group('the first-time tips', () {
    testWidgets(
      'appear once with arrows, can be walked through, and do not return',
      (tester) async {
        final rig = RealRig();
        await rig.launch(tester);
        Guides.enabled = true;
        await rig.signIn(tester);
        await settle(tester, ms: 2500);
        expect(key('guide-card'), findsOneWidget);
        expect(find.textContaining('Касса: здесь вы продаёте'), findsOneWidget);

        await tester.tap(key('guide-next'));
        await settle(tester);
        expect(find.textContaining('Товары: сначала добавьте'), findsOneWidget);
        await tester.tap(key('guide-skip'));
        await settle(tester);
        expect(key('guide-card'), findsNothing);
        expect(Guides.seen(rig.prefs, 'dashboard'), isTrue);
      },
    );

    testWidgets('on a phone every tip sits next to the control it is about', (
      tester,
    ) async {
      final rig = RealRig();
      await rig.launch(tester, size: const Size(393, 800));
      Guides.enabled = true;
      await rig.signIn(tester);
      await settle(tester, ms: 3000);
      for (final tab in ['tab-sales', 'tab-products', 'tab-inventory']) {
        final card = tester.getRect(key('guide-card'));
        final target = tester.getRect(key(tab));
        // the tab bar is at the bottom: the tip is above it, over the right tab
        expect(card.bottom, lessThanOrEqualTo(target.top + 1), reason: tab);
        expect(card.left, lessThanOrEqualTo(target.right), reason: tab);
        expect(card.right, greaterThanOrEqualTo(target.left), reason: tab);
        await tester.tap(key('guide-next'));
        await settle(tester, ms: 600);
      }
      // the last tip points at the help button at the top: the tip is below it
      final help = tester.getRect(key('help-button'));
      expect(
        tester.getRect(key('guide-card')).top,
        greaterThanOrEqualTo(help.bottom - 1),
      );
    });

    testWidgets('can be switched on again from Settings', (tester) async {
      final rig = RealRig();
      await rig.launch(tester, prefsValues: {'guide.dashboard.done': true});
      await rig.signIn(tester);
      await settle(tester, ms: 2000);
      expect(key('guide-card'), findsNothing);
      await tapKey(tester, 'nav-administration');
      await settle(tester);
      await tapKey(tester, 'settings-guide-replay');
      await settle(tester);
      expect(Guides.seen(rig.prefs, 'dashboard'), isFalse);
    });
  });
}
