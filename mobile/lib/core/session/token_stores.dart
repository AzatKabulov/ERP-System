import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../api/api_client.dart';

/// Only an explicitly built local HTTP test website may use a tab-only session.
/// Public hosts, HTTPS and native apps keep the platform's secure storage.
TokenStore createTokenStore({
  bool isWeb = kIsWeb,
  Uri? origin,
  bool localHttpTesting = const bool.fromEnvironment('LOCAL_HTTP_TESTING'),
}) {
  final address = origin ?? Uri.base;
  final octets = address.host.split('.').map(int.tryParse).toList();
  final privateIpv4 =
      octets.length == 4 &&
      octets.every((n) => n != null && n >= 0 && n <= 255) &&
      (octets[0] == 10 ||
          (octets[0] == 172 && octets[1]! >= 16 && octets[1]! <= 31) ||
          (octets[0] == 192 && octets[1] == 168));
  if (isWeb && localHttpTesting && address.scheme == 'http' && privateIpv4) {
    return MemoryTokenStore();
  }
  return SecureTokenStore();
}

/// Keeps the refresh token in the platform secure store (Android Keystore /
/// Apple Keychain). It is the only credential stored on the device.
class SecureTokenStore implements TokenStore {
  SecureTokenStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'refresh_token';
  final FlutterSecureStorage _storage;

  @override
  Future<String?> readRefreshToken() => _storage.read(key: _key);

  @override
  Future<void> writeRefreshToken(String token) =>
      _storage.write(key: _key, value: token);

  @override
  Future<void> clear() => _storage.delete(key: _key);
}

/// For tests and the explicitly enabled local HTTP web test build. A new tab or
/// page reload has no saved session; no credentials are persisted by this store.
class MemoryTokenStore implements TokenStore {
  MemoryTokenStore([this.token]);
  String? token;

  @override
  Future<String?> readRefreshToken() async => token;

  @override
  Future<void> writeRefreshToken(String token) async => this.token = token;

  @override
  Future<void> clear() async => token = null;
}
