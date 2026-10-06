import 'package:flutter/foundation.dart';

/// Tracks whether the last attempt to reach the server worked. Stock-changing
/// actions are disabled while the server is unreachable, and anything cached is
/// shown as possibly out of date.
class ConnectionMonitor extends ChangeNotifier {
  bool _online = true;
  DateTime? _lastSuccess;

  /// False after a failed attempt, until the next successful answer.
  bool get online => _online;
  DateTime? get lastSuccess => _lastSuccess;

  void reportSuccess([DateTime? now]) {
    _lastSuccess = now ?? DateTime.now();
    if (!_online) {
      _online = true;
      notifyListeners();
    }
  }

  void reportFailure() {
    if (_online) {
      _online = false;
      notifyListeners();
    }
  }
}
