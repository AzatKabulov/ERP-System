import 'package:flutter/foundation.dart';

/// Screens with data the user has typed but not saved register here, so switching
/// location or business can ask first instead of silently discarding the work.
class UnsavedWork extends ChangeNotifier {
  final Set<Object> _dirty = {};
  bool _disposed = false;

  bool get isDirty => _dirty.isNotEmpty;

  void mark(Object owner, {required bool dirty}) {
    // Pushed screens are siblings of the workspace, not its children, so while the
    // whole app is torn down they can be disposed after this object has been.
    if (_disposed) return;
    final changed = dirty ? _dirty.add(owner) : _dirty.remove(owner);
    if (changed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
