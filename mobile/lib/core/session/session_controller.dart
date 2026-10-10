import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_client.dart';
import '../api/api_exception.dart';
import 'session_models.dart';

enum SessionStatus {
  /// Looking for a stored session at start-up.
  restoring,
  signedOut,
  signedIn,
}

/// Who is signed in and which business and location they are working in.
/// Nothing private is stored on the device except the refresh token (in secure
/// storage) and the ids of the last business/location, which are not secret.
class SessionController extends ChangeNotifier {
  SessionController({required this.api, required SharedPreferences preferences})
    : _prefs = preferences;

  final ApiClient api;
  final SharedPreferences _prefs;

  SessionStatus _status = SessionStatus.restoring;
  UserProfile? _user;
  List<MembershipInfo> _memberships = const [];
  MembershipInfo? _membership;
  LocationInfo? _location;
  bool _expired = false;
  bool _unreachable = false;

  SessionStatus get status => _status;
  UserProfile? get user => _user;
  List<MembershipInfo> get memberships => _memberships;
  MembershipInfo? get membership => _membership;
  LocationInfo? get location => _location;

  /// The previous session ended on the server; shown once on the sign-in screen.
  bool get sessionExpired => _expired;

  /// Start-up could not reach the server to check the stored session.
  bool get serverUnreachable => _unreachable;

  bool can(String permission) => _membership?.can(permission) ?? false;

  /// Called by [ApiClient] when the server no longer accepts the refresh token.
  void handleSessionExpired() {
    if (_status != SessionStatus.signedIn) return;
    _expired = true;
    _clear();
    _status = SessionStatus.signedOut;
    notifyListeners();
  }

  Future<void> restore() async {
    _unreachable = false;
    try {
      if (await api.restoreSession()) {
        await _loadProfile();
        _status = SessionStatus.signedIn;
      } else {
        _status = SessionStatus.signedOut;
      }
    } on ApiException {
      // Cannot check the stored session right now. Stay signed out of the UI but keep
      // the stored token, so the next attempt can still succeed.
      _unreachable = true;
      _status = SessionStatus.signedOut;
    }
    notifyListeners();
  }

  /// Throws [ApiException] (wrong password, throttled, unreachable...).
  Future<void> signIn(String username, String password) async {
    await api.login(username.trim(), password);
    _expired = false;
    _unreachable = false;
    await _loadProfile();
    _status = SessionStatus.signedIn;
    notifyListeners();
  }

  Future<void> signOut() async {
    await api.logout();
    _expired = false;
    _clear();
    _status = SessionStatus.signedOut;
    notifyListeners();
  }

  /// Re-reads the profile, e.g. after staff or locations changed.
  Future<void> refreshProfile() async {
    await _loadProfile();
    notifyListeners();
  }

  void selectMembership(String membershipId) {
    final next = _memberships.where((m) => m.id == membershipId).firstOrNull;
    if (next == null || next.id == _membership?.id) return;
    _membership = next;
    _location = _initialLocation(next);
    _remember();
    notifyListeners();
  }

  void selectLocation(String locationId) {
    final next = _membership?.locations
        .where((l) => l.id == locationId)
        .firstOrNull;
    if (next == null || next.id == _location?.id) return;
    _location = next;
    _remember();
    notifyListeners();
  }

  /// Saves the interface language on the server (best effort: the local choice
  /// stays in force even when this fails).
  Future<void> saveLanguage(String code) async {
    try {
      await api.patch('/api/v1/me/', body: {'preferred_language': code});
    } on ApiException {
      // Kept locally; it will be saved with the next change.
    }
  }

  Future<void> _loadProfile() async {
    final data = (await api.get('/api/v1/me/')).map;
    _user = UserProfile.fromJson((data['user'] as Map).cast<String, dynamic>());
    _memberships = [
      for (final m in data['memberships'] as List)
        MembershipInfo.fromJson((m as Map).cast<String, dynamic>()),
    ];
    final lastBusiness = _prefs.getString(_key('business'));
    _membership =
        _memberships.where((m) => m.businessId == lastBusiness).firstOrNull ??
        _memberships.firstOrNull;
    _location = _membership == null ? null : _initialLocation(_membership!);
    _remember();
  }

  LocationInfo? _initialLocation(MembershipInfo membership) {
    final last = _prefs.getString(_key('location'));
    return membership.locations.where((l) => l.id == last).firstOrNull ??
        membership.locations.firstOrNull;
  }

  String _key(String name) => 'session.${_user?.id}.$name';

  void _remember() {
    if (_user == null) return;
    final business = _membership?.businessId;
    final location = _location?.id;
    if (business != null) _prefs.setString(_key('business'), business);
    if (location != null) _prefs.setString(_key('location'), location);
  }

  void _clear() {
    _user = null;
    _memberships = const [];
    _membership = null;
    _location = null;
  }
}
