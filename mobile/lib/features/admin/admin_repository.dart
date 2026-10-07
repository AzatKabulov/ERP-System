import 'package:flutter/foundation.dart';

import '../../core/api/api_client.dart';

@immutable
class BusinessInfo {
  const BusinessInfo({
    required this.id,
    required this.name,
    required this.currency,
    required this.defaultLanguage,
    required this.documentLanguage,
    required this.timezone,
    this.address = '',
    this.phone = '',
  });

  final String id;
  final String name;
  final String currency;
  final String defaultLanguage;
  final String documentLanguage;
  final String timezone;

  /// Printed at the top of the receipt.
  final String address;
  final String phone;

  factory BusinessInfo.fromJson(Map<String, dynamic> json) => BusinessInfo(
    id: json['id'] as String,
    name: json['name'] as String,
    currency: json['currency'] as String,
    defaultLanguage: json['default_language'] as String,
    documentLanguage: json['document_language'] as String,
    timezone: json['timezone'] as String,
    address: json['address'] as String? ?? '',
    phone: json['phone'] as String? ?? '',
  );
}

@immutable
class LocationRecord {
  const LocationRecord({
    required this.id,
    required this.name,
    required this.kind,
    required this.isActive,
  });

  final String id;
  final String name;
  final String kind;
  final bool isActive;

  factory LocationRecord.fromJson(Map<String, dynamic> json) => LocationRecord(
    id: json['id'] as String,
    name: json['name'] as String,
    kind: json['kind'] as String,
    isActive: json['is_active'] as bool,
  );
}

@immutable
class StaffRecord {
  const StaffRecord({
    required this.id,
    required this.userId,
    required this.username,
    required this.fullName,
    required this.email,
    required this.preferredLanguage,
    required this.role,
    required this.allLocations,
    required this.locationIds,
    required this.isActive,
  });

  /// The membership id (what the API addresses).
  final String id;
  final String userId;
  final String username;
  final String fullName;
  final String email;
  final String preferredLanguage;
  final String role;
  final bool allLocations;
  final List<String> locationIds;
  final bool isActive;

  String get displayName => fullName.isEmpty ? username : fullName;

  factory StaffRecord.fromJson(Map<String, dynamic> json) {
    final user = (json['user'] as Map).cast<String, dynamic>();
    return StaffRecord(
      id: json['id'] as String,
      userId: user['id'] as String,
      username: user['username'] as String,
      fullName: (user['full_name'] as String?) ?? '',
      email: (user['email'] as String?) ?? '',
      preferredLanguage: (user['preferred_language'] as String?) ?? 'ru',
      role: json['role'] as String,
      allLocations: json['all_locations'] as bool,
      locationIds: [for (final id in json['locations'] as List) id as String],
      isActive: json['is_active'] as bool,
    );
  }
}

/// Business settings, locations and staff over the API. Contains no rules of its
/// own: the server decides what is allowed and answers with codes.
class AdminRepository {
  AdminRepository(this.api, this.businessId);

  final ApiClient api;
  final String businessId;

  String get _base => '/api/v1/businesses/$businessId';

  Future<BusinessInfo> business() async =>
      BusinessInfo.fromJson((await api.get('$_base/')).map);

  Future<BusinessInfo> updateBusiness({
    String? name,
    String? defaultLanguage,
    String? documentLanguage,
    String? address,
    String? phone,
  }) async => BusinessInfo.fromJson(
    (await api.patch(
      '$_base/',
      body: {
        'name': ?name,
        'default_language': ?defaultLanguage,
        'document_language': ?documentLanguage,
        'address': ?address,
        'phone': ?phone,
      },
    )).map,
  );

  Future<List<LocationRecord>> locations({bool includeInactive = false}) async {
    final items = await _all('$_base/locations/', {
      if (includeInactive) 'include_inactive': '1',
    });
    return [for (final i in items) LocationRecord.fromJson(i)];
  }

  Future<LocationRecord> createLocation({
    required String name,
    required String kind,
  }) async => LocationRecord.fromJson(
    (await api.post(
      '$_base/locations/',
      body: {'name': name, 'kind': kind},
    )).map,
  );

  Future<LocationRecord> updateLocation(
    String id, {
    String? name,
    String? kind,
    bool? isActive,
  }) async => LocationRecord.fromJson(
    (await api.patch(
      '$_base/locations/$id/',
      body: {'name': ?name, 'kind': ?kind, 'is_active': ?isActive},
    )).map,
  );

  Future<List<StaffRecord>> staff() async => [
    for (final i in await _all('$_base/staff/', const {}))
      StaffRecord.fromJson(i),
  ];

  Future<StaffRecord> createStaff({
    required String username,
    required String email,
    required String fullName,
    required String preferredLanguage,
    required String role,
    required bool allLocations,
    required List<String> locationIds,
    String? password,
  }) async => StaffRecord.fromJson(
    (await api.post(
      '$_base/staff/',
      body: {
        'username': username,
        'email': email,
        'full_name': fullName,
        'preferred_language': preferredLanguage,
        'role': role,
        'all_locations': allLocations,
        'locations': locationIds,
        if (password != null && password.isNotEmpty) 'password': password,
      },
    )).map,
  );

  Future<StaffRecord> updateStaff(
    String id, {
    String? role,
    bool? allLocations,
    List<String>? locationIds,
    bool? isActive,
  }) async => StaffRecord.fromJson(
    (await api.patch(
      '$_base/staff/$id/',
      body: {
        'role': ?role,
        'all_locations': ?allLocations,
        'locations': ?locationIds,
        'is_active': ?isActive,
      },
    )).map,
  );

  Future<void> sendResetCode(String id) async {
    await api.post('$_base/staff/$id/send-code/');
  }

  /// Reads every page of a list endpoint.
  Future<List<Map<String, dynamic>>> _all(
    String path,
    Map<String, String> query,
  ) async {
    final out = <Map<String, dynamic>>[];
    var offset = 0;
    while (true) {
      final page = (await api.get(
        path,
        query: {...query, 'limit': '200', 'offset': '$offset'},
      )).map;
      final results = [
        for (final r in page['results'] as List)
          (r as Map).cast<String, dynamic>(),
      ];
      out.addAll(results);
      offset += results.length;
      if (results.isEmpty || offset >= (page['count'] as int)) return out;
    }
  }
}
