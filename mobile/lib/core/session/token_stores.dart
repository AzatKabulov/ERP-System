import 'package:flutter/foundation.dart';
import 'dart:convert';
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

/// Keeps credentials and startup snapshots in the platform secure store
/// (Android Keystore / Apple Keychain; existing WebCrypto storage on HTTPS).
class SecureTokenStore implements TokenStore {
  SecureTokenStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'refresh_token';
  final FlutterSecureStorage _storage;
  static const _accessKey = 'erp.access.v1';
  static const _snapshotKey = 'erp.startup.v1';
  Future<void> _writing = Future.value();

  Future<void> _write(Future<void> Function() action) {
    final next = _writing.catchError((Object _) {}).then((_) => action());
    _writing = next;
    return next;
  }

  Future<String?> _read(String key) async {
    String? value;
    await _write(() async {
      value = await _storage.read(key: key);
    });
    return value;
  }

  Future<String?> _readScoped(String key, String server) async {
    try {
      final raw = await _read(key);
      if (raw == null) return null;
      final value = jsonDecode(raw) as Map;
      return value['server'] == server ? value['value'] as String? : null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<String?> readRefreshToken() => _read(_key);

  @override
  Future<void> writeRefreshToken(String token) =>
      _write(() => _storage.write(key: _key, value: token));

  @override
  Future<String?> readAccessToken(String server) =>
      _readScoped(_accessKey, server);
  @override
  Future<void> writeAccessToken(String server, String token) => _write(
    () => _storage.write(
      key: _accessKey,
      value: jsonEncode({'server': server, 'value': token}),
    ),
  );
  @override
  Future<String?> readStartupSnapshot(String server) =>
      _readScoped(_snapshotKey, server);
  @override
  Future<void> writeStartupSnapshot(String server, String value) => _write(
    () => _storage.write(
      key: _snapshotKey,
      value: jsonEncode({'server': server, 'value': value}),
    ),
  );
  @override
  Future<void> clearStartupSnapshot() =>
      _write(() => _storage.delete(key: _snapshotKey));

  @override
  Future<void> clear() => _write(() async {
    await Future.wait([
      for (final key in [_key, _accessKey, _snapshotKey])
        _storage.delete(key: key),
    ]);
  });
}

/// For tests and the explicitly enabled local HTTP web test build. A new tab or
/// page reload has no saved session; no credentials are persisted by this store.
class MemoryTokenStore implements TokenStore {
  MemoryTokenStore([this.token]);
  String? token;
  final Map<String, String> _access = {};
  final Map<String, String> _snapshots = {};

  @override
  Future<String?> readRefreshToken() async => token;

  @override
  Future<void> writeRefreshToken(String token) async => this.token = token;

  @override
  Future<void> clear() async {
    token = null;
    _access.clear();
    _snapshots.clear();
  }

  @override
  Future<String?> readAccessToken(String server) async => _access[server];
  @override
  Future<void> writeAccessToken(String server, String token) async =>
      _access[server] = token;
  @override
  Future<String?> readStartupSnapshot(String server) async =>
      _snapshots[server];
  @override
  Future<void> writeStartupSnapshot(String server, String value) async =>
      _snapshots[server] = value;
  @override
  Future<void> clearStartupSnapshot() async => _snapshots.clear();
}
