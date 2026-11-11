import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../connectivity/connection_monitor.dart';
import 'api_exception.dart';

/// Where the refresh token is kept (platform secure storage in the app).
abstract class TokenStore {
  Future<String?> readRefreshToken();
  Future<void> writeRefreshToken(String token);
  Future<void> clear();
  Future<String?> readAccessToken(String server);
  Future<void> writeAccessToken(String server, String token);
  Future<String?> readStartupSnapshot(String server);
  Future<void> writeStartupSnapshot(String server, String value);
  Future<void> clearStartupSnapshot();
}

@immutable
class ApiResponse {
  const ApiResponse(this.status, this.json, this.headers, {this.bytes});
  final int status;
  final Object? json;
  final Map<String, String> headers;

  /// The raw body of a file download (a PDF); null for JSON answers.
  final Uint8List? bytes;

  /// True when the server answered from its stored record of an operation key.
  bool get isReplay => headers['idempotent-replay'] == 'true';

  Map<String, dynamic> get map => (json as Map).cast<String, dynamic>();
  List<dynamic> get list => json as List<dynamic>;
}

/// A file to send with a request (a receipt photo, a CSV to import). The server checks what the
/// file really is by its content, so no content type is claimed here.
@immutable
class ApiUpload {
  const ApiUpload({
    required this.field,
    required this.filename,
    required this.bytes,
  });
  final String field;
  final String filename;
  final Uint8List bytes;
}

