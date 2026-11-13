import 'dart:ui' as ui;

import 'package:erp_system/core/api/api_client.dart';
import 'package:erp_system/core/config/server_settings.dart';
import 'package:erp_system/core/session/session_controller.dart';
import 'package:erp_system/core/session/token_stores.dart';
import 'package:erp_system/features/auth/sign_in_screen.dart';
import 'package:erp_system/l10n/app_localizations.dart';
import 'package:erp_system/theme/app_palette.dart';
import 'package:erp_system/theme/app_theme.dart';
import 'package:erp_system/widgets/app_shell.dart';
import 'package:erp_system/widgets/glass.dart';
import 'package:erp_system/widgets/pwa_viewport.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/fake_server.dart';
import '../support/real_rig.dart' show settle, key;

const safe = EdgeInsets.fromLTRB(0, 59, 0, 34);

Widget host(
  Widget page, {
  bool enabled = true,
  bool dark = false,
  EdgeInsets insets = safe,
}) {
  AppColors.use(dark ? AppPalette.dark : AppPalette.light);
  return MaterialApp(
    theme: fullScreenTheme(
      dark ? AppTheme.dark : AppTheme.light,
      enabled: enabled,
    ),
    locale: const Locale('ru'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    builder: (context, child) => PwaViewport(
      enabled: enabled,
      insets: insets,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const AmbientField(),
          child!,
          if (enabled)
            const Positioned(top: 0, left: 0, right: 0, child: PwaStatusVeil()),
        ],
      ),
    ),
    home: page,
  );
}

