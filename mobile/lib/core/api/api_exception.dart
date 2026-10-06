import 'package:flutter/foundation.dart';

enum ApiErrorKind {
  /// No answer: connection failed or dropped.
  network,

  /// No answer within the time limit.
  timeout,

  /// The server rejected the credentials or the session ended.
  unauthorized,

  /// The server answered 4xx: it understood and refused; nothing was changed.
  client,

  /// The server answered 5xx.
  server,

  /// The answer could not be understood.
  malformed,
}

@immutable
class FieldError {
  const FieldError(this.code, this.message);
  final String code;
  final String message;
}

/// A failed request, with the stable `code` the app translates (see
/// `apiErrorText`). `message` is an English diagnostic and is never shown.
class ApiException implements Exception {
  const ApiException({
    required this.kind,
    required this.code,
    this.message = '',
    this.status,
    this.params = const {},
    this.fields = const {},
    this.requestId,
  });

  final ApiErrorKind kind;
  final String code;
  final String message;
  final int? status;
  final Map<String, dynamic> params;
  final Map<String, List<FieldError>> fields;
  final String? requestId;

  /// Parses the server's `{"error": {...}}` envelope.
  factory ApiException.fromResponse(int status, Object? json) {
    final error = json is Map && json['error'] is Map
        ? json['error'] as Map
        : const {};
    final fields = <String, List<FieldError>>{};
    final rawFields = error['fields'];
    if (rawFields is Map) {
      rawFields.forEach((key, value) {
        if (value is List) {
          fields['$key'] = [
            for (final item in value)
              if (item is Map)
                FieldError(
                  '${item['code'] ?? 'invalid'}',
                  '${item['message'] ?? ''}',
                ),
          ];
        }
      });
    }
    final params = error['params'];
    return ApiException(
      kind: status == 401
          ? ApiErrorKind.unauthorized
          : status >= 500
          ? ApiErrorKind.server
          : ApiErrorKind.client,
      code: '${error['code'] ?? (status >= 500 ? 'server_error' : 'error')}',
      message: '${error['message'] ?? ''}',
      status: status,
      params: params is Map ? params.cast<String, dynamic>() : const {},
      fields: fields,
      requestId: error['request_id'] as String?,
    );
  }

  /// The server answered with a refusal (4xx): the action was **not** performed,
  /// so the pending record can be dropped and the user shown the reason.
  bool get isDefinitive => status != null && status! >= 400 && status! < 500;

  /// We cannot tell whether the server acted (no answer, 5xx, unreadable answer).
  /// Only the same operation key may be used to try again.
  bool get outcomeUnknown =>
      kind == ApiErrorKind.network ||
      kind == ApiErrorKind.timeout ||
      kind == ApiErrorKind.server ||
      kind == ApiErrorKind.malformed;

  /// First field-level error code for [field], if any.
  String? fieldCode(String field) {
    final list = fields[field];
    return list == null || list.isEmpty ? null : list.first.code;
  }

  @override
  String toString() => 'ApiException($kind, $code, status: $status)';
}
