import 'package:flutter/foundation.dart';
import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_client.dart';
import '../api/api_exception.dart';
import '../files/photo_cache.dart';
import 'session_models.dart';
import 'startup_snapshot.dart';

enum SessionStatus {
  /// Looking for a stored session at start-up.
  restoring,
  signedOut,
  signedIn,
}

/// Who is signed in and which business and location they are working in.
/// Credentials and a bounded startup snapshot use secure storage. Cached roles
/// never authorize actions; a fresh server profile is required before private data.
class SessionController extends ChangeNotifier {
  SessionController({required this.api, required SharedPreferences preferences})
    : _prefs = preferences;

  final ApiClient api;
  final SharedPreferences _prefs;
  late final StartupSnapshot _snapshot = StartupSnapshot(api);
  Future<void>? _restoring;
  int _generation = 0;
  bool _disposed = false;
  Future<ApiResponse>? _startupDashboard;
  String? _startupDashboardScope;
  String? previewName;
  String? previewBusiness;

  /// Cached identity may paint a locked shell. It is never used by can().
  bool get hasPreview => previewName != null;

  String get dashboardScope {
    final m = _membership;
    return jsonEncode([
      api.baseUrl,
      _user?.id,
      _user?.isOperator,
      _user?.mustChangePassword,
      m?.id,
      m?.businessId,
      m?.role,
      (m?.permissions.toList() ?? [])..sort(),
      (m?.locations.map((l) => l.id).toList() ?? [])..sort(),
      m?.subscription?.state,
      m?.subscription?.endsAt?.toIso8601String(),
    ]);
  }

  Map<String, dynamic>? get cachedDashboard =>
      _status == SessionStatus.signedIn &&
          !isOperator &&
          !mustChangePassword &&
          !(subscription?.isBlocked ?? false) &&
          _snapshot.hasRecentDashboard &&
          _snapshot.dashboardScope == dashboardScope
      ? _snapshot.dashboard
      : null;
  DateTime? get dashboardCachedAt =>
      cachedDashboard == null ? null : _snapshot.dashboardAt;

  Future<ApiResponse>? takeStartupDashboard() {
    final result = _startupDashboardScope == dashboardScope
        ? _startupDashboard
        : null;
    _startupDashboard = null;
    _startupDashboardScope = null;
    return result;
  }

  Future<void> cacheDashboard(Map<String, dynamic> value, String scope) async {
    if (_disposed ||
        _status != SessionStatus.signedIn ||
        scope != dashboardScope ||
        isOperator ||
        mustChangePassword ||
        (subscription?.isBlocked ?? false)) {
      return;
    }
    _snapshot.dashboard = value;
    _snapshot.dashboardScope = scope;
    _snapshot.dashboardAt = DateTime.now();
    await _snapshot.save();
  }

  SessionStatus _status = SessionStatus.restoring;
  UserProfile? _user;
  List<MembershipInfo> _memberships = const [];
  MembershipInfo? _membership;
  LocationInfo? _location;
  bool _expired = false;
  bool _unreachable = false;
  List<AnnouncementInfo> _announcements = const [];
  PlatformInfo _platform = const PlatformInfo();

  /// The password just typed to sign in. Kept in memory only (never stored), so the "choose
  /// your own password" screen does not make someone retype what they typed a moment ago.
  String? _enteredPassword;

  SessionStatus get status => _status;

  /// The device's preferences, for small per-person drafts kept between visits.
  SharedPreferences get preferences => _prefs;
  UserProfile? get user => _user;
  List<MembershipInfo> get memberships => _memberships;
  MembershipInfo? get membership => _membership;
  LocationInfo? get location => _location;

  /// The previous session ended on the server; shown once on the sign-in screen.
  bool get sessionExpired => _expired;

  /// Start-up could not reach the server to check the stored session.
  bool get serverUnreachable => _unreachable;

  /// The password someone else chose must be replaced before anything else opens.
  bool get mustChangePassword => _user?.mustChangePassword ?? false;

  /// A platform operator works on the platform page, in no shop.
  bool get isOperator => _user?.isOperator ?? false;
  String? get enteredPassword => _enteredPassword;

  /// Where the shop stands with its subscription (null: nothing to say).
  SubscriptionInfo? get subscription => _membership?.subscription;
  PlatformInfo get platform => _platform;

  /// Notices from us to every shop that the person has not closed yet.
  List<AnnouncementInfo> get announcements {
    final closed = _prefs.getStringList('announcements.closed') ?? const [];
    return [
      for (final a in _announcements)
        if (!closed.contains(a.id)) a,
    ];
  }

  Future<void> dismissAnnouncement(String id) async {
    final closed = {...?_prefs.getStringList('announcements.closed'), id};
    // keep the list short: only ids that are still being announced matter
    final live = {for (final a in _announcements) a.id};
    await _prefs.setStringList('announcements.closed', [
      for (final c in closed)
        if (live.contains(c)) c,
    ]);
    notifyListeners();
  }

