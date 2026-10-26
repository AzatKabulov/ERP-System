import 'package:flutter_test/flutter_test.dart';

import '../support/real_rig.dart';

void main() {
  testWidgets('local testing also retains ordinary password sign-in', (
    tester,
  ) async {
    final rig = RealRig();
    rig.server.localTestLogin = true;
    await rig.launch(tester);
    await settle(tester);
    expect(key('sign-in-username'), findsNothing);
    await tapKey(tester, 'test-login-toggle');
    await settle(tester);
    await tester.enterText(key('sign-in-username'), 'owner');
    await tester.enterText(key('sign-in-password'), 'right-password');
    await tapKey(tester, 'sign-in-submit');
    await settle(tester);
    expect(rig.server.log, contains('POST /api/v1/auth/login/'));
    expect(key('test-login-owner'), findsNothing);
  });

  for (final role in ['owner', 'manager', 'sales', 'warehouse']) {
    testWidgets('local role picker enters as $role without credentials', (
      tester,
    ) async {
      final rig = RealRig();
      rig.server.localTestLogin = true;
      await rig.launch(tester);
      await settle(tester);
      await tapKey(tester, 'sign-in-submit');
      await settle(tester);
      await tapKey(tester, 'test-login-$role');
      await settle(tester);
      expect(key('sign-in-submit'), findsNothing);
      expect((rig.server.me['memberships'] as List).first['role'], role);
      expect(rig.server.log, contains('POST /api/v1/local-test-login/'));
      expect(rig.server.log, isNot(contains('POST /api/v1/auth/login/')));
    });
  }

  testWidgets('ordinary servers still require credentials', (tester) async {
    final rig = RealRig();
    await rig.launch(tester);
    await settle(tester);
    await tapKey(tester, 'sign-in-submit');
    await settle(tester);
    expect(key('test-login-owner'), findsNothing);
    expect(key('sign-in-error'), findsOneWidget);
    expect(rig.server.log, isNot(contains('POST /api/v1/local-test-login/')));
  });
}
