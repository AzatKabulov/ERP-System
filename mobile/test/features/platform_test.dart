import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../core/fake_server.dart';
import '../support/real_rig.dart';

/// The platform owner signs in on the ordinary screen (plus the code from their authenticator
/// app) and lands on their own pages: the overview, every client, the support desk, notices.
void makeOperator(FakeServer server) {
  server.operatorCode = '123456';
  (server.me['user'] as Map)['is_platform_operator'] = true;
  (server.me['user'] as Map)['full_name'] = 'Boss';
  server.me['memberships'] = [];
}

Future<void> signInAsOperator(WidgetTester tester, RealRig rig) async {
  await rig.launch(tester);
  await rig.signIn(tester);
  await tester.enterText(key('sign-in-code'), '123456');
  await tapKey(tester, 'sign-in-submit');
  await settle(tester);
}

Future<void> openClient(WidgetTester tester, String id) async {
  await tapKey(tester, 'nav-platformClients');
  await settle(tester);
  await tapKey(tester, 'client-$id');
  await settle(tester);
}

void main() {
  group('signing in', () {
    testWidgets('the password comes first, then the code', (tester) async {
      final rig = RealRig();
      makeOperator(rig.server);
      await rig.launch(tester);
      expect(key('sign-in-code'), findsNothing);

      await rig.signIn(tester);
      // the password was right: only now is the code asked for, and nothing is shown as an error
      expect(key('sign-in-code'), findsOneWidget);
      expect(key('sign-in-error'), findsNothing);
      expect(key('pf-total'), findsNothing);

      await tester.enterText(key('sign-in-code'), '000000');
      await tapKey(tester, 'sign-in-submit');
      await settle(tester);
      expect(key('sign-in-error'), findsOneWidget);
      expect(key('pf-total'), findsNothing);

      await tester.enterText(key('sign-in-code'), '123456');
      await tapKey(tester, 'sign-in-submit');
      await settle(tester);
      expect(key('pf-total'), findsOneWidget);
    });

    testWidgets('a wrong password never asks for the code', (tester) async {
      final rig = RealRig();
      makeOperator(rig.server);
      await rig.launch(tester);
      await rig.signIn(tester, password: 'wrong');
      expect(key('sign-in-code'), findsNothing);
      expect(key('sign-in-error'), findsOneWidget);
    });

    testWidgets(
      'a shop sees none of the owner pages and is never asked for a code',
      (tester) async {
        final rig = RealRig();
        await rig.launchSignedIn(tester);
        expect(key('nav-products'), findsOneWidget);
        for (final page in ['Overview', 'Clients', 'Support', 'Notices']) {
          expect(key('nav-platform$page'), findsNothing);
        }
        expect(key('sign-in-code'), findsNothing);
      },
    );

    testWidgets('the owner lands on the platform pages, with no shop open', (
      tester,
    ) async {
      final rig = RealRig();
      makeOperator(rig.server);
      await signInAsOperator(tester, rig);
      for (final page in ['Overview', 'Clients', 'Support', 'Notices']) {
        expect(key('nav-platform$page'), findsOneWidget);
      }
      expect(key('nav-administration'), findsOneWidget);
      expect(key('nav-products'), findsNothing);
      expect(key('nav-sales'), findsNothing);
      expect(find.text('Владелец платформы'), findsWidgets);
    });
  });

  group('the overview and the client list', () {
    testWidgets('counts, attention list and payments', (tester) async {
      final rig = RealRig();
      makeOperator(rig.server);
      await signInAsOperator(tester, rig);
      expect(find.text('3'), findsWidgets); // total clients
      expect(key('pf-count-grace'), findsOneWidget);
      expect(find.text('Late Shop'), findsOneWidget);
      expect(find.text('Soon Shop'), findsOneWidget);
      expect(find.text('Willy Wonka'), findsOneWidget); // in the payments
      expect(find.textContaining('150.00'), findsWidgets);
    });

    testWidgets('a count opens the list with that state chosen', (
      tester,
    ) async {
      final rig = RealRig();
      makeOperator(rig.server);
      await signInAsOperator(tester, rig);
      await tapKey(tester, 'pf-count-grace');
      await settle(tester);
      expect(find.text('Late Shop'), findsOneWidget);
      expect(find.text('Willy Wonka'), findsNothing);
      await tapKey(tester, 'pf-filter-all');
      await settle(tester);
      expect(find.text('Willy Wonka'), findsOneWidget);
      expect(find.text('Late Shop'), findsOneWidget);
    });

    testWidgets('search narrows the list', (tester) async {
      final rig = RealRig();
      makeOperator(rig.server);
      await signInAsOperator(tester, rig);
      await tapKey(tester, 'nav-platformClients');
      await settle(tester);
      await tester.enterText(key('pf-search'), 'soon');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await settle(tester);
      expect(find.text('Soon Shop'), findsOneWidget);
      expect(find.text('Late Shop'), findsNothing);
    });
  });

  group('a client and its buttons', () {
    testWidgets('adding a package is reviewed, then done', (tester) async {
      final rig = RealRig();
      makeOperator(rig.server);
      await signInAsOperator(tester, rig);
      await openClient(tester, 'c-1');
      expect(find.text('Willy Wonka'), findsWidgets);

      await tapKey(tester, 'pf-act-renew');
      await settle(tester);
      await tapKey(tester, 'pf-action-review');
      await settle(tester);
      // the sentence says what will happen, and nothing has changed yet
      expect(
        find.textContaining('Добавить пакет «Месяц» магазину «Willy Wonka»'),
        findsOneWidget,
      );
      expect(find.textContaining('150.00 TMT'), findsWidgets);
      expect(
        rig.server.platform.calls.where((c) => c.contains('actions/renew')),
        hasLength(1),
      );

      await tapKey(tester, 'pf-action-confirm');
      await settle(tester);
      expect(key('pf-action-confirm'), findsNothing); // the dialog closed
      expect(
        rig.server.platform.calls.where((c) => c.contains('actions/renew')),
        hasLength(2),
      );
      // the history on the page shows the payment
      expect(find.textContaining('150.00 TMT'), findsWidgets);
    });

    testWidgets('custom days need a reason, and the form says so', (
      tester,
    ) async {
      final rig = RealRig();
      makeOperator(rig.server);
      await signInAsOperator(tester, rig);
      await openClient(tester, 'c-1');
      await tapKey(tester, 'pf-act-extend');
      await settle(tester);
      await tester.enterText(key('pf-field-days'), '5');
      await tapKey(tester, 'pf-action-review');
      await settle(tester);
      expect(find.text('Обязательное поле.'), findsOneWidget);
      expect(key('pf-action-confirm'), findsNothing);
    });

    testWidgets('suspending needs a reason and shows in the status', (
      tester,
    ) async {
      final rig = RealRig();
      makeOperator(rig.server);
      await signInAsOperator(tester, rig);
      await openClient(tester, 'c-1');
      await tapKey(tester, 'pf-act-suspend');
      await settle(tester);
      await tester.enterText(key('pf-field-note'), 'no payment');
      await tapKey(tester, 'pf-action-review');
      await settle(tester);
      expect(find.textContaining('будет отключён сразу'), findsOneWidget);
      await tapKey(tester, 'pf-action-confirm');
      await settle(tester);
      expect(find.text('Приостановлен'), findsWidgets);
      // the button to undo it replaces the button that did it
      expect(key('pf-act-resume'), findsOneWidget);
      expect(key('pf-act-suspend'), findsNothing);
    });

    testWidgets('a reset password is shown once, with a way to copy it', (
      tester,
    ) async {
      final rig = RealRig();
      makeOperator(rig.server);
      await signInAsOperator(tester, rig);
      await openClient(tester, 'c-1');
      await tapKey(tester, 'pf-act-reset-password');
      await settle(tester);
      expect(find.textContaining('новый временный пароль'), findsOneWidget);
      await tapKey(tester, 'pf-action-confirm');
      await settle(tester);
      expect(find.text('Reset-Pass-5678'), findsOneWidget);
      await tapKey(tester, 'pf-action-done');
      await settle(tester);
      expect(find.text('Reset-Pass-5678'), findsNothing);
    });

    testWidgets('a note is added to the diary', (tester) async {
      final rig = RealRig();
      makeOperator(rig.server);
      await signInAsOperator(tester, rig);
      await openClient(tester, 'c-1');
      await tester.enterText(key('pf-note-field'), 'called, pays Friday');
      await tapKey(tester, 'pf-note-add');
      await settle(tester);
      expect(find.text('called, pays Friday'), findsOneWidget);
    });
  });

  group('new client', () {
    testWidgets(
      'the login and temporary password are shown, then the client opens',
      (tester) async {
        final rig = RealRig();
        makeOperator(rig.server);
        await signInAsOperator(tester, rig);
        await tapKey(tester, 'nav-platformClients');
        await settle(tester);
        await tapKey(tester, 'pf-new-client');
        await settle(tester);

        // the store's name is required
        await tapKey(tester, 'pf-new-create');
        await settle(tester);
        expect(find.text('Обязательное поле.'), findsOneWidget);

        await tester.enterText(key('pf-new-store_name'), 'Brand New Shop');
        await tapKey(tester, 'pf-new-create');
        await settle(tester);
        expect(find.text('new-shop'), findsOneWidget);
        expect(find.text('Temp-Pass-1234'), findsOneWidget);

        await tapKey(tester, 'pf-new-open');
        await settle(tester);
        expect(find.text('Brand New Shop'), findsWidgets);
      },
    );
  });

  group('support and notices', () {
    testWidgets('a question is answered', (tester) async {
      final rig = RealRig();
      makeOperator(rig.server);
      await signInAsOperator(tester, rig);
      await tapKey(tester, 'nav-platformSupport');
      await settle(tester);
      expect(find.text('Принтер не печатает'), findsOneWidget);
      await tapKey(tester, 'ticket-t-1');
      await settle(tester);
      expect(find.text('Чек не выходит'), findsOneWidget);
      await tester.enterText(key('pf-reply-field'), 'Попробуйте другой кабель');
      await tapKey(tester, 'pf-reply-send');
      await settle(tester);
      expect(find.text('Попробуйте другой кабель'), findsOneWidget);
      expect(find.text('Отвечено'), findsOneWidget);
    });

    testWidgets('a notice for every shop is written and listed', (
      tester,
    ) async {
      final rig = RealRig();
      makeOperator(rig.server);
      await signInAsOperator(tester, rig);
      await tapKey(tester, 'nav-platformNotices');
      await settle(tester);
      expect(key('pf-no-notices'), findsOneWidget);
      await tapKey(tester, 'pf-new-notice');
      await settle(tester);
      await tester.enterText(key('pf-notice-ru'), 'Сегодня ночью работы');
      await tapKey(tester, 'pf-notice-save');
      await settle(tester);
      expect(find.text('Сегодня ночью работы'), findsOneWidget);
    });
  });

  group('settings', () {
    testWidgets('the owner can sign out from the settings page', (
      tester,
    ) async {
      final rig = RealRig();
      makeOperator(rig.server);
      await signInAsOperator(tester, rig);
      await tapKey(tester, 'nav-administration');
      await settle(tester);
      expect(key('signed-in-as'), findsOneWidget);
      expect(find.text('Месяц · 1 мес.'), findsOneWidget);
      await tapKey(tester, 'admin-sign-out');
      await settle(tester);
      expect(key('sign-in-submit'), findsOneWidget);
    });
  });

  group('on a phone', () {
    testWidgets('the bottom bar reaches every owner page without overflow', (
      tester,
    ) async {
      final rig = RealRig();
      makeOperator(rig.server);
      await rig.launch(tester, size: const Size(393, 800));
      await rig.signIn(tester);
      await tester.enterText(key('sign-in-code'), '123456');
      await tapKey(tester, 'sign-in-submit');
      await settle(tester);
      expect(key('pf-total'), findsOneWidget);
      for (final page in ['Clients', 'Support', 'Notices', 'Overview']) {
        await tapKey(tester, 'nav-platform$page');
        await settle(tester);
        expect(tester.takeException(), isNull, reason: page);
      }
      await tapKey(tester, 'nav-administration');
      await settle(tester);
      expect(tester.takeException(), isNull);
      expect(key('signed-in-as'), findsOneWidget);
    });
  });
}
