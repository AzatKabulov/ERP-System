import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_client.dart';

/// What checking an address found.
enum ServerCheck { ok, invalid, insecure, unreachable, notErp, databaseDown }

/// The address of the server this installation talks to. One app can serve many businesses on
/// many servers (each client has its own), so the address is a setting of the device, chosen on
/// the sign-in screen, not something baked into the build. A build may carry a default (`API_BASE_URL`).
class ServerSettings extends ChangeNotifier {
  ServerSettings({
    required SharedPreferences preferences,
    required ApiClient api,
    required http.Client httpClient,
    this.defaultUrl = '',
    this.allowInsecure = kDebugMode,
    this.fixed = false,
  }) : _prefs = preferences,
       _api = api,
       _http = httpClient;

  static const _key = 'server_url';

  final SharedPreferences _prefs;
  final ApiClient _api;
  final http.Client _http;

  /// The address this build was made for (may be empty).
  final String defaultUrl;

  /// Plain http is only for developing against a local server; people get https only.
  final bool allowInsecure;

  /// True where the address cannot be chosen (the web build only ever talks to its own server).
  final bool fixed;

  /// The address in use: the one chosen on this device, else the build's default.
  String get url => fixed
      ? defaultUrl
      : (_prefs.getString(_key) ?? '').isNotEmpty
      ? _prefs.getString(_key)!
      : defaultUrl;

  bool get configured => url.isNotEmpty;

  /// Writes an address the way it is stored: "https://host[:port]", no path, no slash. Null when
  /// it is not an address at all. A bare "shop.example.com" is taken to mean https.
  static String? normalize(String input) {
    var text = input.trim();
    if (text.isEmpty || text.contains(RegExp(r'\s'))) return null;
    if (!text.contains('://')) text = 'https://$text';
    final uri = Uri.tryParse(text);
    if (uri == null || !uri.hasAuthority || uri.host.isEmpty) return null;
    if (uri.scheme != 'https' && uri.scheme != 'http') return null;
    if (uri.userInfo.isNotEmpty || uri.hasQuery || uri.hasFragment) return null;
    if (uri.path.isNotEmpty && uri.path != '/') return null;
    final port = uri.hasPort ? ':${uri.port}' : '';
    return '${uri.scheme}://${uri.host.toLowerCase()}$port';
  }

  /// Asks the address for its health page: it must be this system, with its database up.
  Future<ServerCheck> check(String input) async {
    final address = normalize(input);
    if (address == null) return ServerCheck.invalid;
    if (address.startsWith('http://') && !allowInsecure) {
      return ServerCheck.insecure;
    }
    try {
      final response = await _http
          .get(
            Uri.parse('$address/api/v1/health/'),
            headers: const {'Accept': 'application/json'},
          )
          .timeout(const Duration(seconds: 10));
      final body = response.body;
      final looksRight = body.contains('"status"');
      if (response.statusCode == 200 && looksRight && body.contains('"ok"')) {
        return ServerCheck.ok;
      }
      if (response.statusCode == 503 && looksRight) {
        return ServerCheck.databaseDown;
      }
      return ServerCheck.notErp;
    } on TimeoutException {
      return ServerCheck.unreachable;
    } catch (_) {
      return ServerCheck.unreachable;
    }
  }

  /// Checks and keeps the address. Anything but [ServerCheck.ok] saves nothing.
  Future<ServerCheck> save(String input) async {
    final result = await check(input);
    if (result != ServerCheck.ok) return result;
    final address = normalize(input)!;
    if (address != url) {
      await _prefs.setString(_key, address);
      await _api.switchServer(address);
      notifyListeners();
    }
    return ServerCheck.ok;
  }
}
