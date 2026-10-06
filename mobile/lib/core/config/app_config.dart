import 'package:flutter/foundation.dart';

/// Build-time configuration (`--dart-define`). Nothing here is secret: the app
/// never holds server credentials, only the address of the API.
@immutable
class AppConfig {
  const AppConfig({required this.apiBaseUrl, this.demoMode = false});

  /// Address of the API, without a trailing slash, e.g. `https://api.example.test`.
  /// Debug builds default to a local server; release builds must set it explicitly.
  final String apiBaseUrl;

  /// Demonstration mode shows sample data from `DemoStore` and a visible banner.
  /// Normal builds never show demo data as real: they start at sign-in.
  final bool demoMode;

  bool get hasApi => apiBaseUrl.isNotEmpty;

  static const AppConfig fromEnvironment = AppConfig(
    apiBaseUrl: String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: kDebugMode ? 'http://127.0.0.1:8000' : '',
    ),
    demoMode: bool.fromEnvironment('DEMO_MODE'),
  );

  static const AppConfig demo = AppConfig(apiBaseUrl: '', demoMode: true);
}