void main() {
  tearDown(() => AppColors.use(AppPalette.light));

  test(
    'merge reserves controls without resizing or adding native insets twice',
    () {
      const data = MediaQueryData(
        size: Size(390, 844),
        devicePixelRatio: 3,
        padding: safe,
        viewPadding: safe,
      );
      final merged = withBrowserSafeAreas(data, safe);
      expect(merged.padding, safe);
      expect(merged.viewPadding, safe);
      expect(merged.size, data.size);
      expect(merged.devicePixelRatio, 3);
      final keyboard = withBrowserSafeAreas(
        data.copyWith(viewInsets: const EdgeInsets.only(bottom: 320)),
        safe,
      );
      expect(keyboard.padding.bottom, 0);
      expect(keyboard.viewPadding.bottom, 34);
      expect(keyboard.viewInsets.bottom, 320);
      final landscape = withBrowserSafeAreas(
        const MediaQueryData(size: Size(844, 390)),
        const EdgeInsets.fromLTRB(59, 0, 59, 21),
      );
      expect(landscape.padding, const EdgeInsets.fromLTRB(59, 0, 59, 21));
    },
  );

  testWidgets('disabled path keeps normal MediaQuery and app-bar theme', (
    tester,
  ) async {
    MediaQueryData? actual;
    await tester.pumpWidget(
      host(
        Builder(
          builder: (context) {
            actual = MediaQuery.of(context);
            expect(PwaAreas.enabledOf(context), isFalse);
            expect(
              Theme.of(context).appBarTheme.backgroundColor,
              AppColors.canvas,
            );
            return const SizedBox();
          },
        ),
        enabled: false,
      ),
    );
    expect(actual!.padding, EdgeInsets.zero);
    expect(find.byKey(const ValueKey('pwa-status-veil')), findsNothing);
  });

  for (final dark in [false, true]) {
    testWidgets(
      'top glass and ambient reach y=0, controls stay safe; dark=$dark',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(390, 844));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        var topTaps = 0;
        var bottomTaps = 0;
        await tester.pumpWidget(
          host(
            AppShell(
              pages: storePages,
              page: AppPage.dashboard,
              onNavigate: (_) => bottomTaps++,
              languageCode: 'ru',
              onLanguageChanged: (_) {},
              locationControl: const Text('Shop'),
              onHelp: () => topTaps++,
              body: Builder(
                builder: (context) => ListView(
                  padding: pagePadding(context, compact: true),
                  children: const [Text('Page'), SizedBox(height: 1600)],
                ),
              ),
            ),
            dark: dark,
          ),
        );
        await settle(tester);
        expect(tester.getTopLeft(key('ambient-field-paint')).dy, 0);
        expect(
          tester.getSize(key('ambient-field-paint')),
          const Size(390, 844),
        );
        final bar = tester.getRect(key('app-top-layer'));
        expect(bar.top, 0);
        expect(bar.height, 59);
        expect(key('help-button'), findsNothing);
        await tester.tap(key('tab-more'));
        await settle(tester);
        await tester.tap(key('more-help'));
        await settle(tester);
        expect(topTaps, 1);
        final bottomControl = tester.getRect(key('tab-products'));
        expect(bottomControl.bottom, lessThanOrEqualTo(844 - 34 + 4));
        await tester.tapAt(bottomControl.center);
        expect(bottomTaps, 1);
        expect(
          find.byKey(const ValueKey('pwa-status-veil')),
          dark ? findsNothing : findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('sign-in gradient starts at zero while brand controls inset', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final fake = FakeServer();
    final api = ApiClient(
      baseUrl: 'https://api.example.test',
      tokens: MemoryTokenStore(),
      httpClient: fake.client,
    );
    final session = SessionController(api: api, preferences: prefs);
    final server = ServerSettings(
      preferences: prefs,
      api: api,
      httpClient: fake.client,
      defaultUrl: 'https://api.example.test',
    );
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      host(
        SignInScreen(
          session: session,
          server: server,
          languageCode: 'ru',
          onLanguageChanged: (_) {},
        ),
      ),
    );
    await settle(tester);
    expect(tester.getTopLeft(key('sign-in-brand-panel')).dy, 0);
    expect(
      tester.getTopLeft(find.text('ERP System').first).dy,
      greaterThanOrEqualTo(59 + 24),
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    session.dispose();
    server.dispose();
    api.close();
  });

  testWidgets(
    'pushed pages, dialogs and sheets share the inset without shifting the canvas',
    (tester) async {
      BuildContext? root;
      final navKey = GlobalKey<NavigatorState>();
      BuildContext? pushed;
      // The application builder keeps the scope above Navigator, not only above home.
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navKey,
          theme: fullScreenTheme(AppTheme.light, enabled: true),
          builder: (context, child) => PwaViewport(
            enabled: true,
            insets: safe,
            child: Stack(
              fit: StackFit.expand,
              children: [const AmbientField(), child!],
            ),
          ),
          home: Builder(
            builder: (context) {
              root = context;
              return const Scaffold();
            },
          ),
        ),
      );
      expect(MediaQuery.paddingOf(root!).top, 59);
      navKey.currentState!.push(
        MaterialPageRoute<void>(
          builder: (context) {
            pushed = context;
            return Scaffold(appBar: AppBar(title: const Text('Pushed')));
          },
        ),
      );
      await settle(tester);
      expect(tester.getTopLeft(find.byType(AppBar)).dy, 0);
      final page = pushed!;
      expect(MediaQuery.paddingOf(page).top, 59);
      expect(Theme.of(page).appBarTheme.backgroundColor, Colors.transparent);
      showDialog<void>(
        context: page,
        builder: (dialog) {
          expect(PwaAreas.enabledOf(dialog), isTrue);
          expect(
            MediaQuery.paddingOf(dialog).top,
            0,
            reason: 'DialogRoute already applied SafeArea',
          );
          return const AlertDialog(content: Text('Dialog'));
        },
      );
      await settle(tester);
      expect(tester.getTopLeft(key('ambient-field-paint')).dy, 0);
      expect(
        tester.getRect(find.byType(AlertDialog)).top,
        greaterThanOrEqualTo(59),
      );
      navKey.currentState!.pop();
      await settle(tester);
      showModalBottomSheet<void>(
        context: page,
        useSafeArea: true,
        builder: (sheet) {
          return SafeArea(
            child: SizedBox(
              key: const ValueKey('sheet-content'),
              height: 100,
              child: Text('${MediaQuery.viewPaddingOf(sheet).bottom}'),
            ),
          );
        },
      );
      await settle(tester);
      expect(
        tester.getRect(key('sheet-content')).bottom,
        lessThanOrEqualTo(tester.view.physicalSize.height - 34),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('readability veil composites changing scene and ignores taps', (
    tester,
  ) async {
    final capture = GlobalKey();
    var taps = 0;
    Widget scene(Color color) => MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(
          size: Size(800, 600),
          padding: safe,
          viewPadding: safe,
        ),
        child: PwaViewport(
          enabled: true,
          insets: safe,
          child: RepaintBoundary(
            key: capture,
            child: Stack(
              fit: StackFit.expand,
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => taps++,
                  child: ColoredBox(color: color),
                ),
                const Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: PwaStatusVeil(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    Future<List<int>> pixel() async {
      final boundary =
          capture.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage();
      final bytes = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      final offset = (20 * image.width + 80) * 4;
      final color = List<int>.generate(4, (i) => bytes.getUint8(offset + i));
      image.dispose();
      return color;
    }

    await tester.pumpWidget(scene(Colors.red));
    await tester.pump();
    final first = await tester.runAsync(pixel);
    await tester.pumpWidget(scene(Colors.blue));
    await tester.pump();
    final second = await tester.runAsync(pixel);
    expect(
      first,
      isNot(second),
      reason: 'the clock area must show the scene, not a fixed color',
    );
    await tester.tapAt(const Offset(80, 20));
    expect(taps, 1);
  });
}
