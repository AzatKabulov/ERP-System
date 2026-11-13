import 'package:erp_system/core/api/api_error_text.dart';
import 'package:erp_system/core/api/api_exception.dart';
import 'package:erp_system/l10n/app_localizations_ru.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/real_rig.dart';
import 'sales_test.dart' show addToCart, deskRig, openSales;

const _phone = Size(360, 800);

void setSubscription(RealRig rig, Map<String, dynamic>? subscription) {
  (rig.server.me['memberships'] as List).first['subscription'] = subscription;
}

Future<void> openSettings(WidgetTester tester, RealRig rig) async {
  await rig.launchSignedIn(tester);
  await tapKey(tester, 'nav-administration');
  await settle(tester);
}

void main() {
  group('choosing your own password', () {
    testWidgets(
      'a password somebody else chose must be replaced before anything opens',
      (tester) async {
        final rig = RealRig();
        (rig.server.me['user'] as Map)['must_change_password'] = true;
        await rig.launchSignedIn(tester);
        expect(key('choose-password-title'), findsOneWidget);
        expect(key('welcome'), findsNothing);
        // the password just typed is not asked for again
        expect(key('password-current'), findsNothing);

        await tester.enterText(key('password-new'), 'short');
        await tester.enterText(key('password-repeat'), 'short');
        await tapKey(tester, 'password-submit');
        await settle(tester, ms: 200);
        expect(find.textContaining('слишком короткий'), findsOneWidget);

        await tester.enterText(key('password-new'), 'my-own-secret-7');
        await tester.enterText(key('password-repeat'), 'my-own-secret-8');
        await tapKey(tester, 'password-submit');
        await settle(tester, ms: 200);
        expect(find.text('Пароли не совпадают'), findsOneWidget);

        await tester.enterText(key('password-repeat'), 'my-own-secret-7');
        await tapKey(tester, 'password-submit');
        await settle(tester);
        expect(key('welcome'), findsOneWidget);
        expect(rig.server.userPassword, 'my-own-secret-7');
      },
    );

    testWidgets('settings offer a password change, closed until asked for', (
      tester,
    ) async {
      final rig = RealRig();
      await openSettings(tester, rig);
      expect(key('password-current'), findsNothing);
      await tapKey(tester, 'password-toggle');
      await settle(tester, ms: 300);
      expect(key('password-current'), findsOneWidget);

      await tester.enterText(key('password-current'), 'wrong-password');
      await tester.enterText(key('password-new'), 'another-secret-9');
      await tester.enterText(key('password-repeat'), 'another-secret-9');
      await tapKey(tester, 'password-submit');
      await settle(tester, ms: 300);
      expect(find.text('Текущий пароль неверный.'), findsOneWidget);
      expect(rig.server.userPassword, 'right-password');

      await tester.enterText(key('password-current'), 'right-password');
      await tapKey(tester, 'password-submit');
      await settle(tester);
      expect(rig.server.userPassword, 'another-secret-9');
      expect(find.text('Пароль изменён'), findsOneWidget);
      expect(key('password-current'), findsNothing);
    });

    testWidgets('the sign-in password can be looked at', (tester) async {
      final rig = RealRig();
      await rig.launch(tester);
      bool hidden() => tester
          .widget<TextField>(
            find.descendant(
              of: key('sign-in-password'),
              matching: find.byType(TextField),
            ),
          )
          .obscureText;
      expect(hidden(), isTrue);
      await tester.tap(find.byTooltip('Показать пароль'));
      await tester.pump();
      expect(hidden(), isFalse);
      await tester.tap(find.byTooltip('Скрыть пароль'));
      await tester.pump();
      expect(hidden(), isTrue);
    });

    testWidgets('a returning person taps their name instead of typing it', (
      tester,
    ) async {
      final rig = RealRig();
      await openSettings(tester, rig);
      await tapKey(tester, 'admin-sign-out');
      await settle(tester);
      expect(key('recent-aman'), findsOneWidget);
      await tester.tap(key('recent-aman'));
      await tester.pump();
      expect(
        tester.widget<TextField>(key('sign-in-username')).controller!.text,
        'aman',
      );
    });
  });

  group('the subscription', () {
    const phone = {'support_phone': '+993 65 000000', 'support_note': ''};

    testWidgets('a healthy shop sees nothing', (tester) async {
      final rig = RealRig();
      setSubscription(rig, {
        'state': 'active',
        'is_trial': false,
        'ends_at': '2027-01-10T12:00:00Z',
        'days_left': 60,
      });
      await rig.launchSignedIn(tester);
      expect(key('subscription-banner'), findsNothing);
    });

    testWidgets('a week left: the owner is told the date and how to renew', (
      tester,
    ) async {
      final rig = RealRig();
      rig.server.me['platform'] = phone;
      setSubscription(rig, {
        'state': 'expiring',
        'is_trial': false,
        'ends_at': '2026-11-10T12:00:00Z',
        'days_left': 3,
      });
      await rig.launchSignedIn(tester);
      expect(
        find.text('Подписка заканчивается 10.11.2026 (дней: 3).'),
        findsOneWidget,
      );
      await tapKey(tester, 'subscription-renew');
      await settle(tester, ms: 300);
      expect(key('renew-dialog'), findsOneWidget);
      expect(find.text('Позвонить: +993 65 000000'), findsOneWidget);
      // the way to write to us is right there
      await tapKey(tester, 'renew-write-us');
      await settle(tester);
      expect(key('support-new'), findsOneWidget);
    });

    testWidgets('a free trial says so', (tester) async {
      final rig = RealRig();
      setSubscription(rig, {
        'state': 'active',
        'is_trial': true,
        'ends_at': '2026-11-20T12:00:00Z',
        'days_left': 13,
      });
      await rig.launchSignedIn(tester);
      expect(
        find.text('Пробный период до 20.11.2026 (дней: 13).'),
        findsOneWidget,
      );
      expect(key('subscription-renew'), findsNothing);
    });

    testWidgets('the grace days are a red warning, and work continues', (
      tester,
    ) async {
      final rig = RealRig();
      setSubscription(rig, {
        'state': 'grace',
        'is_trial': false,
        'ends_at': '2026-11-03T12:00:00Z',
        'grace_ends_at': '2026-11-10T12:00:00Z',
        'days_left': -3,
      });
      await rig.launchSignedIn(tester);
      expect(find.textContaining('Всё работает до 10.11.2026'), findsOneWidget);
      expect(key('welcome'), findsOneWidget);
    });

    testWidgets('read-only: the owner learns what that means', (tester) async {
      final rig = RealRig();
      setSubscription(rig, {
        'state': 'read_only',
        'is_trial': false,
        'ends_at': '2026-10-01T12:00:00Z',
        'days_left': -40,
      });
      await rig.launchSignedIn(tester);
      expect(find.textContaining('данные можно смотреть'), findsOneWidget);
      expect(key('subscription-renew'), findsOneWidget);
    });

    testWidgets('a seller is told to tell the owner, with no dates', (
      tester,
    ) async {
      final rig = RealRig();
      rig.server.role = 'sales';
      setSubscription(rig, {'state': 'read_only'});
      await rig.launchSignedIn(tester);
      expect(find.textContaining('Сообщите владельцу'), findsOneWidget);
      expect(key('subscription-renew'), findsNothing);
    });

    testWidgets('a suspended shop sees only how to reach us', (tester) async {
      final rig = RealRig();
      rig.server.me['platform'] = phone;
      setSubscription(rig, {'state': 'suspended', 'is_trial': false});
      await rig.launchSignedIn(tester);
      expect(key('suspended-title'), findsOneWidget);
      expect(find.text('Позвонить: +993 65 000000'), findsOneWidget);
      expect(key('phone-navigation'), findsNothing);
      expect(key('welcome'), findsNothing);
      await tapKey(tester, 'suspended-write-us');
      await settle(tester);
      expect(key('support-new'), findsOneWidget);
    });

    test('the refusals of a lapsed subscription are explained in words', () {
      final l = AppLocalizationsRu();
      String say(String code) => apiErrorText(
        l,
        ApiException(kind: ApiErrorKind.client, code: code, status: 402),
      );
      expect(say('subscription_expired'), contains('можно смотреть'));
      expect(say('subscription_suspended'), contains('приостановлен'));
      expect(say('password_change_required'), contains('пароль'));
    });

    testWidgets('a notice from us can be closed, and stays closed', (
      tester,
    ) async {
      final rig = RealRig();
      rig.server.me['announcements'] = [
        {'id': 'a1', 'message': 'Работы сегодня в 23:00'},
      ];
      await rig.launchSignedIn(tester);
      expect(find.text('Работы сегодня в 23:00'), findsOneWidget);
      await tapKey(tester, 'announcement-hide-a1');
      await settle(tester, ms: 200);
      expect(find.text('Работы сегодня в 23:00'), findsNothing);
      expect(rig.prefs.getStringList('announcements.closed'), ['a1']);
    });
  });

  group('writing to us', () {
    testWidgets('the owner asks a question and sees it in the list', (
      tester,
    ) async {
      final rig = RealRig();
      await openSettings(tester, rig);
      await tapKey(tester, 'settings-support');
      await settle(tester);
      expect(key('support-empty'), findsOneWidget);
      await tapKey(tester, 'support-new');
      await settle(tester, ms: 200);

      // empty fields are explained, nothing is sent
      await tapKey(tester, 'support-send');
      await settle(tester, ms: 200);
      expect(find.text('Обязательное поле.'), findsWidgets);
      expect(rig.server.supportRequests, isEmpty);

      await tester.enterText(key('support-subject'), 'Принтер');
      await tester.enterText(key('support-body'), 'Чек не печатается');
      await tapKey(tester, 'support-send');
      await settle(tester);
      expect(key('support-sent'), findsOneWidget);
      expect(find.text('Принтер'), findsOneWidget);
      expect(rig.server.supportRequests, hasLength(1));
    });

    testWidgets('our answer opens by itself and can be replied to', (
      tester,
    ) async {
      final rig = RealRig();
      const stamp = '2026-11-06T10:00:00Z';
      rig.server.supportRequests.add(<String, dynamic>{
        'id': 's-9',
        'subject': 'Принтер',
        'status': 'answered',
        'created_at': stamp,
        'updated_at': stamp,
        'messages': <Map<String, dynamic>>[
          {
            'id': 'm1',
            'from_store': true,
            'text': 'Чек не печатается',
            'created_at': stamp,
          },
          {
            'id': 'm2',
            'from_store': false,
            'text': 'Попробуйте другой кабель',
            'created_at': stamp,
          },
        ],
      });
      await openSettings(tester, rig);
      await tapKey(tester, 'settings-support');
      await settle(tester);
      expect(find.text('Есть ответ'), findsOneWidget);
      expect(find.text('Попробуйте другой кабель'), findsOneWidget);

      await tester.enterText(key('support-reply-s-9'), 'Помогло, спасибо');
      await tapKey(tester, 'support-reply-send-s-9');
      await settle(tester);
      expect(rig.server.supportRequests.first['status'], 'open');
      expect(
        (rig.server.supportRequests.first['messages'] as List),
        hasLength(3),
      );
    });

    testWidgets('a seller is told to ask the owner', (tester) async {
      final rig = RealRig();
      rig.server.permissions.remove('support.write');
      rig.server.me['platform'] = const {
        'support_phone': '+993 65 000000',
        'support_note': '',
      };
      await openSettings(tester, rig);
      await tapKey(tester, 'settings-support');
      await settle(tester);
      expect(key('support-owners-only'), findsOneWidget);
      expect(key('support-new'), findsNothing);
      expect(find.text('Телефон: +993 65 000000'), findsOneWidget);
    });

    testWidgets('the how-to pages open from Settings and from the top bar', (
      tester,
    ) async {
      final rig = RealRig();
      await openSettings(tester, rig);
      await tapKey(tester, 'settings-help');
      await settle(tester);
      await tester.tap(key('help-receive'));
      await settle(tester, ms: 300);
      expect(find.textContaining('Приёмка сканированием'), findsOneWidget);
      expect(key('help-write-us'), findsOneWidget);
      await tapKey(tester, 'help-write-us');
      await settle(tester);
      expect(key('support-new'), findsOneWidget);
    });

    testWidgets('a phone keeps help and shop context in More', (tester) async {
      final rig = RealRig();
      await rig.launch(tester, size: _phone);
      await rig.signIn(tester);
      await tester.tap(key('tab-more'));
      await settle(tester);
      await tester.tap(key('more-help'));
      await settle(tester);
      expect(key('help-sell'), findsOneWidget);
    });
  });

  group('staff without email', () {
    testWidgets('the owner gives a temporary password, shown once', (
      tester,
    ) async {
      final rig = RealRig();
      // the clipboard is a platform service: answer it, as a phone would
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async => null,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await openSettings(tester, rig);
      await tapKey(tester, 'settings-tab-team');
      await settle(tester);
      await tapKey(tester, 'edit-staff-sata');
      await settle(tester, ms: 400);
      await tapKey(tester, 'staff-temp-password');
      await settle(tester, ms: 300);
      await tester.tap(find.text('Подтвердить'));
      await settle(tester, ms: 400);
      expect(key('temp-password-dialog'), findsOneWidget);
      expect(
        tester.widget<SelectableText>(key('temp-password-value')).data,
        'Kd7mQ-4xvWp-9TnzB',
      );
      expect(rig.server.temporaryPasswordGiven, 'm-2');
      await tapKey(tester, 'temp-password-copy');
      await settle(tester, ms: 200);
      expect(find.text('Скопировано'), findsOneWidget);
    });

    testWidgets('a member without an email gets no "send a code" button', (
      tester,
    ) async {
      final rig = RealRig();
      (rig.server.staffData[1]['user'] as Map)['email'] = '';
      await openSettings(tester, rig);
      await tapKey(tester, 'settings-tab-team');
      await settle(tester);
      await tapKey(tester, 'edit-staff-sata');
      await settle(tester, ms: 400);
      expect(key('staff-send-code'), findsNothing);
      expect(key('staff-temp-password'), findsOneWidget);
    });
  });

  group('a new shop', () {
    const fresh = {
      'has_products': false,
      'has_stock': false,
      'has_sales': false,
      'has_details': false,
      'has_team': false,
    };

    testWidgets(
      'the dashboard lists what to do first, and each step leads on',
      (tester) async {
        final rig = RealRig();
        rig.server.reports.onboarding = {...fresh, 'has_products': true};
        await rig.launchSignedIn(tester);
        expect(key('onboarding-card'), findsOneWidget);
        expect(find.text('Готово 1 из 5'), findsOneWidget);
        await tapKey(tester, 'onboarding-stock');
        await settle(tester);
        expect(key('stock-empty'), findsOneWidget);
      },
    );

    testWidgets(
      'it can be hidden for good, and is gone once everything is done',
      (tester) async {
        final rig = RealRig();
        rig.server.reports.onboarding = fresh;
        await rig.launchSignedIn(tester);
        await tapKey(tester, 'onboarding-hide');
        await settle(tester, ms: 200);
        expect(key('onboarding-card'), findsNothing);
        expect(
          rig.prefs.getKeys().any((k) => k.startsWith('onboarding.hidden')),
          isTrue,
        );
      },
    );

    testWidgets('a finished shop has no list', (tester) async {
      final rig = RealRig();
      rig.server.reports.onboarding = {for (final k in fresh.keys) k: true};
      await rig.launchSignedIn(tester);
      expect(key('onboarding-card'), findsNothing);
    });

    testWidgets('with no name set the greeting does not use the login', (
      tester,
    ) async {
      final rig = RealRig();
      (rig.server.me['user'] as Map)['full_name'] = '';
      await rig.launchSignedIn(tester);
      expect(find.text('Здравствуйте!'), findsNothing);
      expect(find.text('Обзор'), findsWidgets);
    });

    testWidgets('an empty stock page offers the first steps, not filters', (
      tester,
    ) async {
      final rig = RealRig();
      await rig.launchSignedIn(tester);
      await tapKey(tester, 'nav-inventory');
      await settle(tester);
      expect(key('stock-empty'), findsOneWidget);
      expect(key('stock-empty-intake'), findsOneWidget);
      expect(key('stock-empty-opening'), findsOneWidget);
      expect(key('stock-search'), findsNothing);
      expect(key('stock-condition-all'), findsNothing);
    });
  });

  group('the cart', () {
    testWidgets('a removed line can be taken back', (tester) async {
      final t = deskRig();
      await openSales(tester, t.rig);
      await addToCart(tester);
      expect(key('cart-qty-0'), findsOneWidget);
      await tapKey(tester, 'cart-remove-0');
      await settle(tester, ms: 200);
      expect(key('cart-qty-0'), findsNothing);
      expect(find.text('Позиция удалена'), findsOneWidget);
      await tester.tap(key('cart-undo'));
      await settle(tester, ms: 200);
      expect(key('cart-qty-0'), findsOneWidget);
    });
  });
}
