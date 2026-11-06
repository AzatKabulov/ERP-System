import 'package:flutter/foundation.dart';

import '../../core/api/api_client.dart';

@immutable
class SupportMessage {
  const SupportMessage({
    required this.id,
    required this.fromStore,
    required this.text,
    required this.createdAt,
  });

  final String id;

  /// Written by someone in the shop (false: written by us).
  final bool fromStore;
  final String text;
  final DateTime createdAt;

  factory SupportMessage.fromJson(Map<String, dynamic> json) => SupportMessage(
    id: json['id'] as String,
    fromStore: json['from_store'] as bool,
    text: json['text'] as String,
    createdAt: DateTime.parse(json['created_at'] as String),
  );
}

@immutable
class SupportRequest {
  const SupportRequest({
    required this.id,
    required this.subject,
    required this.status,
    required this.updatedAt,
    required this.messages,
  });

  final String id;
  final String subject;

  /// open (waiting for us), answered, closed.
  final String status;
  final DateTime updatedAt;
  final List<SupportMessage> messages;

  bool get isClosed => status == 'closed';

  factory SupportRequest.fromJson(Map<String, dynamic> json) => SupportRequest(
    id: json['id'] as String,
    subject: json['subject'] as String,
    status: json['status'] as String,
    updatedAt: DateTime.parse(json['updated_at'] as String),
    messages: [
      for (final m in json['messages'] as List)
        SupportMessage.fromJson((m as Map).cast<String, dynamic>()),
    ],
  );
}

/// The conversation between a shop and us. Plain requests: nothing here changes stock or money,
/// so no operation key is needed.
class SupportRepository {
  SupportRepository(this.api, this.businessId);

  final ApiClient api;
  final String businessId;

  String get _base => '/api/v1/businesses/$businessId/support/';

  Future<List<SupportRequest>> list() async {
    final map = (await api.get(_base)).map;
    return [
      for (final r in map['results'] as List)
        SupportRequest.fromJson((r as Map).cast<String, dynamic>()),
    ];
  }

  Future<SupportRequest> create({
    required String subject,
    required String body,
    String screen = '',
    String appVersion = '',
  }) async => SupportRequest.fromJson(
    (await api.post(
      _base,
      body: {
        'subject': subject,
        'body': body,
        'screen': screen,
        'app_version': appVersion,
      },
    )).map,
  );

  Future<SupportRequest> reply(String requestId, String body) async =>
      SupportRequest.fromJson(
        (await api.post(
          '$_base$requestId/messages/',
          body: {'body': body},
        )).map,
      );
}
