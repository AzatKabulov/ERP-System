import 'package:erp_system/features/auth/sign_in_screen.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/real_rig.dart';

void main() {
  setUp(() => rolePicker = true);
  tearDown(() => rolePicker = false);

  testWidgets('choosing a role asks for that account\'s password', (
    tester,
  ) async {
    final rig = RealRig();
    await rig.launch(tester);
    await settle(tester);
    expect(key('sign-in-username'), findsNothing);
    await tapKey(tester, 'sign-in-submit');
    await settle(tester);
    await tapKey(tester, 'test-login-manager');
    await settle(tester);
    await tester.enterText(key('role-login-password'), 'right-password');
    await tapKey(tester, 'role-login-submit');
    await settle(tester);
    expect(key('sign-in-submit'), findsNothing);
    expect(rig.server.log, contains('POST /api/v1/auth/login/'));
    expect(rig.server.log, isNot(contains('POST /api/v1/local-test-login/')));
  });

  testWidgets('a wrong password keeps the sign-in screen with an error', (
    tester,
  ) async {
    final rig = RealRig();
    await rig.launch(tester);
    await settle(tester);
    await tapKey(tester, 'sign-in-submit');
    await settle(tester);
    await tapKey(tester, 'test-login-owner');
    await settle(tester);
    await tester.enterText(key('role-login-password'), 'wrong');
    await tapKey(tester, 'role-login-submit');
    await settle(tester);
    expect(key('sign-in-submit'), findsOneWidget);
    expect(key('sign-in-error'), findsOneWidget);
  });

  testWidgets('ordinary username and password sign-in stays available', (
    tester,
  ) async {
    final rig = RealRig();
    await rig.launch(tester);
    await settle(tester);
    await tapKey(tester, 'test-login-toggle');
    await settle(tester);
    expect(key('sign-in-username'), findsOneWidget);
  });
}
