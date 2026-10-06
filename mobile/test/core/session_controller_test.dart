import 'package:erp_system/core/api/api_client.dart';
import 'package:erp_system/core/api/api_exception.dart';
import 'package:erp_system/core/session/session_controller.dart';
import 'package:erp_system/core/session/token_stores.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_server.dart';

class Rig {
  Rig._(this.server, this.tokens, this.prefs);

  final FakeServer server;
  final MemoryTokenStore tokens;
  final SharedPreferences prefs;
  late ApiClient api;
  late SessionController session;

  static Future<Rig> create({String? storedToken}) async {
    SharedPreferences.setMockInitialValues({});
    final rig = Rig._(
      FakeServer(),
      MemoryTokenStore(storedToken),
      await SharedPreferences.getInstance(),
    );
    rig.build();
    return rig;
  }

  /// A fresh app run on the same device (same token store and preferences).
  void build() {
    api = ApiClient(
      baseUrl: 'https://api.example.test',
      tokens: tokens,
      httpClient: server.client,
      onSessionExpired: () => session.handleSessionExpired(),
    );
    session = SessionController(api: api, preferences: prefs);
  }
}

void main() {
  test('without a stored token the app starts signed out', () async {
    final rig = await Rig.create();
    expect(rig.session.status, SessionStatus.restoring);
    await rig.session.restore();
    expect(rig.session.status, SessionStatus.signedOut);
    expect(rig.session.serverUnreachable, isFalse);
  });

  test(
    'a stored session is restored with profile, memberships and defaults',
    () async {
      final rig = await Rig.create(storedToken: 'refresh-1');
      await rig.session.restore();
      final s = rig.session;
      expect(s.status, SessionStatus.signedIn);
      expect(s.user!.displayName, 'Aman Ataýew');
      expect(s.membership!.businessName, 'Täze Dükan');
      expect(s.membership!.role, 'owner');
      expect(s.location!.name, 'Esasy dükan');
      expect(s.can('purchasing.receive'), isTrue);
      expect(s.can('stock.adjust'), isFalse);
    },
  );

  test(
    'an unreachable server at start-up keeps the stored token for the next try',
    () async {
      final rig = await Rig.create(storedToken: 'refresh-1');
      rig.server.reachable = false;
      await rig.session.restore();
      expect(rig.session.status, SessionStatus.signedOut);
      expect(rig.session.serverUnreachable, isTrue);
      expect(rig.tokens.token, 'refresh-1');
      rig.server.reachable = true;
      await rig.session.restore();
      expect(rig.session.status, SessionStatus.signedIn);
      expect(rig.session.serverUnreachable, isFalse);
    },
  );

  test(
    'a refresh token the server rejects at start-up leads to the sign-in screen',
    () async {
      final rig = await Rig.create(storedToken: 'stale-token');
      await rig.session.restore();
      expect(rig.session.status, SessionStatus.signedOut);
      expect(rig.session.serverUnreachable, isFalse);
    },
  );

  test('wrong password fails with a code and changes nothing', () async {
    final rig = await Rig.create();
    await rig.session.restore();
    await expectLater(
      rig.session.signIn('aman', 'wrong'),
      throwsA(
        isA<ApiException>().having(
          (e) => e.code,
          'code',
          'invalid_credentials',
        ),
      ),
    );
    expect(rig.session.status, SessionStatus.signedOut);
    expect(rig.tokens.token, isNull);
  });

  test('sign-in then sign-out clears the user and the stored token', () async {
    final rig = await Rig.create();
    await rig.session.restore();
    await rig.session.signIn('aman', 'right-password');
    expect(rig.session.status, SessionStatus.signedIn);
    expect(rig.tokens.token, 'refresh-1');
    await rig.session.signOut();
    expect(rig.session.status, SessionStatus.signedOut);
    expect(rig.session.user, isNull);
    expect(rig.session.membership, isNull);
    expect(rig.tokens.token, isNull);
  });

  test('the chosen location is remembered per user across app runs', () async {
    final rig = await Rig.create();
    await rig.session.restore();
    await rig.session.signIn('aman', 'right-password');
    rig.session.selectLocation('l-2');
    expect(rig.session.location!.name, 'Ammar');
    rig.session.selectLocation('does-not-exist'); // ignored
    expect(rig.session.location!.id, 'l-2');

    rig.build(); // restart
    await rig.session.restore();
    expect(rig.session.status, SessionStatus.signedIn);
    expect(rig.session.location!.id, 'l-2');
  });

  test(
    'when the server ends the session the user is signed out and told why',
    () async {
      final rig = await Rig.create();
      await rig.session.restore();
      await rig.session.signIn('aman', 'right-password');
      rig.server.expireAccess = true;
      rig.server.refreshRejected = true;
      await expectLater(
        rig.session.refreshProfile(),
        throwsA(isA<ApiException>()),
      );
      expect(rig.session.status, SessionStatus.signedOut);
      expect(rig.session.sessionExpired, isTrue);
      expect(rig.session.user, isNull);
      // signing in again clears the notice
      rig.server.refreshRejected = false;
      rig.server.expireAccess = false;
      await rig.session.signIn('aman', 'right-password');
      expect(rig.session.sessionExpired, isFalse);
    },
  );

  test(
    'the language is saved on the server, and a failure does not matter',
    () async {
      final rig = await Rig.create();
      await rig.session.restore();
      await rig.session.signIn('aman', 'right-password');
      await rig.session.saveLanguage('tk');
      expect((rig.server.me['user'] as Map)['preferred_language'], 'tk');
      rig.server.reachable = false;
      await rig.session.saveLanguage('ru'); // must not throw
    },
  );
}
