import 'package:erp_system/theme/app_palette.dart';
import 'package:erp_system/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/real_rig.dart';

double contrast(Color a, Color b) {
  final x = a.computeLuminance() + 0.05;
  final y = b.computeLuminance() + 0.05;
  return x > y ? x / y : y / x;
}

/// What a translucent colour looks like over a backdrop.
Color over(Color top, Color backdrop) => Color.alphaBlend(top, backdrop);

void main() {
  group(
    'both schemes are readable (WCAG AA: 4.5:1 for text, 3:1 for outlines)',
    () {
      for (final p in [AppPalette.light, AppPalette.dark]) {
        final name = p.isDark ? 'dark' : 'light';
        // text on the page, on a card (glass over the page) and on an opaque surface
        final card = over(p.glass, p.canvas);
        final strong = over(p.glassStrong, p.canvas);

        test('$name: body and muted text on every surface', () {
          for (final (label, text) in [
            ('ink', p.ink),
            ('muted', p.muted),
            ('neutral', p.neutral),
          ]) {
            for (final (where, surface) in [
              ('canvas', p.canvas),
              ('canvas edge', p.canvasEdge),
              ('card', card),
              ('strong glass', strong),
              ('surface', p.surface),
              ('soft surface', p.surfaceSoft),
              ('muted surface', p.surfaceMuted),
            ]) {
              expect(
                contrast(text, surface),
                greaterThanOrEqualTo(4.5),
                reason: '$label on $where',
              );
            }
          }
        });

        test('$name: cobalt and the status colours on their own tints', () {
          expect(contrast(p.blue, p.surface), greaterThanOrEqualTo(4.5));
          expect(contrast(p.blue, card), greaterThanOrEqualTo(4.5));
          expect(contrast(p.blue, p.tint), greaterThanOrEqualTo(4.5));
          expect(contrast(p.success, p.successTint), greaterThanOrEqualTo(4.5));
          expect(contrast(p.warning, p.warningTint), greaterThanOrEqualTo(4.5));
          expect(contrast(p.danger, p.dangerTint), greaterThanOrEqualTo(4.5));
          expect(
            contrast(p.violetText, p.violetTint),
            greaterThanOrEqualTo(4.5),
          );
          // the selected pill: cobalt over a wash of cobalt on the card
          final wash = over(
            p.blue.withValues(alpha: p.isDark ? 0.22 : 0.1),
            card,
          );
          expect(contrast(p.blue, wash), greaterThanOrEqualTo(4.5));
        });

        test('$name: white text on the primary button', () {
          expect(contrast(Colors.white, p.blueFill), greaterThanOrEqualTo(4.5));
          expect(
            contrast(Colors.white, p.blueFillDeep),
            greaterThanOrEqualTo(4.5),
          );
        });

        test('$name: an input outline stands out from its surface', () {
          expect(contrast(p.control, p.surface), greaterThanOrEqualTo(3));
        });
      }
    },
  );

  group('the scheme is a setting', () {
    tearDown(() => AppColors.use(AppPalette.light));

    testWidgets('the app starts light, and Settings switch it to dark and back', (
      tester,
    ) async {
      final rig = RealRig();
      await rig.launchSignedIn(tester);
      expect(AppColors.isDark, isFalse);
      await tapKey(tester, 'nav-administration');
      await settle(tester);
      await tapKey(tester, 'theme-chip-dark');
      await settle(tester);
      expect(AppColors.isDark, isTrue);
      expect(rig.prefs.getString('theme.mode'), 'dark');
      // the screen was repainted in place: it is still the same page, with its state
      expect(key('theme-chip-dark'), findsOneWidget);
      expect(key('settings-tab-account'), findsOneWidget);

      await tapKey(tester, 'theme-chip-light');
      await settle(tester);
      expect(AppColors.isDark, isFalse);
      expect(rig.prefs.getString('theme.mode'), 'light');
    });

    testWidgets('a saved choice is in force from the first frame', (
      tester,
    ) async {
      final rig = RealRig();
      await rig.launch(tester, prefsValues: {'theme.mode': 'dark'});
      expect(AppColors.isDark, isTrue);
      expect(
        key('sign-in-submit'),
        findsOneWidget,
      ); // and the app is usable in it
    });

    testWidgets('"as the phone" follows the phone', (tester) async {
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      final rig = RealRig();
      await rig.launch(tester, prefsValues: {'theme.mode': 'system'});
      expect(AppColors.isDark, isTrue);
    });

    testWidgets('the default does not follow the phone', (tester) async {
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      final rig = RealRig();
      await rig.launch(tester);
      expect(AppColors.isDark, isFalse);
    });

    testWidgets(
      'every main page draws without overflow in the dark scheme at a phone width',
      (tester) async {
        final rig = RealRig();
        await rig.launch(
          tester,
          size: const Size(360, 800),
          prefsValues: {'theme.mode': 'dark'},
        );
        await rig.signIn(tester);
        for (final page in [
          'dashboard',
          'products',
          'sales',
          'inventory',
          'expenses',
          'warranties',
          'reports',
          'administration',
        ]) {
          await tapKey(tester, 'nav-$page');
          await settle(tester);
          expect(tester.takeException(), isNull, reason: page);
        }
      },
    );
  });
}
