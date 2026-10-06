import 'package:flutter/foundation.dart';

/// Screens with data the user has typed but not saved register here, so switching
/// location or business can ask first instead of silently discarding the work.
class UnsavedWork extends ChangeNotifier {
  final Set<Object> _dirty = {};

  bool get isDirty => _dirty.isNotEmpty;

  void mark(Object owner, {required bool dirty}) {
    final changed = dirty ? _dirty.add(owner) : _dirty.remove(owner);
    if (changed) notifyListeners();
  }
}
