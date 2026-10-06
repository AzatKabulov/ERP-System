import 'package:erp_system/core/config/app_config.dart';
import 'package:erp_system/core/operations/pending_operation.dart';
import 'package:erp_system/core/operations/pending_operation_store.dart';
import 'package:erp_system/core/session/token_stores.dart';
import 'package:erp_system/features/scanning/barcode_scanner.dart';
import 'package:erp_system/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/fake_server.dart';

const demoBanner =
    'Демонстрационные данные · изменения действуют только в этой сессии';

Future<void> settle(WidgetTester tester, {int ms = 800}) async {
  for (var i = 0; i < ms ~/ 50; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

class RealRig {
  RealRig({String? storedToken, List<PendingOperation>? pending, this.scanner})
    : tokens = MemoryTokenStore(storedToken),
      store = MemoryPendingOperationStore(pending);

  /// Replaces the camera (null keeps the real camera scanner).
  final BarcodeScanner? scanner;

  final FakeServer server = FakeServer();
  final MemoryTokenStore tokens;
  final MemoryPendingOperationStore store;
  late SharedPreferences prefs;

  Future<void> launch(
    WidgetTester tester, {
    Size size = const Size(1440, 1000),
    Map<String, Object> prefsValues = const {},
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues(prefsValues);
    prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ErpApp(
        preferences: prefs,
        config: const AppConfig(apiBaseUrl: 'https://api.example.test'),
        httpClient: server.client,
        tokenStore: tokens,
        pendingStore: store,
        scanner: scanner ?? const CameraBarcodeScanner(),
      ),
    );
    await settle(tester);
  }

  Future<void> signIn(
    WidgetTester tester, {
    String username = 'aman',
    String password = 'right-password',
  }) async {
    await tester.enterText(
      find.byKey(const ValueKey('sign-in-username')),
      username,
    );
    await tester.enterText(
      find.byKey(const ValueKey('sign-in-password')),
      password,
    );
    await tapKey(tester, 'sign-in-submit');
    await settle(tester);
  }

  /// Signed in and looking at the workspace.
  Future<void> launchSignedIn(WidgetTester tester) async {
    await launch(tester);
    await signIn(tester);
  }
}

Finder key(String name) => find.byKey(ValueKey(name));

/// Scrolls the control into view first, as a person would, then taps it.
Future<void> tapKey(WidgetTester tester, String name) async {
  final finder = find.byKey(ValueKey(name));
  await tester.ensureVisible(finder);
  // The scroll is animated, and a scrollable ignores taps until it has stopped;
  // frame by frame, because one long pump would skip the end of the animation.
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.tap(finder);
}
