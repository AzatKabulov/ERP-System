import 'dart:convert';

import 'package:erp_system/core/api/api_client.dart';
import 'package:erp_system/core/api/api_exception.dart';
import 'package:erp_system/core/connectivity/connection_monitor.dart';
import 'package:erp_system/core/session/token_stores.dart';
import 'package:flutter/foundation.dart' show VoidCallback;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'fake_server.dart';

ApiClient clientFor(
  FakeServer server,
  MemoryTokenStore tokens, {
  ConnectionMonitor? monitor,
  VoidCallback? onExpired,
  Duration timeout = const Duration(seconds: 5),
}) => ApiClient(
  baseUrl: 'https://api.example.test/',
  tokens: tokens,
  httpClient: server.client,
  monitor: monitor,
  onSessionExpired: onExpired,
  timeout: timeout,
);

void main() {
  test(
    'login stores the refresh token and sends the bearer token afterwards',
    () async {
      final server = FakeServer();
      final tokens = MemoryTokenStore();
      final api = clientFor(server, tokens);
      await api.login(' aman ', 'right-password');
      expect(tokens.token, 'refresh-1');
      final me = await api.get('/api/v1/me/');
      expect(me.map['user']['username'], 'aman');
      final last = server.requestHeaders.last;
      expect(last['Authorization'], 'Bearer access-1');
      expect(last['X-Request-ID'], isNotEmpty);
      expect(last['Accept'], 'application/json');
    },
  );

  test(
    'Russian and Turkmen text survives even without a charset header',
    () async {
      final server = FakeServer();
      final api = clientFor(server, MemoryTokenStore());
      await api.login('aman', 'right-password');
      final me = await api.get('/api/v1/me/');
      expect(me.map['user']['full_name'], 'Aman Ataýew');
      expect(me.map['memberships'][0]['business']['name'], 'Täze Dükan');
      // and the request body is sent as UTF-8
      await api.post(
        '/api/v1/businesses/b-1/demo/',
        body: {'n': 1, 'note': 'Şäher Ýüpek Ç ň Ž Тормозные колодки'},
        idempotencyKey: 'k-1',
      );
      expect(
        server.performed.single['note'],
        'Şäher Ýüpek Ç ň Ž Тормозные колодки',
      );
    },
  );

  test(
    'error envelopes become ApiException with code, fields and request id',
    () async {
      final client = MockClient(
        (request) async => http.Response(
          jsonEncode({
            'error': {
              'code': 'validation_error',
              'message': 'Invalid input',
              'request_id': 'abc',
              'fields': {
                'new_password': [
                  {'code': 'password_too_short', 'message': 'short'},
                ],
              },
            },
          }),
          400,
        ),
      );
      final api = ApiClient(
        baseUrl: 'https://x.test',
        tokens: MemoryTokenStore(),
        httpClient: client,
      );
      try {
        await api.post(
          '/api/v1/auth/password/change/',
          body: {},
          authenticated: false,
        );
        fail('should throw');
      } on ApiException catch (e) {
        expect(e.code, 'validation_error');
        expect(e.status, 400);
        expect(e.requestId, 'abc');
        expect(e.fieldCode('new_password'), 'password_too_short');
        expect(e.isDefinitive, isTrue);
        expect(e.outcomeUnknown, isFalse);
      }
    },
  );

  test(
    'an expired access token is refreshed once and the call re-sent with the same key',
    () async {
      final server = FakeServer();
      final tokens = MemoryTokenStore();
      final api = clientFor(server, tokens);
      await api.login('aman', 'right-password');
      server.expireAccess = true;
      final response = await api.post(
        '/api/v1/businesses/b-1/demo/',
        body: {'n': 1},
        idempotencyKey: 'key-1',
      );
      expect(response.status, 201);
      expect(server.refreshCalls, 1);
      expect(tokens.token, 'refresh-2'); // rotated and stored
      expect(server.performed, hasLength(1));
      final keys = server.requestHeaders
          .where((h) => h['Idempotency-Key'] != null)
          .map((h) => h['Idempotency-Key'])
          .toSet();
      expect(keys, {'key-1'});
    },
  );

  test('requests that fail together share a single refresh', () async {
    final server = FakeServer();
    final api = clientFor(server, MemoryTokenStore());
    await api.login('aman', 'right-password');
    server.expireAccess = true;
    final results = await Future.wait([
      api.get('/api/v1/me/'),
      api.get('/api/v1/me/'),
      api.get('/api/v1/me/'),
    ]);
    expect(results.map((r) => r.status), everyElement(200));
    expect(server.refreshCalls, 1);
  });

  test(
    'a refused refresh token ends the session: tokens cleared, callback fired',
    () async {
      final server = FakeServer();
      final tokens = MemoryTokenStore();
      var expired = 0;
      final api = clientFor(server, tokens, onExpired: () => expired++);
      await api.login('aman', 'right-password');
      server.expireAccess = true;
      server.refreshRejected = true;
      await expectLater(
        api.get('/api/v1/me/'),
        throwsA(
          isA<ApiException>().having((e) => e.code, 'code', 'session_expired'),
        ),
      );
      expect(tokens.token, isNull);
      expect(expired, 1);
      expect(api.hasAccessToken, isFalse);
    },
  );

  test('a network failure while refreshing does not sign anyone out', () async {
    final server = FakeServer();
    final tokens = MemoryTokenStore();
    var expired = 0;
    server.expireAccess = true;
    // the first call answers 401, then the network drops before the refresh
    var calls = 0;
    final flaky = MockClient((request) async {
      calls++;
      if (calls == 1) {
        return server.client.send(request).then(http.Response.fromStream);
      }
      throw http.ClientException('offline');
    });
    final api2 = ApiClient(
      baseUrl: 'https://api.example.test',
      tokens: tokens,
      httpClient: flaky,
      onSessionExpired: () => expired++,
    );
    await api2.adoptTokens('access-1', 'refresh-1');
    await expectLater(
      api2.get('/api/v1/me/'),
      throwsA(
        isA<ApiException>().having((e) => e.kind, 'kind', ApiErrorKind.network),
      ),
    );
    expect(tokens.token, 'refresh-1'); // kept: the user is still signed in
    expect(expired, 0);
  });

  test('the connection monitor follows success and failure', () async {
    final server = FakeServer();
    final monitor = ConnectionMonitor();
    final api = clientFor(server, MemoryTokenStore(), monitor: monitor);
    await api.login('aman', 'right-password');
    expect(monitor.online, isTrue);
    server.reachable = false;
    await expectLater(api.get('/api/v1/me/'), throwsA(isA<ApiException>()));
    expect(monitor.online, isFalse);
    server.reachable = true;
    await api.get('/api/v1/me/');
    expect(monitor.online, isTrue);
    expect(monitor.lastSuccess, isNotNull);
  });

  test(
    'a slow server is reported as a timeout, which leaves the outcome unknown',
    () async {
      final slow = MockClient((request) async {
        await Future<void>.delayed(const Duration(milliseconds: 300));
        return http.Response('{}', 200);
      });
      final api = ApiClient(
        baseUrl: 'https://x.test',
        tokens: MemoryTokenStore(),
        httpClient: slow,
        timeout: const Duration(milliseconds: 30),
      );
      try {
        await api.get('/x', query: null);
        fail('should time out');
      } on ApiException catch (e) {
        expect(e.kind, ApiErrorKind.timeout);
        expect(e.outcomeUnknown, isTrue);
        expect(e.isDefinitive, isFalse);
      }
    },
  );

  test(
    '204 answers, unreadable 2xx answers and 5xx answers are classified correctly',
    () async {
      Future<ApiResponse> call(int status, String body) => ApiClient(
        baseUrl: 'https://x.test',
        tokens: MemoryTokenStore(),
        httpClient: MockClient((_) async => http.Response(body, status)),
      ).get('/x');
      expect((await call(204, '')).status, 204);
      await expectLater(
        call(200, 'not json'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.outcomeUnknown,
            'unknown',
            isTrue,
          ),
        ),
      );
      await expectLater(
        call(502, '<html>bad gateway</html>'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.kind, 'kind', ApiErrorKind.server)
              .having((e) => e.outcomeUnknown, 'unknown', isTrue),
        ),
      );
    },
  );

  test(
    'restoreSession reports false without a token and rethrows when unreachable',
    () async {
      final server = FakeServer();
      final api = clientFor(server, MemoryTokenStore());
      expect(await api.restoreSession(), isFalse);

      final tokens = MemoryTokenStore('refresh-1');
      final api2 = clientFor(server, tokens);
      server.reachable = false;
      await expectLater(api2.restoreSession(), throwsA(isA<ApiException>()));
      expect(
        tokens.token,
        'refresh-1',
      ); // not forgotten just because we are offline
      server.reachable = true;
      expect(await api2.restoreSession(), isTrue);
    },
  );

  test(
    'logout revokes the token on the server and forgets it locally',
    () async {
      final server = FakeServer();
      final tokens = MemoryTokenStore();
      final api = clientFor(server, tokens);
      await api.login('aman', 'right-password');
      await api.logout();
      expect(tokens.token, isNull);
      expect(server.refreshRejected, isTrue);
      expect(api.hasAccessToken, isFalse);
      // even when the server cannot be reached, the device is signed out
      final api2 = clientFor(server, MemoryTokenStore('x'));
      server.reachable = false;
      await api2.logout();
    },
  );
}
