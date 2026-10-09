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

  String? _access;
  Future<void>? _refreshing;

  bool get hasAccessToken => _access != null;

  Future<ApiResponse> get(String path, {Map<String, String>? query}) =>
      send('GET', path, query: query);

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
  Future<Map<String, dynamic>> login(String username, String password) async {
    final response = await send(
      'POST',
      '/api/v1/auth/login/',
      body: {'username': username, 'password': password},
      authenticated: false,
    );
    final data = response.map;
    await _adopt(data['access'] as String, data['refresh'] as String);
    return data;
  }

  /// Uses the stored refresh token to obtain a session. False when there is none
  /// or it is no longer valid; throws only when the server cannot be reached.
  Future<bool> restoreSession() async {
    if (await tokens.readRefreshToken() == null) return false;
    try {
      await _refresh();
      return true;
    } on ApiException catch (e) {
      if (e.kind == ApiErrorKind.unauthorized || e.isDefinitive) return false;
      rethrow;
    }
  }

  /// The server this client talks to, without a trailing slash.
  String get baseUrl => _base.toString();

  /// Points the client at another server. Tokens belong to the server that issued them, so they
  /// are forgotten here (without telling either server).
  Future<void> switchServer(String baseUrl) async {
    final trimmed = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    _base = Uri.parse(trimmed);
    _access = null;
    await tokens.clear();
  }

  /// Revokes the refresh token on the server (best effort) and forgets all tokens.
  Future<void> logout() async {
    final refresh = await tokens.readRefreshToken();
    _access = null;
    await tokens.clear();
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
      _adopt(access, refresh);

  Future<void> _adopt(String access, String refresh) async {
    _access = access;
    await tokens.writeRefreshToken(refresh);
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
    try {
      return await _once(
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
    } on ApiException catch (e) {
      if (authenticated &&
          e.kind == ApiErrorKind.unauthorized &&
          await tokens.readRefreshToken() != null) {
        await _refresh(); // may throw: session over, or server unreachable
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
  Future<void> _refresh() => _refreshing ??= _doRefresh().whenComplete(() {
    _refreshing = null;
  });

  Future<void> _doRefresh() async {
    final refresh = await tokens.readRefreshToken();
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
      await _adopt(data['access'] as String, data['refresh'] as String);
    } on ApiException catch (e) {
      if (e.isDefinitive) {
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
