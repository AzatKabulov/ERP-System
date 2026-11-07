import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'core/api/api_client.dart';
import 'core/config/app_config.dart';
import 'core/config/server_settings.dart';
import 'core/files/file_services.dart';
import 'core/connectivity/connection_monitor.dart';
import 'core/operations/pending_operation_store.dart';
import 'core/session/session_controller.dart';
import 'core/session/token_stores.dart';
import 'core/web/web_chrome.dart';
import 'demo/demo_store.dart';
import 'features/sales/document_actions.dart';
import 'features/scanning/barcode_scanner.dart';
import 'features/workspace/real_home.dart';
import 'l10n/app_localizations.dart';
import 'l10n/turkmen_localizations.dart';
import 'screens/workspace.dart';
import 'theme/app_theme.dart';
import 'theme/theme_controller.dart';
import 'widgets/glass.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Android only (a no-op on web and unreachable on iOS, which has no native status bar to
  // style here): the app has no AppBar to derive this from, no dark theme, and is always drawn
  // edge-to-edge, so without this the system bars default to undefined, possibly unreadable icon
  // colours on top of the app's light canvas.
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  LicenseRegistry.addLicense(() async* {
    for (final font in ['Onest']) {
      final text = await rootBundle.loadString(
        'assets/fonts/$font-LICENSE.txt',
      );
      yield LicenseEntryWithLineBreaks([font], text);
    }
  });
  final preferences = await SharedPreferences.getInstance();
  runApp(ErpApp(preferences: preferences));
}

/// The application. A real build starts at sign-in and talks to the server; a
/// demonstration build (`DEMO_MODE`, or an explicit [store]) runs on in-memory
/// sample data with a visible banner. The two never mix.
class ErpApp extends StatefulWidget {
  const ErpApp({
    super.key,
    required this.preferences,
    this.store,
    this.config = AppConfig.fromEnvironment,
    this.httpClient,
    this.tokenStore,
    this.pendingStore,
    this.scanner = const CameraBarcodeScanner(),
    this.documents = const DevicePrintingDocumentActions(),
    this.picking = const DeviceFilePicking(),
    this.sharing = const DeviceFileSharing(),
  });

  final SharedPreferences preferences;

  /// Supplying a demonstration store selects demonstration mode.
  final DemoStore? store;
  final AppConfig config;

  /// Injectable for tests.
  final http.Client? httpClient;
  final TokenStore? tokenStore;
  final PendingOperationStore? pendingStore;

  /// How barcodes are read (the camera in the app, a fake in tests).
  final BarcodeScanner scanner;

  /// How receipts and invoices are printed or shared (the device dialogs; a fake in tests).
  final DocumentActions documents;

  /// How photos and files are chosen and sent on (the device dialogs; fakes in tests).
  final FilePicking picking;
  final FileSharing sharing;

  @override
  State<ErpApp> createState() => _ErpAppState();
}

class _ErpAppState extends State<ErpApp> with WidgetsBindingObserver {
  late final ThemeController _theme = ThemeController(widget.preferences);
  late final bool _demo = widget.store != null || widget.config.demoMode;
  late final DemoStore? _store = _demo ? (widget.store ?? DemoStore()) : null;
  late final ConnectionMonitor _monitor = ConnectionMonitor();
  late final http.Client _httpClient = widget.httpClient ?? http.Client();

  /// The server this build is made for. A web page can only ever talk to the server that
  /// served it, so there that address is used and cannot be changed.
  late final String _defaultServer = widget.config.apiBaseUrl.isNotEmpty
      ? widget.config.apiBaseUrl
      : (kIsWeb ? Uri.base.origin : '');

  /// A phone or tablet remembers the address its user chose on the sign-in screen.
  late final String _startServer = kIsWeb
      ? _defaultServer
      : ((widget.preferences.getString('server_url') ?? '').isNotEmpty
            ? widget.preferences.getString('server_url')!
            : _defaultServer);

  late final ApiClient _api = ApiClient(
    baseUrl: _startServer.isEmpty ? 'http://invalid.local' : _startServer,
    tokens: widget.tokenStore ?? createTokenStore(),
    httpClient: _httpClient,
    monitor: _monitor,
    onSessionExpired: () => _session.handleSessionExpired(),
    onSubscriptionBlocked: () => _session.handleSubscriptionBlocked(),
  );
  late final ServerSettings _server = ServerSettings(
    preferences: widget.preferences,
    api: _api,
    httpClient: _httpClient,
    defaultUrl: _defaultServer,
    fixed: kIsWeb,
  );
  late final SessionController _session = SessionController(
    api: _api,
    preferences: widget.preferences,
  );
  late Locale _locale = Locale(
    widget.preferences.getString('language') == 'tk' ? 'tk' : 'ru',
  );

