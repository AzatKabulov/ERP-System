import 'package:erp_system/core/api/api_client.dart';
import 'package:erp_system/core/config/app_config.dart';
import 'package:erp_system/core/config/server_settings.dart';
import 'package:erp_system/core/session/token_stores.dart';
import 'package:erp_system/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/real_rig.dart';
import 'stock_ops_test.dart' show fieldNames;

Future<void> openDialog(WidgetTester tester) async {
  await tapKey(tester, 'server-change');
  await settle(tester, ms: 400);
}

Future<void> saveAddress(WidgetTester tester, String address) async {
  await tester.enterText(key('server-url'), address);
  await tester.pump();
  await tapKey(tester, 'server-save');
  await settle(tester, ms: 600);
}

SharedPreferences? prefsForTests;

void main() {
  group('normalising an address', () {
    test('keeps only scheme, host and port', () {
      expect(
        ServerSettings.normalize('https://Shop.Example.com/'),
        'https://shop.example.com',
      );
      expect(
        ServerSettings.normalize('  shop.example.com  '),
        'https://shop.example.com',
      );
      expect(
        ServerSettings.normalize('https://10.0.0.5:8443'),
        'https://10.0.0.5:8443',
      );
    });

    test('refuses what is not an address', () {
      for (final bad in [
        '',
        'two words',
        'ftp://shop.example.com',
        'https://shop.example.com/api',
        'https://user:pass@shop.example.com',
        'https://shop.example.com?x=1',
      ]) {
        expect(ServerSettings.normalize(bad), isNull, reason: bad);
      }
    });
  });

  group('checking an address', () {
    ServerSettings settings({bool allowInsecure = false}) {
      SharedPreferences.setMockInitialValues({});
      return ServerSettings(
        preferences: prefsForTests!,
        api: ApiClient(
          baseUrl: 'https://x.example.test',
          tokens: MemoryTokenStore(),
        ),
        httpClient: MockClient((request) async {
          if (request.url.host == 'dead.example.test') {
            throw http.ClientException('no route');
          }
          return http.Response('{"status":"ok"}', 200);
        }),
        allowInsecure: allowInsecure,
      );
    }

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefsForTests = await SharedPreferences.getInstance();
    });

    test('plain http is refused unless this is a development build', () async {
      expect(
        await settings().check('http://shop.example.com'),
        ServerCheck.insecure,
      );
      expect(
        await settings(allowInsecure: true).check('http://shop.example.com'),
        ServerCheck.ok,
      );
      expect(
        await settings().check('https://shop.example.com'),
        ServerCheck.ok,
      );
    });

    test('an address nobody answers on is unreachable', () async {
      expect(
        await settings().check('https://dead.example.test'),
        ServerCheck.unreachable,
      );
    });
  });

  group('the server address on the sign-in screen', () {
    testWidgets('shows the address of this build and signs in there', (
      tester,
    ) async {
      final rig = RealRig();
      await rig.launch(tester);
      expect(find.text('Сервер: https://api.example.test'), findsOneWidget);
      await rig.signIn(tester);
      expect(key('welcome'), findsOneWidget);
      expect(rig.server.hosts.toSet(), {'https://api.example.test'});
    });

    testWidgets('another server is checked, kept and used for signing in', (
      tester,
    ) async {
      final rig = RealRig();
      await rig.launch(tester);
      await openDialog(tester);
      await saveAddress(tester, 'shop.example.com');
      expect(find.text('Адрес сервера сохранён.'), findsOneWidget);
      expect(find.text('Сервер: https://shop.example.com'), findsOneWidget);
      expect(rig.prefs.getString('server_url'), 'https://shop.example.com');
      await rig.signIn(tester);
      expect(key('welcome'), findsOneWidget);
      // the health check went to the new address, and so did the sign-in
      expect(rig.server.hosts.last, 'https://shop.example.com');
      expect(
        rig.server.hosts.where((h) => h == 'https://shop.example.com').length,
        greaterThan(2),
      );
    });

    testWidgets('the chosen address is still there after a restart', (
      tester,
    ) async {
      final rig = RealRig();
      await rig.launch(tester);
      await openDialog(tester);
      await saveAddress(tester, 'https://shop.example.com');
      await tester.pumpWidget(const SizedBox());
      // a new start of the app: the same preferences, nothing else remembered
      await tester.pumpWidget(
        ErpApp(
          preferences: rig.prefs,
          config: const AppConfig(apiBaseUrl: 'https://api.example.test'),
          httpClient: rig.server.client,
          tokenStore: MemoryTokenStore(),
        ),
      );
      await settle(tester);
      expect(find.text('Сервер: https://shop.example.com'), findsOneWidget);
    });

    for (final c in [
      ('not an address', 'two words', 'Введите адрес вида'),
      ('nobody there', 'dead.example.test', 'Сервер не отвечает'),
      ('another site', 'stranger.example.test', 'нет сервера этой системы'),
      ('database down', 'dbdown.example.test', 'база данных сейчас недоступна'),
    ]) {
      testWidgets('${c.$1}: says what is wrong and keeps the old address', (
        tester,
      ) async {
        final rig = RealRig();
        rig.server.deadHosts.add('https://dead.example.test');
        rig.server.strangerHosts.add('https://stranger.example.test');
        rig.server.databaseDownHosts.add('https://dbdown.example.test');
        await rig.launch(tester);
        await openDialog(tester);
        await saveAddress(tester, c.$2);
        expect(key('server-error'), findsOneWidget);
        expect(find.textContaining(c.$3), findsOneWidget);
        expect(rig.prefs.getString('server_url'), isNull);
        await tapKey(tester, 'server-cancel');
        await settle(tester, ms: 400);
        expect(find.text('Сервер: https://api.example.test'), findsOneWidget);
      });
    }

    testWidgets(
      'a build with no address asks for one, and then signing in works',
      (tester) async {
        final rig = RealRig(config: const AppConfig(apiBaseUrl: ''));
        await rig.launch(tester);
        expect(key('notice-unconfigured'), findsOneWidget);
        expect(find.text('Сервер не выбран'), findsOneWidget);
        await openDialog(tester);
        await saveAddress(tester, 'https://shop.example.com');
        expect(key('notice-unconfigured'), findsNothing);
        await rig.signIn(tester);
        expect(key('welcome'), findsOneWidget);
      },
    );

    testWidgets('the field has its own name for a screen reader', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final rig = RealRig();
      await rig.launch(tester);
      await openDialog(tester);
      expect(fieldNames(tester), contains('Адрес сервера'));
      handle.dispose();
    });

    testWidgets('fits a phone with doubled text', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final rig = RealRig();
      await rig.launch(tester, size: const Size(360, 800));
      expect(tester.takeException(), isNull, reason: 'sign-in');
      await openDialog(tester);
      await saveAddress(tester, 'dead.example.test');
      expect(tester.takeException(), isNull, reason: 'dialog');
    });
  });
}
