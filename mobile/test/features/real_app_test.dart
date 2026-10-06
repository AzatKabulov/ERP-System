import 'package:erp_system/core/api/api_client.dart';
import 'package:erp_system/core/config/app_config.dart';
import 'package:erp_system/core/connectivity/connection_monitor.dart';
import 'package:erp_system/core/operations/operation_runner.dart';
import 'package:erp_system/core/operations/pending_operation.dart';
import 'package:erp_system/core/operations/pending_operation_store.dart';
import 'package:erp_system/core/session/session_controller.dart';
import 'package:erp_system/core/session/token_stores.dart';
import 'package:erp_system/features/workspace/real_workspace.dart';
import 'package:erp_system/features/workspace/unsaved_work.dart';
import 'package:erp_system/l10n/app_localizations.dart';
import 'package:erp_system/l10n/turkmen_localizations.dart';
import 'package:erp_system/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/fake_server.dart';
import '../support/real_rig.dart';

void main() {
  group('sign-in', () {
    testWidgets('a real build starts at sign-in and never shows demo data', (
      tester,
    ) async {
      final rig = RealRig();
      await rig.launch(tester);
      expect(key('sign-in-submit'), findsOneWidget);
      expect(find.text(demoBanner), findsNothing);
      expect(find.text('Масляный фильтр'), findsNothing);
      expect(
        rig.server.log,
        isEmpty,
      ); // nothing to restore, so no request was made
    });

    testWidgets('wrong password: a translated message, in both languages', (
      tester,
    ) async {
      final rig = RealRig();
      await rig.launch(tester);
      await rig.signIn(tester, password: 'nope');
      expect(find.text('Неверный логин или пароль.'), findsOneWidget);
      expect(find.textContaining('invalid_credentials'), findsNothing);
      await tapKey(tester, 'language-selector');
      await settle(tester, ms: 400);
      await tester.tap(find.text('Türkmençe').last);
      await settle(tester, ms: 400);
      expect(find.text('Login ýa-da parol nädogry.'), findsOneWidget);
    });

    testWidgets(
      'right password opens the workspace and keeps the refresh token',
      (tester) async {
        final rig = RealRig();
        await rig.launchSignedIn(tester);
        expect(key('welcome'), findsOneWidget);
        expect(find.text('Здравствуйте, Aman Ataýew!'), findsOneWidget);
        expect(rig.tokens.token, 'refresh-1');
        expect(find.text(demoBanner), findsNothing);
      },
    );

    testWidgets('empty fields are refused without contacting the server', (
      tester,
    ) async {
      final rig = RealRig();
      await rig.launch(tester);
      await tapKey(tester, 'sign-in-submit');
      await settle(tester, ms: 200);
      expect(find.text('Проверьте введённые данные.'), findsOneWidget);
      expect(rig.server.log, isEmpty);
    });

    testWidgets('a double tap sends one request', (tester) async {
      final rig = RealRig();
      await rig.launch(tester);
      await tester.enterText(key('sign-in-username'), 'aman');
      await tester.enterText(key('sign-in-password'), 'right-password');
      await tester.tap(key('sign-in-submit'));
      await tester.tap(key('sign-in-submit'), warnIfMissed: false);
      await settle(tester);
      expect(
        rig.server.log.where((l) => l == 'POST /api/v1/auth/login/'),
        hasLength(1),
      );
    });

    testWidgets("the server's saved language applies after signing in", (
      tester,
    ) async {
      final rig = RealRig();
      (rig.server.me['user'] as Map)['preferred_language'] = 'tk';
      await rig.launch(tester);
      await rig.signIn(tester);
      expect(find.text('Salam, Aman Ataýew!'), findsOneWidget);
      expect(rig.prefs.getString('language'), 'tk');
    });

    testWidgets('a stored session is restored without asking for a password', (
      tester,
    ) async {
      final rig = RealRig(storedToken: 'refresh-1');
      await rig.launch(tester);
      expect(key('sign-in-submit'), findsNothing);
      expect(key('welcome'), findsOneWidget);
    });

    testWidgets(
      'an unreachable server at start-up is explained and can be retried',
      (tester) async {
        final rig = RealRig(storedToken: 'refresh-1');
        rig.server.reachable = false;
        await rig.launch(tester);
        expect(key('notice-unreachable'), findsOneWidget);
        expect(rig.tokens.token, 'refresh-1');
        rig.server.reachable = true;
        await tapKey(tester, 'retry-restore');
        await settle(tester);
        expect(key('welcome'), findsOneWidget);
      },
    );

    testWidgets('a build without a server address says so and cannot sign in', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1000, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(
        ErpApp(
          preferences: await SharedPreferences.getInstance(),
          config: const AppConfig(apiBaseUrl: ''),
          tokenStore: MemoryTokenStore(),
        ),
      );
      await settle(tester);
      expect(key('notice-unconfigured'), findsOneWidget);
      final button = tester.widget<FilledButton>(
        find.descendant(
          of: key('sign-in-submit'),
          matching: find.byType(FilledButton),
        ),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets(
      'signing out returns to the sign-in screen and forgets the token',
      (tester) async {
        final rig = RealRig();
        await rig.launchSignedIn(tester);
        await tapKey(tester, 'sidebar-sign-out');
        await settle(tester);
        expect(key('sign-in-submit'), findsOneWidget);
        expect(rig.tokens.token, isNull);
      },
    );

    testWidgets('when the server ends the session the user is told why', (
      tester,
    ) async {
      final rig = RealRig();
      await rig.launchSignedIn(tester);
      rig.server.expireAccess = true;
      rig.server.refreshRejected = true;
      await tapKey(tester, 'nav-administration');
      await settle(tester);
      expect(key('sign-in-submit'), findsOneWidget);
      expect(key('notice-expired'), findsOneWidget);
    });
  });

  group('password recovery screens', () {
    testWidgets('request a code, then set a new password with it', (
      tester,
    ) async {
      final rig = RealRig();
      await rig.launch(tester);
      await tapKey(tester, 'forgot-password');
      await settle(tester, ms: 400);
      await tester.enterText(key('reset-identifier'), 'aman');
      await tapKey(tester, 'reset-send');
      await settle(tester, ms: 300);
      expect(rig.server.resetRequests, ['aman']);
      expect(key('reset-sent'), findsOneWidget);

      // a wrong code is refused with a translated message
      await tester.enterText(key('reset-code'), 'WRONGCOD');
      await tester.enterText(key('reset-new-password'), 'a-new-passphrase-12');
      await tapKey(tester, 'reset-confirm');
      await settle(tester, ms: 300);
      expect(find.text('Код неверный или истёк.'), findsOneWidget);

      // a weak password is refused with the reason, and the correct code is not burnt
      await tester.enterText(key('reset-code'), 'ABCD2345');
      await tester.enterText(key('reset-new-password'), 'short');
      await tapKey(tester, 'reset-confirm');
      await settle(tester, ms: 300);
      expect(find.textContaining('Пароль слишком короткий'), findsOneWidget);

      await tester.enterText(key('reset-new-password'), 'a-new-passphrase-12');
      await tapKey(tester, 'reset-confirm');
      await settle(tester, ms: 300);
      expect(find.text('Пароль сохранён. Теперь войдите.'), findsOneWidget);
      expect(rig.server.passwordResetTo, 'a-new-passphrase-12');
      await tapKey(tester, 'reset-done-back');
      await settle(tester, ms: 400);
      expect(key('sign-in-submit'), findsOneWidget);
    });

    testWidgets('the screens speak Turkmen too', (tester) async {
      final rig = RealRig();
      await rig.launch(tester, prefsValues: {'language': 'tk'});
      await tapKey(tester, 'forgot-password');
      await settle(tester, ms: 400);
      expect(find.text('Paroly dikeltmek'), findsWidgets);
      expect(find.text('Kody ibermek'), findsOneWidget);
    });
  });

  group('navigation and honesty about unfinished pages', () {
    testWidgets(
      'an owner sees every page; unfinished ones say so and show no demo data',
      (tester) async {
        final rig = RealRig();
        await rig.launchSignedIn(tester);
        for (final page in [
          'dashboard',
          'products',
          'inventory',
          'purchasing',
          'sales',
          'expenses',
          'warranties',
          'reports',
          'administration',
        ]) {
          expect(key('nav-$page'), findsOneWidget, reason: page);
        }
        await tapKey(tester, 'nav-sales');
        await settle(tester, ms: 300);
        expect(find.text('Раздел появится позже'), findsOneWidget);
        expect(find.text('Масляный фильтр'), findsNothing);
        expect(find.text('Завершить демо-продажу'), findsNothing);
      },
    );

    testWidgets('pages the role may not use are not offered', (tester) async {
      final rig = RealRig();
      rig.server.role = 'sales';
      rig.server.permissions = [
        'business.view',
        'location.view',
        'catalog.view',
        'stock.view',
      ];
      await rig.launchSignedIn(tester);
      expect(key('nav-products'), findsOneWidget);
      expect(key('nav-inventory'), findsOneWidget);
      expect(key('nav-purchasing'), findsNothing);
    });

    testWidgets(
      'a user with no business sees a clear message and can sign out',
      (tester) async {
        final rig = RealRig();
        rig.server.me['memberships'] = <Map<String, dynamic>>[];
        await rig.launchSignedIn(tester);
        expect(key('no-business'), findsOneWidget);
        await tapKey(tester, 'no-business-sign-out');
        await settle(tester);
        expect(key('sign-in-submit'), findsOneWidget);
      },
    );

    testWidgets('the header shows the real locations of the business', (
      tester,
    ) async {
      final rig = RealRig();
      await rig.launchSignedIn(tester);
      expect(
        find.descendant(
          of: key('location-selector'),
          matching: find.text('Esasy dükan'),
        ),
        findsOneWidget,
      );
      await tapKey(tester, 'location-selector');
      await settle(tester, ms: 300);
      await tester.tap(find.text('Ammar').last);
      await settle(tester, ms: 300);
      expect(
        find.descendant(
          of: key('location-selector'),
          matching: find.text('Ammar'),
        ),
        findsOneWidget,
      );
    });
  });

  group('connection and pending operations', () {
    testWidgets(
      'losing the connection is shown, and clears once the server answers',
      (tester) async {
        final rig = RealRig();
        await rig.launchSignedIn(tester);
        expect(key('offline-banner'), findsNothing);
        rig.server.reachable = false;
        await tapKey(tester, 'nav-administration');
        await settle(tester);
        expect(key('offline-banner'), findsOneWidget);
        expect(find.text('Нет связи с сервером.'), findsWidgets);
        rig.server.reachable = true;
        await tester.ensureVisible(key('retry-load').first);
        await tester.pump();
        await tester.tap(key('retry-load').first);
        await settle(tester);
        expect(key('offline-banner'), findsNothing);
      },
    );

    PendingOperation op({String key = 'k-1'}) => PendingOperation(
      key: key,
      action: 'demo',
      userId: 'u-1',
      businessId: 'b-1',
      path: '/api/v1/businesses/b-1/demo/',
      body: {'n': 1},
      createdAt: DateTime.utc(2026, 10, 6, 9, 30),
      subject: 'PO-000012',
      state: PendingState.unknown,
    );

    testWidgets(
      'an operation the server never saw is listed after a restart and can be discarded',
      (tester) async {
        final rig = RealRig(storedToken: 'refresh-1', pending: [op()]);
        await rig.launch(tester);
        expect(find.text('Ожидают подтверждения: 1'), findsOneWidget);
        await tapKey(tester, 'pending-review');
        await settle(tester, ms: 300);
        expect(find.textContaining('PO-000012'), findsOneWidget);
        expect(
          find.textContaining('Сервер не получил это действие'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'an operation the server did commit disappears by itself after a restart',
      (tester) async {
        final rig = RealRig(storedToken: 'refresh-1', pending: [op()]);
        rig.server.records['k-1'] = (
          fingerprint: '{"n":1}',
          status: 201,
          body: {'ok': true},
        );
        await rig.launch(tester);
        expect(find.textContaining('Ожидают подтверждения'), findsNothing);
        expect(rig.store.backing, isEmpty);
        expect(rig.server.performed, isEmpty); // recovered, not re-sent
      },
    );

    testWidgets("another user's unconfirmed operations are not shown", (
      tester,
    ) async {
      final other = PendingOperation(
        key: 'k-9',
        action: 'demo',
        userId: 'someone-else',
        businessId: 'b-1',
        path: '/x',
        body: const {},
        createdAt: DateTime.utc(2026),
      );
      final rig = RealRig(storedToken: 'refresh-1', pending: [other]);
      await rig.launch(tester);
      expect(find.textContaining('Ожидают подтверждения'), findsNothing);
      expect(rig.store.backing, hasLength(1));
    });

    testWidgets('discarding asks for confirmation first', (tester) async {
      final rig = RealRig(storedToken: 'refresh-1', pending: [op()]);
      await rig.launch(tester);
      await tapKey(tester, 'pending-review');
      await settle(tester, ms: 300);
      await tapKey(tester, 'pending-discard-k-1');
      await settle(tester, ms: 300);
      expect(
        find.textContaining('Удалить запись об этом действии?'),
        findsOneWidget,
      );
      await tester.tap(find.text('Отмена').last);
      await settle(tester, ms: 300);
      expect(rig.store.backing, hasLength(1));
      await tapKey(tester, 'pending-discard-k-1');
      await settle(tester, ms: 300);
      await tester.tap(find.text('Подтвердить').last);
      await settle(tester, ms: 300);
      expect(rig.store.backing, isEmpty);
    });
  });

  group('administration', () {
    Future<void> openAdmin(WidgetTester tester, RealRig rig) async {
      await rig.launchSignedIn(tester);
      await tapKey(tester, 'nav-administration');
      await settle(tester);
    }

    testWidgets(
      'an owner sees business, locations and staff with edit controls',
      (tester) async {
        final rig = RealRig();
        await openAdmin(tester, rig);
        expect(find.text('Профиль бизнеса'), findsOneWidget);
        expect(find.text('Валюта: TMT'), findsOneWidget);
        expect(key('location-Esasy dükan'), findsOneWidget);
        expect(key('staff-aman'), findsOneWidget);
        expect(key('add-location'), findsOneWidget);
        expect(key('add-staff'), findsOneWidget);
        expect(key('business-save'), findsOneWidget);
      },
    );

    testWidgets('a manager can look but not change settings or staff', (
      tester,
    ) async {
      final rig = RealRig();
      rig.server.role = 'manager';
      rig.server.permissions = ['business.view', 'location.view', 'staff.view'];
      await openAdmin(tester, rig);
      expect(key('staff-aman'), findsOneWidget);
      expect(key('add-staff'), findsNothing);
      expect(key('add-location'), findsNothing);
      expect(key('business-save'), findsNothing);
    });

    testWidgets('a sales user sees only their own settings', (tester) async {
      final rig = RealRig();
      rig.server.role = 'sales';
      rig.server.permissions = ['location.view'];
      await openAdmin(tester, rig);
      expect(find.text('Профиль бизнеса'), findsNothing);
      expect(key('signed-in-as'), findsOneWidget);
      expect(find.text('Сотрудники'), findsNothing);
    });

    testWidgets('adding a location, including a duplicate-name refusal', (
      tester,
    ) async {
      final rig = RealRig();
      await openAdmin(tester, rig);
      await tapKey(tester, 'add-location');
      await settle(tester, ms: 300);
      await tester.enterText(key('location-name'), 'ammar');
      await tapKey(tester, 'location-save');
      await settle(tester, ms: 300);
      expect(find.text('Такое название уже есть.'), findsOneWidget);
      await tester.enterText(key('location-name'), 'Täze şahamça');
      await tapKey(tester, 'location-save');
      await settle(tester);
      expect(key('location-Täze şahamça'), findsOneWidget);
      expect(rig.server.locationsData.last['name'], 'Täze şahamça');
    });

    testWidgets(
      'creating staff: field errors are shown, then the person is added',
      (tester) async {
        final rig = RealRig();
        await openAdmin(tester, rig);
        await tapKey(tester, 'add-staff');
        await settle(tester, ms: 400);
        await tester.enterText(key('staff-username'), 'taken');
        await tester.enterText(key('staff-email'), 'new@example.test');
        await tapKey(tester, 'staff-save');
        await settle(tester, ms: 300);
        expect(find.text('Этот логин уже занят.'), findsOneWidget);

        await tester.enterText(key('staff-username'), 'newbie');
        await tester.enterText(key('staff-password'), 'short');
        await tapKey(tester, 'staff-save');
        await settle(tester, ms: 300);
        expect(find.textContaining('Пароль слишком короткий'), findsOneWidget);

        await tester.enterText(key('staff-password'), '');
        await tapKey(tester, 'staff-save');
        await settle(tester);
        expect(key('staff-newbie'), findsOneWidget);
        final created = rig.server.staffData.last;
        expect(created['role'], 'sales');
        expect(created['user']['email'], 'new@example.test');
      },
    );

    testWidgets('a recovery code can be sent to a staff member', (
      tester,
    ) async {
      final rig = RealRig();
      await openAdmin(tester, rig);
      await tapKey(tester, 'edit-staff-sata');
      await settle(tester, ms: 400);
      await tapKey(tester, 'staff-send-code');
      await settle(tester, ms: 300);
      expect(key('staff-code-sent'), findsOneWidget);
      expect(rig.server.codesSent, ['m-2']);
    });

    testWidgets(
      "the last owner cannot be deactivated: the server's refusal is explained",
      (tester) async {
        final rig = RealRig();
        await openAdmin(tester, rig);
        await tapKey(tester, 'edit-staff-aman');
        await settle(tester, ms: 400);
        await tapKey(tester, 'staff-active');
        await settle(tester, ms: 200);
        await tapKey(tester, 'staff-save');
        await settle(tester, ms: 300);
        expect(
          find.text('В бизнесе должен остаться хотя бы один владелец.'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'changing language is saved on the server and on the device, and switches the whole UI',
      (tester) async {
        final rig = RealRig();
        await openAdmin(tester, rig);
        await tapKey(tester, 'language-chip-tk');
        await settle(tester);
        expect((rig.server.me['user'] as Map)['preferred_language'], 'tk');
        expect(rig.prefs.getString('language'), 'tk');
        expect(find.text('Işgärler'), findsOneWidget);
        expect(find.text('Профиль бизнеса'), findsNothing);
      },
    );

    testWidgets('saving the business profile', (tester) async {
      final rig = RealRig();
      await openAdmin(tester, rig);
      await tester.enterText(key('business-name'), 'Ýüpek Ätiýaçlyk Bölekler');
      await tapKey(tester, 'business-save');
      await settle(tester);
      expect(key('business-saved'), findsOneWidget);
      expect(rig.server.businessData['name'], 'Ýüpek Ätiýaçlyk Bölekler');
    });
  });

  group('unsaved work guard', () {
    testWidgets('switching location asks first when something is unsaved', (
      tester,
    ) async {
      final server = FakeServer();
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final monitor = ConnectionMonitor();
      final api = ApiClient(
        baseUrl: 'https://api.example.test',
        tokens: MemoryTokenStore(),
        httpClient: server.client,
        monitor: monitor,
      );
      final session = SessionController(api: api, preferences: prefs);
      await session.signIn('aman', 'right-password');
      final runner = OperationRunner(
        api: api,
        store: MemoryPendingOperationStore(),
        userId: 'u-1',
      );
      final unsaved = UnsavedWork();
      final owner = Object();
      await tester.binding.setSurfaceSize(const Size(1440, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ru'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            TurkmenMaterialDelegate(),
            TurkmenCupertinoDelegate(),
            TurkmenWidgetsDelegate(),
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: RealWorkspace(
            session: session,
            api: api,
            runner: runner,
            monitor: monitor,
            unsaved: unsaved,
            languageCode: 'ru',
            onLanguageChanged: (_) {},
          ),
        ),
      );
      await settle(tester, ms: 300);

      unsaved.mark(owner, dirty: true);
      await tapKey(tester, 'location-selector');
      await settle(tester, ms: 300);
      await tester.tap(find.text('Ammar').last);
      await settle(tester, ms: 300);
      expect(
        find.textContaining('Несохранённые данные будут потеряны'),
        findsOneWidget,
      );
      await tester.tap(find.text('Отмена').last);
      await settle(tester, ms: 300);
      expect(session.location!.name, 'Esasy dükan'); // not switched

      await tapKey(tester, 'location-selector');
      await settle(tester, ms: 300);
      await tester.tap(find.text('Ammar').last);
      await settle(tester, ms: 300);
      await tester.tap(find.text('Подтвердить').last);
      await settle(tester, ms: 300);
      expect(session.location!.name, 'Ammar');

      unsaved.mark(owner, dirty: false);
      expect(unsaved.isDirty, isFalse);
    });
  });

  group('layouts', () {
    for (final size in [const Size(360, 800), const Size(800, 1100)]) {
      testWidgets('sign-in and administration work at $size with doubled text', (
        tester,
      ) async {
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final rig = RealRig();
        await rig.launch(tester, size: size);
        expect(tester.takeException(), isNull);
        await rig.signIn(tester);
        expect(tester.takeException(), isNull);
        expect(key('welcome'), findsOneWidget);
        // compact layouts reach every page through the menu button
        if (size.width < 600) {
          await tester.tap(find.byTooltip('Меню'));
          await settle(tester, ms: 400);
          // the drawer is a scrolling list; at doubled text the last page is below the fold
          await tester.scrollUntilVisible(
            key('nav-administration'),
            200,
            scrollable: find.descendant(
              of: find.byType(Drawer),
              matching: find.byType(Scrollable),
            ),
          );
        }
        await tapKey(tester, 'nav-administration');
        await settle(tester);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