  /// The usernames that signed in on this device lately, newest first, so a returning person
  /// taps their name instead of typing it. Names only, never passwords.
  List<String> get recentUsernames =>
      _prefs.getStringList('signin.recent') ?? const [];

  Future<void> _rememberUsername(String username) async {
    final name = username.trim().toLowerCase();
    if (name.isEmpty) return;
    final list = [
      name,
      for (final n in recentUsernames)
        if (n != name) n,
    ];
    await _prefs.setStringList('signin.recent', list.take(5).toList());
  }

  bool can(String permission) =>
      _status == SessionStatus.signedIn &&
      (_membership?.can(permission) ?? false);

  /// The place a page is about, for its subtitle: the location's name, but only where there is
  /// a choice of places. A business is one shop whose name is already in the top bar, so
  /// repeating it under every page title would only be noise.
  String? get placeSubtitle =>
      (_membership?.locations.length ?? 0) > 1 ? _location?.name : null;

  /// Called by [ApiClient] when the server no longer accepts the refresh token.
  void handleSessionExpired() {
    if (_status != SessionStatus.signedIn) return;
    _expired = true;
    _generation++;
    _clear();
    _status = SessionStatus.signedOut;
    notifyListeners();
  }

  Future<void> restore() =>
      _restoring ??= _restore().whenComplete(() => _restoring = null);

  Future<void> _restore() async {
    final generation = ++_generation;
    _unreachable = false;
    try {
      if (await api.tokens.readRefreshToken() != null) {
        await _snapshot.read();
        if (_disposed || generation != _generation) return;
        final profile = _snapshot.profile;
        try {
          if (profile != null) {
            final u = UserProfile.fromJson(
              (profile['user'] as Map).cast<String, dynamic>(),
            );
            if (!u.isOperator && !u.mustChangePassword) {
              previewName = u.displayName;
              previewBusiness =
                  ((profile['memberships'] as List).firstOrNull
                          as Map?)?['business']?['name']
                      as String?;
              if (!_disposed && generation == _generation) notifyListeners();
            }
          }
        } catch (_) {
          _snapshot.clearMemory();
        }
      }
      final restored = await api.restoreSession();
      if (_disposed || generation != _generation) return;
      if (restored) {
        // The cached scope is only a server-checked request target. Its answer
        // stays hidden until /me confirms membership/permissions/subscription.
        Future<ApiResponse>? prefetched;
        String? oldScope;
        try {
          final profile = _snapshot.profile;
          if (profile != null) {
            final user = UserProfile.fromJson(
              (profile['user'] as Map).cast<String, dynamic>(),
            );
            final memberships = [
              for (final item in profile['memberships'] as List)
                MembershipInfo.fromJson((item as Map).cast<String, dynamic>()),
            ];
            final remembered = _prefs.getString('session.${user.id}.business');
            final m =
                memberships
                    .where((item) => item.businessId == remembered)
                    .firstOrNull ??
                memberships.first;
            if (!user.isOperator &&
                !user.mustChangePassword &&
                m.can('dashboard.view') &&
                !(m.subscription?.isBlocked ?? false)) {
              oldScope = jsonEncode([
                api.baseUrl,
                user.id,
                user.isOperator,
                user.mustChangePassword,
                m.id,
                m.businessId,
                m.role,
                m.permissions.toList()..sort(),
                m.locations.map((l) => l.id).toList()..sort(),
                m.subscription?.state,
                m.subscription?.endsAt?.toIso8601String(),
              ]);
              prefetched = api.get(
                '/api/v1/businesses/${m.businessId}/dashboard/',
              );
              // Observe errors even if a changed scope means no widget consumes it.
              unawaited(prefetched.then<void>((_) {}, onError: (Object _) {}));
            }
          }
        } catch (_) {
          /* Invalid/missing snapshots use ordinary progressive loading. */
        }
        await _loadProfile();
        if (_disposed || generation != _generation) return;
        if (oldScope == dashboardScope) {
          _startupDashboard = prefetched;
          _startupDashboardScope = oldScope;
        }
        _status = SessionStatus.signedIn;
      } else {
        _clear();
        _status = SessionStatus.signedOut;
      }
    } on ApiException catch (error) {
      if (_disposed || generation != _generation) return;
      if (error.kind == ApiErrorKind.unauthorized) {
        _clear();
        _expired = true;
        _status = SessionStatus.signedOut;
        notifyListeners();
        return;
      }
      // Cannot check the stored session right now. Stay signed out of the UI but keep
      // the stored token, so the next attempt can still succeed.
      _unreachable = true;
      _status = hasPreview ? SessionStatus.restoring : SessionStatus.signedOut;
    } catch (_) {
      // Unavailable/corrupt device storage cannot leave an endless splash.
      if (_disposed || generation != _generation) return;
      _clear();
      _status = SessionStatus.signedOut;
    }
    if (!_disposed && generation == _generation) notifyListeners();
  }

