import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../support/real_rig.dart';
import 'platform_test.dart' show makeOperator, signInAsOperator;
import 'intake_test.dart' show intakeRig, openIntake, scanByKeyboard;

void main() {
  testWidgets('new client asks before discarding entered details', (
    tester,
  ) async {
    final rig = RealRig();
    makeOperator(rig.server);
    await signInAsOperator(tester, rig);
    await tapKey(tester, 'nav-platformClients');
    await settle(tester);
    await tapKey(tester, 'pf-new-client');
    await settle(tester);
    await tester.enterText(key('pf-new-store_name'), 'My new shop');
    await tester.pump();
    await tester.tap(find.byType(BackButton));
    await settle(tester);
    // A real confirmation is present; cancelling must keep the entered shop name.
    expect(find.text('Отмена'), findsOneWidget);
    await tester.tap(find.text('Отмена'));
    await settle(tester);
    expect(
      tester.widget<TextField>(key('pf-new-store_name')).controller!.text,
      'My new shop',
    );
  });
  for (final width in [360.0, 768.0, 1280.0]) {
    testWidgets(
      'receiving photo and name stay on separate rows at width $width',
      (tester) async {
        final t = intakeRig();
        await openIntake(tester, t.rig);
        await scanByKeyboard(tester, 'NEW-FILTER', review: true);
        await tester.binding.setSurfaceSize(Size(width, 900));
        await tester.pumpAndSettle();
        final photo = tester.getRect(key('intake-new-photo'));
        final name = tester.getRect(key('intake-new-name'));
        expect(photo.bottom, lessThan(name.top));
        expect(tester.takeException(), isNull);
      },
    );
  }
}