/// The only place that talks to the server. It adds the bearer token, refreshes
/// it once when it has expired, turns failures into [ApiException] and keeps the
/// [ConnectionMonitor] informed. It never retries a request by itself, except
/// the single re-send after a token refresh, which reuses the same idempotency key.
class ApiClient {
  ApiClient({
    required String baseUrl,
    required this.tokens,
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 15),
    this.longTimeout = const Duration(seconds: 60),
    this.monitor,
    this.onSessionExpired,
    this.onSubscriptionBlocked,
    Uuid uuid = const Uuid(),
  }) : _base = Uri.parse(
         baseUrl.endsWith('/')
             ? baseUrl.substring(0, baseUrl.length - 1)
             : baseUrl,
       ),
       _http = httpClient ?? http.Client(),
       _uuid = uuid;

  Uri _base;
  final http.Client _http;
  final Uuid _uuid;
  final TokenStore tokens;
  final Duration timeout;

  /// For file uploads and downloads, which take longer than a small JSON answer.
  final Duration longTimeout;
  final ConnectionMonitor? monitor;

  /// Called when the refresh token is no longer accepted (the user must sign in again).
  final VoidCallback? onSessionExpired;

  /// Called when the server refuses work because the shop's subscription ended or was
  /// suspended (HTTP 402), so the app can re-read it and show what happened.
  final VoidCallback? onSubscriptionBlocked;

  String? _access;
  Future<void>? _refreshing;
  int _refreshGeneration = -1;
  int _generation = 0;
  int _readRevision = 0;
  final Map<String, Future<ApiResponse>> _reads = {};

  int get sessionGeneration => _generation;

  bool get hasAccessToken => _access != null;

  Future<ApiResponse> get(String path, {Map<String, String>? query}) {
    final key = '$_generation/$_readRevision/$path/${jsonEncode(query)}';
    return _reads.putIfAbsent(key, () {
      late final Future<ApiResponse> future;
      future = send('GET', path, query: query).whenComplete(() {
        if (identical(_reads[key], future)) _reads.remove(key);
      });
      return future;
    });
  }

  /// Downloads a file (a PDF receipt, a CSV, a receipt photo): the answer's
  /// [ApiResponse.bytes]. [accept] says what kind of file is expected.
  Future<ApiResponse> download(
    String path, {
    Map<String, String>? query,
    String accept = 'application/pdf, application/json',
  }) => send('GET', path, query: query, binary: true, accept: accept);

  /// Sends a file (multipart). Not retried by itself: the caller decides.
  Future<ApiResponse> upload(String path, ApiUpload file) =>
      send('POST', path, upload: file);

  Future<ApiResponse> post(
    String path, {
    Object? body,
    String? idempotencyKey,
    bool authenticated = true,
  }) => send(
    'POST',
    path,
    body: body ?? const {},
    idempotencyKey: idempotencyKey,
    authenticated: authenticated,
  );

  Future<ApiResponse> patch(String path, {Object? body}) =>
      send('PATCH', path, body: body ?? const {});

  /// Signs in and keeps the tokens. Throws [ApiException] on failure.
  Future<Map<String, dynamic>> login(
    String username,
    String password, {
    String? otpToken,
  }) async {
    final generation = ++_generation;
    _access = null;
    _reads.clear();
    final response = await send(
      'POST',
      '/api/v1/auth/login/',
      body: {
        'username': username,
        'password': password,
        if (otpToken != null && otpToken.isNotEmpty) 'otp_token': otpToken,
      },
      authenticated: false,
    );
    final data = response.map;
    if (generation != _generation) throw _expired();
    await tokens.clearStartupSnapshot();
    await _adopt(
      data['access'] as String,
      data['refresh'] as String,
      generation: generation,
    );
    return data;
  }

  /// Uses the stored refresh token to obtain a session. False when there is none
  /// or it is no longer valid; throws only when the server cannot be reached.
  Future<bool> restoreSession() async {
    final generation = _generation;
    final refresh = await tokens.readRefreshToken();
    if (refresh == null) return false;
    try {
      final access = await tokens.readAccessToken(baseUrl);
      final accessClaims = _claims(access);
      final refreshClaims = _claims(refresh);
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      if (generation != _generation) return false;
      // This is a latency hint, never authorization. Every API read still
      // verifies signature, revocation, membership and permissions on the server.
      if (accessClaims?['token_type'] == 'access' &&
          accessClaims?['exp'] is num &&
          (accessClaims!['exp'] as num) > now + 30 &&
          refreshClaims?['token_type'] == 'refresh' &&
          refreshClaims?['exp'] is num &&
          (refreshClaims!['exp'] as num) > now &&
          accessClaims['user_id'] != null &&
          accessClaims['user_id'] == refreshClaims['user_id']) {
        _access = access;
        return true;
      }
      await _refresh();
      return true;
    } on ApiException catch (e) {
      if (e.kind == ApiErrorKind.unauthorized || e.code == 'token_not_valid') {
        return false;
      }
      rethrow;
    }
  }

  static Map<String, dynamic>? _claims(String? token) {
    try {
      if (token == null || token.split('.').length != 3) return null;
      return (jsonDecode(
                utf8.decode(
                  base64Url.decode(base64Url.normalize(token.split('.')[1])),
                ),
              )
              as Map)
          .cast<String, dynamic>();
    } catch (_) {
      return null;
    }
  }

  /// The server this client talks to, without a trailing slash.
  String get baseUrl => _base.toString();

  /// Points the client at another server. Tokens belong to the server that issued them, so they
  /// are forgotten here (without telling either server).
  Future<void> switchServer(String baseUrl) async {
    _generation++;
    _reads.clear();
    final trimmed = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    _base = Uri.parse(trimmed);
    _access = null;
    await tokens.clear();
  }

  /// Revokes the refresh token on the server (best effort) and forgets all tokens.
  Future<void> logout() async {
    final generation = ++_generation;
    _reads.clear();
    _access = null;
    final reading = tokens.readRefreshToken();
    final clearing = tokens.clear();
    final refresh = await reading;
    await clearing;
    if (generation != _generation) return;
    if (refresh == null) return;
    try {
      await send(
        'POST',
        '/api/v1/auth/logout/',
        body: {'refresh': refresh},
        authenticated: false,
      );
    } on ApiException {
      // The device is signed out either way; the token expires on its own.
    }
  }

  /// Adopts a fresh token pair, e.g. after a password change.
  Future<void> adoptTokens(String access, String refresh) =>
      _adopt(access, refresh, generation: ++_generation);

  Future<void> _adopt(
    String access,
    String refresh, {
    required int generation,
  }) async {
    if (generation != _generation) throw _expired();
    try {
      await tokens.writeRefreshToken(refresh);
    } catch (_) {
      _access = null;
      throw const ApiException(
        kind: ApiErrorKind.client,
        code: 'session_storage_unavailable',
      );
    }
    if (generation != _generation) throw _expired();
    try {
      await tokens.writeAccessToken(baseUrl, access);
    } catch (_) {
      // A missing optional access cache only costs a refresh next launch.
    }
    if (generation != _generation) throw _expired();
    _access = access;
  }

  Future<ApiResponse> send(
    String method,
    String path, {
    Map<String, String>? query,
    Object? body,
    String? idempotencyKey,
    bool authenticated = true,
    bool binary = false,
    String? accept,
    ApiUpload? upload,
  }) async {
    final generation = _generation;
    final accessAtStart = _access;
    if (authenticated &&
        _refreshGeneration == _generation &&
        _refreshing != null) {
      await _refreshing;
    }
    if (authenticated && generation != _generation) throw _expired();
    try {
      final response = await _once(
        method,
        path,
        query,
        body,
        idempotencyKey,
        authenticated,
        binary,
        accept,
        upload,
      );
      if (authenticated && generation != _generation && method == 'GET') {
        throw _expired();
      }
      if (method != 'GET') _readRevision++;
      return response;
    } on ApiException catch (e) {
      if (authenticated && generation != _generation) {
        // A command may already have committed. Preserve its real result (and
        // unknown-outcome errors), but never retry it as a different account.
        if (method == 'GET') throw _expired();
        rethrow;
      }
      if (e.status == 402 && e.code.startsWith('subscription_')) {
        onSubscriptionBlocked?.call();
      }
      if (authenticated &&
          e.kind == ApiErrorKind.unauthorized &&
          await tokens.readRefreshToken() != null) {
        if (generation != _generation) throw _expired();
        if (_access == null || _access == accessAtStart) await _refresh();
        if (generation != _generation) throw _expired();
        return _once(
          method,
          path,
          query,
          body,
          idempotencyKey,
          authenticated,
          binary,
          accept,
          upload,
        );
      }
      rethrow;
    }
  }

  /// One refresh at a time: requests that fail together wait for the same one.
  Future<void> _refresh() {
    if (_refreshGeneration == _generation && _refreshing != null) {
      return _refreshing!;
    }
    _refreshGeneration = _generation;
    late final Future<void> future;
    future = _doRefresh().whenComplete(() {
      if (identical(_refreshing, future)) _refreshing = null;
    });
    _refreshing = future;
    return future;
  }

  Future<void> _doRefresh() async {
    final generation = _generation;
    final refresh = await tokens.readRefreshToken();
    if (generation != _generation) throw _expired();
    if (refresh == null) throw _expired();
    try {
      final response = await _once(
        'POST',
        '/api/v1/auth/refresh/',
        null,
        {'refresh': refresh},
        null,
        false,
        false,
        null,
        null,
      );
      final data = response.map;
      await _adopt(
        data['access'] as String,
        data['refresh'] as String,
        generation: generation,
      );
    } on ApiException catch (e) {
      if (generation != _generation) throw _expired();
      if (e.kind == ApiErrorKind.unauthorized || e.code == 'token_not_valid') {
        // The server says this refresh token is dead: the session is over.
        _access = null;
        await tokens.clear();
        onSessionExpired?.call();
        throw _expired();
      }
      rethrow; // network trouble must not sign anyone out
    }
  }

  ApiException _expired() => const ApiException(
    kind: ApiErrorKind.unauthorized,
    code: 'session_expired',
    status: 401,
  );

  Future<ApiResponse> _once(
    String method,
    String path,
    Map<String, String>? query,
    Object? body,
    String? idempotencyKey,
    bool authenticated,
    bool binary,
    String? accept,
    ApiUpload? upload,
  ) async {
    final uri = _base.replace(
      path: '${_base.path}$path',
      queryParameters: query == null || query.isEmpty ? null : query,
    );
    final http.BaseRequest request;
    if (upload != null) {
      request = http.MultipartRequest(method, uri)
        ..files.add(
          http.MultipartFile.fromBytes(
            upload.field,
            upload.bytes,
            filename: upload.filename,
          ),
        );
    } else {
      final plain = http.Request(method, uri);
      if (body != null) {
        plain.headers['Content-Type'] = 'application/json; charset=utf-8';
        plain.bodyBytes = utf8.encode(jsonEncode(body));
      }
      request = plain;
    }
    request.headers['Accept'] = binary
        ? (accept ?? 'application/pdf, application/json')
        : 'application/json';
    request.headers['X-Request-ID'] = _uuid.v4();
    final limit = binary || upload != null ? longTimeout : timeout;
    if (idempotencyKey != null) {
      request.headers['Idempotency-Key'] = idempotencyKey;
    }
    if (authenticated && _access != null) {
      request.headers['Authorization'] = 'Bearer $_access';
    }

    final http.Response response;
    try {
      final streamed = await _http.send(request).timeout(limit);
      response = await http.Response.fromStream(streamed).timeout(limit);
    } on TimeoutException {
      monitor?.reportFailure();
      throw const ApiException(kind: ApiErrorKind.timeout, code: 'timeout');
    } on http.ClientException {
      monitor?.reportFailure();
      throw const ApiException(kind: ApiErrorKind.network, code: 'network');
    } catch (_) {
      // Socket and TLS errors surface as platform-specific types.
      monitor?.reportFailure();
      throw const ApiException(kind: ApiErrorKind.network, code: 'network');
    }
    monitor?.reportSuccess();
    if (binary && response.statusCode >= 200 && response.statusCode < 300) {
      return ApiResponse(
        response.statusCode,
        null,
        response.headers,
        bytes: response.bodyBytes,
      );
    }

    // The server sends UTF-8 without a charset header; `http` would assume Latin-1
    // and garble Russian and Turkmen text, so decode the bytes ourselves.
    final text = utf8.decode(response.bodyBytes, allowMalformed: true);
    Object? json;
    if (text.isNotEmpty) {
      try {
        json = jsonDecode(text);
      } on FormatException {
        if (response.statusCode >= 200 && response.statusCode < 300) {
          throw const ApiException(
            kind: ApiErrorKind.malformed,
            code: 'malformed_response',
          );
        }
      }
    }
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return ApiResponse(response.statusCode, json, response.headers);
    }
    throw ApiException.fromResponse(response.statusCode, json);
  }

  void close() => _http.close();
}
