import 'package:flutter/foundation.dart';

@immutable
class UserProfile {
  const UserProfile({
    required this.id,
    required this.username,
    required this.fullName,
    required this.email,
    required this.preferredLanguage,
  });

  final String id;
  final String username;
  final String fullName;
  final String email;
  final String preferredLanguage;

  String get displayName => fullName.isEmpty ? username : fullName;

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
    id: json['id'] as String,
    username: json['username'] as String,
    fullName: (json['full_name'] as String?) ?? '',
    email: (json['email'] as String?) ?? '',
    preferredLanguage: (json['preferred_language'] as String?) ?? 'ru',
  );
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
  });

  final String id;
  final String businessId;
  final String businessName;
  final String currency;
  final String role; // owner | manager | sales | warehouse
  final Set<String> permissions;
  final List<LocationInfo> locations;

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
    );
  }
}