  /// Throws [ApiException] (wrong password, throttled, unreachable...).
  Future<void> signIn(
    String username,
    String password, {
    String? otpToken,
  }) async {
    final generation = ++_generation;
    await api.login(username.trim(), password, otpToken: otpToken);
    if (_disposed || generation != _generation) return;
    _expired = false;
    _unreachable = false;
    _enteredPassword = password;
    await _loadProfile();
    await _rememberUsername(username);
    if (_disposed || generation != _generation) return;
    _status = SessionStatus.signedIn;
    notifyListeners();
  }

  /// Chooses a new password for the signed-in person. The server ends every other session and
  /// answers with fresh tokens for this device. Throws [ApiException] (wrong current password,
  /// too weak a new one...).
  Future<void> changePassword(String oldPassword, String newPassword) async {
    final generation = _generation;
    final data = (await api.post(
      '/api/v1/auth/password/change/',
      body: {'old_password': oldPassword, 'new_password': newPassword},
    )).map;
    if (_disposed || generation != _generation) return;
    await api.adoptTokens(data['access'] as String, data['refresh'] as String);
    _enteredPassword = null;
    await _loadProfile();
    notifyListeners();
  }

  /// The server refused work because of the subscription (see ApiClient.onSubscriptionBlocked):
  /// read the status again so the banners and the blocked screen match.
  Future<void> handleSubscriptionBlocked() async {
    if (_status != SessionStatus.signedIn) return;
    try {
      await refreshProfile();
    } on ApiException {
      // The next refresh will do; the refused action already told the person why.
    }
  }

  /// Only the local sample server advertises this capability. Production has no route.
  Future<void> signInAsTestRole(String role) async {
    final generation = ++_generation;
    final data = (await api.post(
      '/api/v1/local-test-login/',
      body: {'role': role},
      authenticated: false,
    )).map;
    if (_disposed || generation != _generation) return;
    await api.adoptTokens(data['access'] as String, data['refresh'] as String);
    _expired = false;
    _unreachable = false;
    await _loadProfile();
    if (_disposed || generation != _generation) return;
    _status = SessionStatus.signedIn;
    notifyListeners();
  }

  Future<void> signOut() async {
    _generation++;
    final logout = api.logout();
    _expired = false;
    _clear();
    _status = SessionStatus.signedOut;
    notifyListeners();
    await logout;
  }

  /// Re-reads the profile, e.g. after staff or locations changed.
  Future<void> refreshProfile() async {
    final generation = _generation;
    await _loadProfile();
    if (!_disposed && generation == _generation) notifyListeners();
  }

  void selectMembership(String membershipId) {
    final next = _memberships.where((m) => m.id == membershipId).firstOrNull;
    if (next == null || next.id == _membership?.id) return;
    _membership = next;
    _startupDashboard = null;
    _startupDashboardScope = null;
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
    final generation = _generation;
    final previousScope = dashboardScope;
    final data = (await api.get('/api/v1/me/')).map;
    if (_disposed || generation != _generation) return;
    _user = UserProfile.fromJson((data['user'] as Map).cast<String, dynamic>());
    _announcements = [
      for (final a in (data['announcements'] as List?) ?? const [])
        AnnouncementInfo(
          id: (a as Map)['id'] as String,
          message: a['message'] as String,
        ),
    ];
    final platform = data['platform'];
    _platform = platform is Map
        ? PlatformInfo(
            supportPhone: (platform['support_phone'] as String?) ?? '',
            supportNote: (platform['support_note'] as String?) ?? '',
          )
        : const PlatformInfo();
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
    if (previousScope != dashboardScope) PhotoCache.instance.clear();
    if (_snapshot.dashboardScope != dashboardScope) {
      _snapshot.dashboard = null;
      _snapshot.dashboardAt = null;
      _snapshot.dashboardScope = null;
    }
    if (!isOperator && !mustChangePassword) {
      _snapshot.profile = {
        'user': Map<String, dynamic>.of(
          (data['user'] as Map).cast<String, dynamic>(),
        )..remove('email'),
        'memberships': data['memberships'],
      };
      _snapshot.verifiedAt = DateTime.now();
      unawaited(_snapshot.save());
    } else {
      _snapshot.clearMemory();
      unawaited(api.tokens.clearStartupSnapshot());
    }
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
    _snapshot.clearMemory();
    _startupDashboard = null;
    _startupDashboardScope = null;
    previewName = null;
    previewBusiness = null;
    PhotoCache.instance.clear();
    _user = null;
    _memberships = const [];
    _membership = null;
    _location = null;
    _announcements = const [];
    _enteredPassword = null;
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    super.dispose();
  }
}