  void _applyLanguage(String code) {
    if (code != 'ru' && code != 'tk') return;
    setState(() => _locale = Locale(code));
    widget.preferences.setString('language', code);
  }

  /// The user's own choice: remembered on this device and, when signed in, saved
  /// on the server so it follows them to another device.
  void _changeLanguage(String code) {
    _applyLanguage(code);
    if (!_demo && _session.status == SessionStatus.signedIn) {
      _session.saveLanguage(code);
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // the scheme is in force before the first frame, so there is no flash of the wrong one
    ThemeController.apply(
      _theme.resolve(
        WidgetsBinding.instance.platformDispatcher.platformBrightness,
      ),
    );
    _theme.addListener(_schemeChanged);
    syncBrowserChrome(dark: AppColors.isDark);
  }

  /// The phone switched between light and dark while the app was open.
  @override
  void didChangePlatformBrightness() => _schemeChanged();

  void _schemeChanged() {
    final brightness = _theme.resolve(
      WidgetsBinding.instance.platformDispatcher.platformBrightness,
    );
    final changed = ThemeController.apply(brightness);
    syncBrowserChrome(dark: AppColors.isDark);
    setState(() {}); // the Material theme follows the chosen mode
    if (!changed) return;
    // every widget reads its colours when it builds: build them all again, in place
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => ThemeController.repaintEverything(),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _theme.removeListener(_schemeChanged);
    _theme.dispose();
    if (_demo) {
      if (widget.store == null) _store!.dispose();
    } else {
      _session.dispose();
      _server.dispose();
      _api.close();
      _monitor.dispose();
    }
    super.dispose();
  }

  /// The phone's own top and bottom areas (web only), added to what Flutter already knows.
  MediaQueryData _withPhoneAreas(MediaQueryData data) {
    if (!fullScreenMode())
      return data; // the normal app leaves the phone's areas to the browser
    final areas = safeAreaInsets();
    final padding = data.padding.copyWith(
      top: areas.top > data.padding.top ? areas.top : data.padding.top,
      bottom: areas.bottom > data.padding.bottom
          ? areas.bottom
          : data.padding.bottom,
    );
    return data.copyWith(padding: padding, viewPadding: padding);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ERP System',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: _theme.themeMode,
      locale: _locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        TurkmenMaterialDelegate(),
        TurkmenCupertinoDelegate(),
        TurkmenWidgetsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      builder: (context, child) => MediaQuery(
        // Full screen: the page reaches under the phone's clock and home bar, so tell every screen
        // how far those areas reach, and its content keeps clear of them.
        data: _withPhoneAreas(MediaQuery.of(context)),
        child: ThemeScope(
          controller: _theme,
          // the status bar's icons follow the scheme (dark icons on light, light on dark)
          child: AnnotatedRegion<SystemUiOverlayStyle>(
            value: AppColors.isDark
                ? SystemUiOverlayStyle.light.copyWith(
                    statusBarColor: Colors.transparent,
                    systemNavigationBarColor: Colors.transparent,
                  )
                : SystemUiOverlayStyle.dark.copyWith(
                    statusBarColor: Colors.transparent,
                    systemNavigationBarColor: Colors.transparent,
                  ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // the soft light behind every screen, which the frosted layers blur
                const AmbientField(),
                ScannerScope(
                  scanner: widget.scanner,
                  child: FilesScope(
                    picking: widget.picking,
                    sharing: widget.sharing,
                    child: DocumentsScope(
                      actions: widget.documents,
                      child: child!,
                    ),
                  ),
                ),
                const _TopScrim(),
              ],
            ),
          ),
        ),
      ),
      // The browser address holds the pushed pages' names; a reload starts at the first page.
      initialRoute: '/',
      home: _demo
          ? Workspace(
              store: _store!,
              languageCode: _locale.languageCode,
              onLanguageChanged: _changeLanguage,
            )
          : RealHome(
              session: _session,
              api: _api,
              monitor: _monitor,
              preferences: widget.preferences,
              languageCode: _locale.languageCode,
              onLanguageChanged: _changeLanguage,
              onServerLanguage: _applyLanguage,
              server: _server,
              pendingStore: widget.pendingStore,
            ),
    );
  }
}

/// Full-screen copy, light scheme: the page is drawn under the phone's clock, whose text is always
/// white there, so the top few millimetres fade from a soft blue-grey into the page.
class _TopScrim extends StatelessWidget {
  const _TopScrim();

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    if (!fullScreenMode() || top <= 0 || AppColors.isDark) {
      return const SizedBox.shrink();
    }
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      height: top + 14,
      child: const IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x8C3A4A86), Color(0x003A4A86)],
            ),
          ),
        ),
      ),
    );
  }
}
