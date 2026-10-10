import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'pending_operation.dart';

/// Durable storage for [PendingOperation]s. Every write completes only once the
/// record is safely stored, because the request is sent right after.
abstract class PendingOperationStore {
  Future<List<PendingOperation>> load();
  Future<void> upsert(PendingOperation operation);
  Future<void> remove(String key);
}

/// Stores the records as JSON in `SharedPreferences`.
///
/// The legacy `SharedPreferences` API is used on purpose: on Android it writes with
/// `commit()`, so the returned Future completes after the data is durable. The
/// newer `SharedPreferencesAsync` API uses `apply()` and does not give that
/// guarantee: re-check this before changing it. Writes are queued so two quick
/// changes can never overwrite each other.
class PreferencesPendingOperationStore implements PendingOperationStore {
  PreferencesPendingOperationStore(this._prefs);

  static const _key = 'pending_operations_v1';
  final SharedPreferences _prefs;
  Future<void> _queue = Future.value();

  List<PendingOperation> _read() {
    final raw = _prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      return [
        for (final item in jsonDecode(raw) as List)
          PendingOperation.fromJson((item as Map).cast<String, dynamic>()),
      ];
    } on Object {
      return []; // unreadable data must not block the app
    }
  }

  Future<void> _write(List<PendingOperation> items) async {
    final ok = await _prefs.setString(
      _key,
      jsonEncode([for (final i in items) i.toJson()]),
    );
    if (!ok) throw StateError('Could not save pending operations');
  }

  Future<T> _serial<T>(Future<T> Function() action) {
    final result = _queue.then((_) => action());
    _queue = result.then<void>((_) {}, onError: (_) {});
    return result;
  }

  @override
  Future<List<PendingOperation>> load() => _serial(() async => _read());

  @override
  Future<void> upsert(PendingOperation operation) => _serial(() async {
    final items = _read();
    final index = items.indexWhere((i) => i.key == operation.key);
    if (index >= 0) {
      items[index] = operation;
    } else {
      items.add(operation);
    }
    await _write(items);
  });

  @override
  Future<void> remove(String key) => _serial(() async {
    final items = _read()..removeWhere((i) => i.key == key);
    await _write(items);
  });
}

/// For tests. Several instances can share one [backing] list to simulate a
/// restart of the app on the same device.
class MemoryPendingOperationStore implements PendingOperationStore {
  MemoryPendingOperationStore([List<PendingOperation>? backing])
    : backing = backing ?? [];
  final List<PendingOperation> backing;

  @override
  Future<List<PendingOperation>> load() async => List.of(backing);

  @override
  Future<void> upsert(PendingOperation operation) async {
    backing.removeWhere((i) => i.key == operation.key);
    backing.add(operation);
  }

  @override
  Future<void> remove(String key) async =>
      backing.removeWhere((i) => i.key == key);
}
