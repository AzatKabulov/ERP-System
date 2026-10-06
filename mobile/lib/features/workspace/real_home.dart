import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/api/api_client.dart';
import '../../core/connectivity/connection_monitor.dart';
import '../../core/operations/operation_runner.dart';
import '../../core/operations/pending_operation_store.dart';
import '../../core/session/session_controller.dart';
import '../../widgets/common.dart';
import '../auth/sign_in_screen.dart';
import 'real_workspace.dart';
import 'unsaved_work.dart';

/// Chooses between the splash, sign-in and workspace for a real (non-demo) build,
/// and owns the per-sign-in objects: the pending-operation runner is created when
/// someone signs in and dropped when they sign out, so private state never outlives
/// the session.
class RealHome extends StatefulWidget {
  const RealHome({
    super.key,
    required this.session,
    required this.api,
    required this.monitor,
    required this.preferences,
    required this.languageCode,
    required this.onLanguageChanged,
    required this.onServerLanguage,
    required this.configured,
    this.pendingStore,
  });

  final SessionController session;
  final ApiClient api;
  final ConnectionMonitor monitor;
  final SharedPreferences preferences;
  final String languageCode;
  final ValueChanged<String> onLanguageChanged;

  /// The server's saved language for the user who just signed in.
  final ValueChanged<String> onServerLanguage;
  final bool configured;

  /// Injectable for tests; defaults to a `SharedPreferences`-backed store.
  final PendingOperationStore? pendingStore;

  @override
  State<RealHome> createState() => _RealHomeState();
}

class _RealHomeState extends State<RealHome> with WidgetsBindingObserver {
  OperationRunner? _runner;
  final _unsaved = UnsavedWork();

  SessionController get session => widget.session;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    session.addListener(_sessionChanged);
    unawaited(session.restore());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    session.removeListener(_sessionChanged);
    _runner?.dispose();
    _unsaved.dispose();
    super.dispose();
  }

  void _sessionChanged() {
    final user = session.user;
    if (session.status == SessionStatus.signedIn && user != null) {
      if (_runner?.userId != user.id) {
        _runner?.dispose();
        final runner = OperationRunner(
          api: widget.api,
          store:
              widget.pendingStore ??
              PreferencesPendingOperationStore(widget.preferences),
          userId: user.id,
        );
        _runner = runner;
        widget.onServerLanguage(user.preferredLanguage);
        // Ask the server what became of anything left unconfirmed before the
        // last close, crash or restart.
        unawaited(runner.start());
      }
    } else if (_runner != null) {
      _runner!.dispose();
      _runner = null;
    }
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_runner?.recover());
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = strings(context);
    switch (session.status) {
      case SessionStatus.restoring:
        return Scaffold(
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(
                  l.checkingSession,
                  key: const ValueKey('checking-session'),
                ),
              ],
            ),
          ),
        );
      case SessionStatus.signedOut:
        return SignInScreen(
          session: session,
          languageCode: widget.languageCode,
          onLanguageChanged: widget.onLanguageChanged,
          configured: widget.configured,
        );
      case SessionStatus.signedIn:
        final runner = _runner;
        if (runner == null) return const SizedBox.shrink();
        return RealWorkspace(
          key: ValueKey(
            'workspace-${session.user?.id}-${session.membership?.id}',
          ),
          session: session,
          api: widget.api,
          runner: runner,
          monitor: widget.monitor,
          unsaved: _unsaved,
          languageCode: widget.languageCode,
          onLanguageChanged: widget.onLanguageChanged,
        );
    }
  }
}
