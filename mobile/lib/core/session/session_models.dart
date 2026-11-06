import 'package:flutter/foundation.dart';

@immutable
class UserProfile {
  const UserProfile({
    required this.id,
    required this.username,
    required this.fullName,
    required this.email,
    required this.preferredLanguage,
    this.mustChangePassword = false,
  });

  final String id;
  final String username;
  final String fullName;
  final String email;
  final String preferredLanguage;

  /// Somebody else chose this password (the owner, or us for a new shop): it must be replaced
  /// by the person's own before anything else opens.
  final bool mustChangePassword;

  String get displayName => fullName.isEmpty ? username : fullName;

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
    id: json['id'] as String,
    username: json['username'] as String,
    fullName: (json['full_name'] as String?) ?? '',
    email: (json['email'] as String?) ?? '',
    preferredLanguage: (json['preferred_language'] as String?) ?? 'ru',
    mustChangePassword: (json['must_change_password'] as bool?) ?? false,
  );
}

/// Where a shop stands with its subscription. `state` is one of free, active, expiring, grace,
/// read_only, suspended. Only the owner and managers receive the dates; everyone else is told
/// only when work is blocked.
@immutable
class SubscriptionInfo {
  const SubscriptionInfo({
    required this.state,
    this.isTrial = false,
    this.endsAt,
    this.graceEndsAt,
    this.daysLeft,
  });

  final String state;
  final bool isTrial;
  final DateTime? endsAt;
  final DateTime? graceEndsAt;
  final int? daysLeft;

  bool get isSuspended => state == 'suspended';
  bool get isReadOnly => state == 'read_only';

  /// Looking is allowed but nothing may be changed (or nothing at all, when suspended).
  bool get isBlocked => isReadOnly || isSuspended;
  bool get needsWarning => state == 'expiring' || state == 'grace' || isBlocked;

  factory SubscriptionInfo.fromJson(Map<String, dynamic> json) =>
      SubscriptionInfo(
        state: json['state'] as String,
        isTrial: (json['is_trial'] as bool?) ?? false,
        endsAt: _date(json['ends_at']),
        graceEndsAt: _date(json['grace_ends_at']),
        daysLeft: json['days_left'] as int?,
      );

  static DateTime? _date(Object? value) =>
      value is String ? DateTime.tryParse(value)?.toLocal() : null;
}

/// A notice from us to every shop ("maintenance tonight").
@immutable
class AnnouncementInfo {
  const AnnouncementInfo({required this.id, required this.message});
  final String id;
  final String message;
}

/// How a shop reaches us (set on the server).
@immutable
class PlatformInfo {
  const PlatformInfo({this.supportPhone = '', this.supportNote = ''});
  final String supportPhone;
  final String supportNote;

  bool get hasContact => supportPhone.isNotEmpty || supportNote.isNotEmpty;
}

@immutable
class LocationInfo {
  const LocationInfo({
    required this.id,
    required this.name,
    required this.kind,
  });

  final String id;
  final String name;
  final String kind; // 'store' | 'warehouse'

  factory LocationInfo.fromJson(Map<String, dynamic> json) => LocationInfo(
    id: json['id'] as String,
    name: json['name'] as String,
    kind: (json['kind'] as String?) ?? 'store',
  );
}

/// The signed-in user's place in one business: their role, what the server lets
/// that role do, and which locations they may use. The server enforces all of
/// it again on every request; this only decides what to show.
@immutable
class MembershipInfo {
  const MembershipInfo({
    required this.id,
    required this.businessId,
    required this.businessName,
    required this.currency,
    required this.role,
    required this.permissions,
    required this.locations,
    this.subscription,
  });

  final String id;
  final String businessId;
  final String businessName;
  final String currency;
  final String role; // owner | manager | sales | warehouse
  final Set<String> permissions;
  final List<LocationInfo> locations;

  /// Null for a seller or keeper while everything is fine.
  final SubscriptionInfo? subscription;

  bool can(String permission) => permissions.contains(permission);

  factory MembershipInfo.fromJson(Map<String, dynamic> json) {
    final business = (json['business'] as Map).cast<String, dynamic>();
    return MembershipInfo(
      id: json['id'] as String,
      businessId: business['id'] as String,
      businessName: business['name'] as String,
      currency: (business['currency'] as String?) ?? 'TMT',
      role: json['role'] as String,
      permissions: {for (final p in json['permissions'] as List) p as String},
      locations: [
        for (final l in json['locations'] as List)
          LocationInfo.fromJson((l as Map).cast<String, dynamic>()),
      ],
      subscription: json['subscription'] is Map
          ? SubscriptionInfo.fromJson(
              (json['subscription'] as Map).cast<String, dynamic>(),
            )
          : null,
    );
  }
}
