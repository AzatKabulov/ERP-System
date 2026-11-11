import 'dart:async';
import 'dart:convert';
import 'package:erp_system/core/api/api_client.dart';
import 'package:erp_system/core/api/api_exception.dart';
import 'package:erp_system/core/session/session_controller.dart';
import 'package:erp_system/core/session/token_stores.dart';
import 'package:erp_system/core/session/startup_snapshot.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'session_controller_test.dart' show Rig;

String token(String kind, {int seconds = 3600, String user = 'u-1'}) =>
    '${base64Url.encode(utf8.encode('{}'))}.${base64Url.encode(utf8.encode(jsonEncode({'token_type': kind, 'user_id': user, 'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + seconds})))}.test';

Future<Rig> savedSession() async {
  final rig = await Rig.create();
  rig.server.accessToken = token('access');
  rig.server.refreshToken = token('refresh');
  await rig.session.signIn('aman', 'right-password');
  await rig.session.cacheDashboard({
    'sales_today': {'count': 1, 'total': '100.00'},
  }, rig.session.dashboardScope);
  return rig;
}

void main() {
  for (final status in [201, 500]) {
    test(
      'logout preserves the actual outcome of an in-flight command ($status)',
      () async {
        final gate = Completer<void>();
        final started = Completer<void>();
        final api = ApiClient(
          baseUrl: 'https://api.example.test',
          tokens: MemoryTokenStore(),
          httpClient: MockClient((request) async {
            if (request.url.path.endsWith('/logout/')) {
              return http.Response('', 204);
            }
            started.complete();
            await gate.future;
            return http.Response('{}', status);
          }),
        );
        await api.adoptTokens('access', 'refresh');
        final command = api.post(
          '/api/v1/businesses/b-1/sales/',
          idempotencyKey: 'same-operation',
        );
        final checked = status == 201
            ? command.then((response) => expect(response.status, 201))
            : expectLater(
                command,
                throwsA(
                  isA<ApiException>().having(
                    (e) => e.outcomeUnknown,
                    'unknown command outcome',
                    true,
                  ),
                ),
              );
        await started.future;
        await api.logout();
        gate.complete();
        await checked;
        api.close();
      },
    );
  }

  test('a throttled refresh keeps the saved session for retry', () async {
    final tokens = MemoryTokenStore('saved-refresh');
    final api = ApiClient(
      baseUrl: 'https://api.example.test',
      tokens: tokens,
      httpClient: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'error': {'code': 'throttled'},
          }),
          429,
        ),
      ),
    );
    await expectLater(api.restoreSession(), throwsA(isA<ApiException>()));
    expect(tokens.token, 'saved-refresh');
    api.close();
  });

  test('old refresh cannot block or replace a newer account session', () async {
    final started = Completer<void>();
    final gate = Completer<void>();
    final tokens = MemoryTokenStore('old-refresh');
    final api = ApiClient(
      baseUrl: 'https://api.example.test',
      tokens: tokens,
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/refresh/')) {
          started.complete();
          await gate.future;
          return http.Response(
            jsonEncode({'access': 'old-access', 'refresh': 'old-rotated'}),
            200,
          );
        }
        if (request.url.path.endsWith('/login/')) {
          return http.Response(
            jsonEncode({'access': 'new-access', 'refresh': 'new-refresh'}),
            200,
          );
        }
        expect(request.headers['Authorization'], 'Bearer new-access');
        return http.Response('{}', 200);
      }),
    );
    final restoring = api.restoreSession();
    await started.future;
    await api.login('another', 'password');
    await api.get('/api/v1/me/').timeout(const Duration(seconds: 1));
    gate.complete();
    expect(await restoring, isFalse);
    expect(tokens.token, 'new-refresh');
    expect(await tokens.readAccessToken(api.baseUrl), 'new-access');
    api.close();
  });

  test(
    'overlapping reads coalesce, mutations and logout invalidate them',
    () async {
      final rig = await savedSession();
      final gate = Completer<void>();
      rig.server.readPaths.clear();
      rig.server.readWaits['/api/v1/me/'] = gate.future;
      final first = rig.api.get('/api/v1/me/');
      expect(identical(first, rig.api.get('/api/v1/me/')), isTrue);
      await Future<void>.delayed(Duration.zero);
      expect(rig.server.readPaths.where((p) => p == '/api/v1/me/').length, 1);
      await rig.api.patch('/api/v1/me/', body: {'preferred_language': 'tk'});
      final second = rig.api.get('/api/v1/me/');
      expect(identical(first, second), isFalse);
      final failures = Future.wait([
        expectLater(first, throwsA(isA<ApiException>())),
        expectLater(second, throwsA(isA<ApiException>())),
      ]);
      await rig.session.signOut();
      gate.complete();
      await failures;
    },
  );

  test(
    'warm restore skips refresh and overlaps profile with dashboard',
    () async {
      final rig = await savedSession();
      rig.build();
      final gate = Completer<void>();
      rig.server.readWaits['/api/v1/me/'] = gate.future;
      final task = rig.session.restore();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(rig.session.hasPreview, isTrue);
      expect(rig.session.status, SessionStatus.restoring);
      expect(rig.session.can('sales.create'), isFalse);
      expect(
        rig.session.cachedDashboard,
        isNull,
        reason: 'no private cache before fresh permissions',
      );
      expect(
        rig.server.readPaths,
        contains('/api/v1/businesses/b-1/dashboard/'),
      );
      expect(rig.server.refreshCalls, 0);
      gate.complete();
      await task;
      expect(rig.session.status, SessionStatus.signedIn);
      expect(rig.session.cachedDashboard, isNotNull);
      final pending = rig.session.takeStartupDashboard();
      expect(pending, isNotNull);
      await pending;
      expect(rig.session.takeStartupDashboard(), isNull);
    },
  );

  test(
    'expired access follows refresh without discarding the session',
    () async {
      final rig = await savedSession();
      await rig.tokens.writeAccessToken(
        rig.api.baseUrl,
        token('access', seconds: -1),
      );
      rig.build();
      await rig.session.restore();
      expect(rig.server.refreshCalls, 1);
      expect(rig.session.status, SessionStatus.signedIn);
    },
  );

  test(
    'revoked session clears snapshot and cannot paint cached money',
    () async {
      final rig = await savedSession();
      rig.server.expireAccess = true;
      rig.server.refreshRejected = true;
      rig.build();
      await rig.session.restore();
      expect(rig.session.status, SessionStatus.signedOut);
      expect(rig.session.hasPreview, isFalse);
      expect(rig.session.cachedDashboard, isNull);
      expect(await rig.tokens.readStartupSnapshot(rig.api.baseUrl), isNull);
    },
  );

  test('offline restore keeps a locked preview and can retry', () async {
    final rig = await savedSession();
    rig.server.reachable = false;
    rig.build();
    await rig.session.restore();
    expect(rig.session.hasPreview, isTrue);
    expect(rig.session.serverUnreachable, isTrue);
    expect(rig.session.can('catalog.view'), isFalse);
    expect(rig.session.cachedDashboard, isNull);
    rig.server.reachable = true;
    await rig.session.restore();
    expect(rig.session.status, SessionStatus.signedIn);
  });

  test('changed permissions invalidate private dashboard snapshot', () async {
    final rig = await savedSession();
    rig.server.permissions.remove('sales.cost.view');
    rig.build();
    await rig.session.restore();
    expect(rig.session.cachedDashboard, isNull);
    expect(rig.session.takeStartupDashboard(), isNull);
  });

  for (final state in ['read_only', 'suspended']) {
    test('$state subscription cannot revive a cached overview', () async {
      final rig = await savedSession();
      (rig.server.me['memberships'] as List).first['subscription'] = {
        'state': state,
      };
      rig.build();
      await rig.session.restore();
      expect(rig.session.subscription!.isBlocked, isTrue);
      expect(rig.session.cachedDashboard, isNull);
      expect(rig.session.takeStartupDashboard(), isNull);
    });
  }

  test('server switch never reuses access token or startup snapshot', () async {
    final rig = await savedSession();
    await rig.api.switchServer('https://another.example.test');
    expect(await rig.tokens.readAccessToken(rig.api.baseUrl), isNull);
    expect(await rig.tokens.readStartupSnapshot(rig.api.baseUrl), isNull);
  });

  test(
    'corrupt snapshot fails open to server loading, not local authorization',
    () async {
      final rig = await savedSession();
      await rig.tokens.writeStartupSnapshot(rig.api.baseUrl, 'not json');
      rig.build();
      await rig.session.restore();
      expect(rig.session.status, SessionStatus.signedIn);
      expect(rig.session.cachedDashboard, isNull);
    },
  );

  test('expired or oversized snapshot is not retained', () async {
    final rig = await savedSession();
    final old =
        jsonDecode((await rig.tokens.readStartupSnapshot(rig.api.baseUrl))!)
            as Map;
    old['verified_at'] = DateTime.now()
        .subtract(const Duration(days: 2))
        .toIso8601String();
    await rig.tokens.writeStartupSnapshot(rig.api.baseUrl, jsonEncode(old));
    final snapshot = StartupSnapshot(rig.api);
    await snapshot.read();
    expect(snapshot.profile, isNull);
    await rig.tokens.writeStartupSnapshot(rig.api.baseUrl, 'x' * 70000);
    await snapshot.read();
    expect(snapshot.profile, isNull);
  });

  test(
    'logout during a delayed restore cannot resurrect user or snapshot',
    () async {
      final rig = await savedSession();
      rig.build();
      final gate = Completer<void>();
      rig.server.readWaits['/api/v1/me/'] = gate.future;
      final restore = rig.session.restore();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await rig.session.signOut();
      gate.complete();
      await restore;
      expect(rig.session.status, SessionStatus.signedOut);
      expect(rig.session.user, isNull);
      expect(await rig.tokens.readStartupSnapshot(rig.api.baseUrl), isNull);
    },
  );
}
