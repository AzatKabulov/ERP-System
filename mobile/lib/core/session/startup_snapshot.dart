import 'dart:convert';

import '../api/api_client.dart';

/// A bounded, server-scoped encrypted snapshot. It never grants permissions.
/// Private figures are read only after a fresh /me response confirms the scope.
class StartupSnapshot {
  StartupSnapshot(this.api);
  final ApiClient api;
  Map<String, dynamic>? profile;
  Map<String, dynamic>? dashboard;
  String? dashboardScope;
  DateTime? dashboardAt;
  DateTime? verifiedAt;

  Future<void> read() async {
    clearMemory();
    try {
      final raw = await api.tokens.readStartupSnapshot(api.baseUrl);
      if (raw == null || utf8.encode(raw).length > 65536) return;
      final value = jsonDecode(raw) as Map;
      final verified = DateTime.parse(value['verified_at'] as String);
      final age = DateTime.now().difference(verified);
      if (value['version'] != 1 ||
          age.isNegative ||
          age > const Duration(hours: 24)) {
        return;
      }
      profile = (value['profile'] as Map).cast<String, dynamic>();
      verifiedAt = verified;
      dashboard = (value['dashboard'] as Map?)?.cast<String, dynamic>();
      dashboardScope = value['scope'] as String?;
      dashboardAt = DateTime.tryParse(value['dashboard_at'] as String? ?? '');
    } catch (_) {
      clearMemory();
    }
  }

  bool get hasRecentDashboard {
    final age = dashboardAt == null
        ? null
        : DateTime.now().difference(dashboardAt!);
    return dashboard != null &&
        age != null &&
        !age.isNegative &&
        age < const Duration(minutes: 10);
  }

  Future<void> save() async {
    if (profile == null || verifiedAt == null) return;
    final value = jsonEncode({
      'version': 1,
      'profile': profile,
      'verified_at': verifiedAt!.toUtc().toIso8601String(),
      'dashboard': dashboard,
      'dashboard_at': dashboardAt?.toUtc().toIso8601String(),
      'scope': dashboardScope,
    });
    if (utf8.encode(value).length > 65536) return;
    try {
      await api.tokens.writeStartupSnapshot(api.baseUrl, value);
    } catch (_) {
      // Storage/quota failures only remove the optimization, never sign-in.
    }
  }

  void clearMemory() {
    profile = null;
    dashboard = null;
    dashboardScope = null;
    dashboardAt = null;
    verifiedAt = null;
  }
}
