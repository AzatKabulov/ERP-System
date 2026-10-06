import 'package:flutter/foundation.dart';

/// Where an unconfirmed operation stands.
enum PendingState {
  /// Saved and sent (or about to be); no answer yet.
  sending,

  /// No usable answer; the server may or may not have acted.
  unknown,

  /// The server has no record of this key. Retrying with the same key is safe.
  notFound,
}

/// A stock-changing request that the server has not confirmed yet. It is saved on
/// the device **before** it is sent and removed only on a definite answer, so a
/// crash or restart can never turn one action into two (the retry reuses [key]).
/// Holds only what is needed to resend: no tokens, no balances.
@immutable
class PendingOperation {
  const PendingOperation({
    required this.key,
    required this.action,
    required this.userId,
    required this.businessId,
    required this.path,
    required this.body,
    required this.createdAt,
    this.subject = '',
    this.state = PendingState.sending,
  });

  /// The operation key (UUID) sent as `Idempotency-Key`.
  final String key;

  /// Slug such as `purchase_receive`; also part of the server's status URL.
  final String action;
  final String userId;
  final String businessId;
  final String path;
  final Map<String, dynamic> body;
  final DateTime createdAt;

  /// A short human reference such as a purchase order number.
  final String subject;
  final PendingState state;

  PendingOperation withState(PendingState next) => PendingOperation(
    key: key,
    action: action,
    userId: userId,
    businessId: businessId,
    path: path,
    body: body,
    createdAt: createdAt,
    subject: subject,
    state: next,
  );

  Map<String, dynamic> toJson() => {
    'key': key,
    'action': action,
    'userId': userId,
    'businessId': businessId,
    'path': path,
    'body': body,
    'createdAt': createdAt.toIso8601String(),
    'subject': subject,
    'state': state.name,
  };

  factory PendingOperation.fromJson(Map<String, dynamic> json) =>
      PendingOperation(
        key: json['key'] as String,
        action: json['action'] as String,
        userId: json['userId'] as String,
        businessId: json['businessId'] as String,
        path: json['path'] as String,
        body: (json['body'] as Map).cast<String, dynamic>(),
        createdAt: DateTime.parse(json['createdAt'] as String),
        subject: (json['subject'] as String?) ?? '',
        state: PendingState.values.firstWhere(
          (s) => s.name == json['state'],
          orElse: () => PendingState.unknown,
        ),
      );
}
