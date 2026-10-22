import 'package:erp_system/core/api/api_client.dart';
import 'package:erp_system/core/api/api_exception.dart';
import 'package:erp_system/core/config/app_config.dart';
import 'package:erp_system/core/session/token_stores.dart';
import 'package:erp_system/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/real_rig.dart' show settle;
import 'fake_server.dart';

class UnavailableTokenStore extends MemoryTokenStore {
  @override
  Future<void> writeRefreshToken(String token) async {
    throw UnsupportedError('Secure storage is unavailable');
  }
}

void main() {
  for (final language in ['ru', 'tk']) {
    testWidgets('a storage failure stays on sign-in with an error in $language', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({'language': language});
      await tester.pumpWidget(
        ErpApp(
          preferences: await SharedPreferences.getInstance(),
          config: const AppConfig(apiBaseUrl: 'https://api.example.test'),
          tokenStore: UnavailableTokenStore(),
          httpClient: FakeServer().client,
        ),
      );
      await settle(tester);
      await tester.enterText(
        find.byKey(const ValueKey('sign-in-username')),
        'aman',
      );
      await tester.enterText(
        find.byKey(const ValueKey('sign-in-password')),
        'right-password',
      );
      await tester.tap(find.byKey(const ValueKey('sign-in-submit')));
      await settle(tester);
      expect(find.byKey(const ValueKey('sign-in-submit')), findsOneWidget);
      expect(
        find.text(
          language == 'ru'
              ? 'Не удалось сохранить сеанс входа. В браузере откройте сайт по защищённому адресу HTTPS и повторите вход.'
              : 'Giriş sessiýasyny ýatda saklap bolmady. Brauzerde sahypany goragly HTTPS salgysy bilen açyň we täzeden giriň.',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }

  test('ordinary builds always use secure storage', () {
    expect(
      createTokenStore(isWeb: true, origin: Uri.parse('http://192.168.0.4')),
      isA<SecureTokenStore>(),
    );
  });

  for (final host in [
    '10.0.0.1',
    '172.16.0.1',
    '172.31.255.254',
    '192.168.0.4',
  ]) {
    test(
      'local web testing on $host keeps the session only in memory',
      () async {
        TokenStore store() => createTokenStore(
          isWeb: true,
          origin: Uri.parse('http://$host:8000'),
          localHttpTesting: true,
        );
        final tokens = store();
        expect(tokens, isA<MemoryTokenStore>());
        await tokens.writeRefreshToken('test-refresh');
        expect(await tokens.readRefreshToken(), 'test-refresh');
        expect(await store().readRefreshToken(), isNull);
        await tokens.clear();
        expect(await tokens.readRefreshToken(), isNull);
      },
    );
  }

  for (final address in [
    'https://192.168.0.4',
    'http://example.com',
    'http://192.168.0.4.example.com',
    'http://172.15.0.1',
    'http://172.32.0.1',
    'http://192.169.0.4',
    'http://8.8.8.8',
  ]) {
    test('the local test option keeps secure storage on $address', () {
      expect(
        createTokenStore(
          isWeb: true,
          origin: Uri.parse(address),
          localHttpTesting: true,
        ),
        isA<SecureTokenStore>(),
      );
    });
  }

  test(
    'native applications keep secure storage with the local test option',
    () {
      expect(
        createTokenStore(
          isWeb: false,
          origin: Uri.parse('http://192.168.0.4'),
          localHttpTesting: true,
        ),
        isA<SecureTokenStore>(),
      );
    },
  );

  test(
    'a failed session save gives a handled error and no access token',
    () async {
      final api = ApiClient(
        baseUrl: 'https://api.example.test',
        tokens: UnavailableTokenStore(),
        httpClient: FakeServer().client,
      );
      addTearDown(api.close);
      await expectLater(
        api.login('aman', 'right-password'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.code,
            'code',
            'session_storage_unavailable',
          ),
        ),
      );
      expect(api.hasAccessToken, isFalse);
    },
  );
}
