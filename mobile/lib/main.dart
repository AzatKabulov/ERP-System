import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'core/api/api_client.dart';
import 'core/config/app_config.dart';
import 'core/connectivity/connection_monitor.dart';
import 'core/operations/pending_operation_store.dart';
import 'core/session/session_controller.dart';
import 'core/session/token_stores.dart';
import 'demo/demo_store.dart';
import 'features/scanning/barcode_scanner.dart';
import 'features/workspace/real_home.dart';
import 'l10n/app_localizations.dart';
import 'l10n/turkmen_localizations.dart';
import 'screens/workspace.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    for (final font in ['Inter', 'NotoSerif']) {
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

  @override
  State<ErpApp> createState() => _ErpAppState();
}

class _ErpAppState extends State<ErpApp> {
  late final bool _demo = widget.store != null || widget.config.demoMode;
  late final DemoStore? _store = _demo ? (widget.store ?? DemoStore()) : null;
  late final ConnectionMonitor _monitor = ConnectionMonitor();
  late final ApiClient _api = ApiClient(
    baseUrl: widget.config.apiBaseUrl.isEmpty
        ? 'http://invalid.local'
        : widget.config.apiBaseUrl,
    tokens: widget.tokenStore ?? SecureTokenStore(),
    httpClient: widget.httpClient,
    monitor: _monitor,
    onSessionExpired: () => _session.handleSessionExpired(),
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
  void dispose() {
    if (_demo) {
      if (widget.store == null) _store!.dispose();
    } else {
      _session.dispose();
      _api.close();
      _monitor.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ERP System',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
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
      builder: (context, child) =>
          ScannerScope(scanner: widget.scanner, child: child!),
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
              configured: widget.config.hasApi,
              pendingStore: widget.pendingStore,
            ),
    );
  }
}
