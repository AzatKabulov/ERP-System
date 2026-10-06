import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../api/api_client.dart';
import '../api/api_exception.dart';
import 'pending_operation.dart';
import 'pending_operation_store.dart';

sealed class OperationOutcome {
  const OperationOutcome();
}

/// The server confirmed the action (possibly from its stored record of the key).
class OperationCompleted extends OperationOutcome {
  const OperationCompleted(this.response, {this.recovered = false});
  final ApiResponse response;

  /// Found by asking for the outcome after a restart or timeout, not by this request.
  final bool recovered;
}

/// The server refused: nothing was changed. Show the reason; the record is gone.
class OperationRejected extends OperationOutcome {
  const OperationRejected(this.error);
  final ApiException error;
}

/// No usable answer. The record stays saved; use [OperationRunner.retry] (same
/// key), [OperationRunner.recover] or [OperationRunner.discard].
class OperationUnknown extends OperationOutcome {
  const OperationUnknown(this.operation, this.error);
  final PendingOperation operation;
  final ApiException error;
}

/// Runs stock-changing commands so that one user action is never performed twice,
/// even when the connection drops, the app crashes or the tablet restarts:
///
/// 1. the request (with its operation key) is saved on the device;
/// 2. it is sent with that key as `Idempotency-Key`;
/// 3. the record is removed only after a definite answer;
/// 4. after any doubt, the server is asked what happened to that key before
///    anything is sent again, and a resend always reuses the same key.
class OperationRunner extends ChangeNotifier {
  OperationRunner({
    required this.api,
    required PendingOperationStore store,
    required this.userId,
    Uuid uuid = const Uuid(),
    DateTime Function()? clock,
  }) : _store = store,
       _uuid = uuid,
       _clock = clock ?? DateTime.now;

  final ApiClient api;
  final String userId;
  final PendingOperationStore _store;
  final Uuid _uuid;
  final DateTime Function() _clock;

  List<PendingOperation> _pending = const [];
  final Set<String> _busy = {};

  /// Operations of the signed-in user that the server has not confirmed yet.
  List<PendingOperation> get pending => _pending;
  bool get hasPending => _pending.isNotEmpty;

  /// Loads saved records (call at start-up and after sign-in), then asks the
  /// server what became of each. Returns the operations found completed.
  Future<List<PendingOperation>> start() async {
    await _reload();
    return recover();
  }

  Future<OperationOutcome> submit({
    required String action,
    required String businessId,
    required String path,
    required Map<String, dynamic> body,
    String subject = '',
  }) async {
    final operation = PendingOperation(
      key: _uuid.v4(),
      action: action,
      userId: userId,
      businessId: businessId,
      path: path,
      body: body,
      createdAt: _clock(),
      subject: subject,
    );
    await _store.upsert(operation); // saved BEFORE it is sent
    await _reload();
    return _send(operation);
  }

  /// Sends the saved request again with the **same** operation key.
  Future<OperationOutcome> retry(String key) async {
    final operation = _pending.where((o) => o.key == key).firstOrNull;
    if (operation == null) {
      throw StateError('No pending operation with key $key');
    }
    return _send(operation);
  }

  /// Asks the server about every unconfirmed operation. Completed ones are
  /// cleared and returned so screens can refresh; unknown ones stay listed.
  Future<List<PendingOperation>> recover() async {
    final completed = <PendingOperation>[];
    for (final operation in List.of(_pending)) {
      if (!_busy.add(operation.key)) continue;
      try {
        await api.get(
          '/api/v1/businesses/${operation.businessId}/operations/'
          '${operation.action}/${operation.key}/',
        );
        await _store.remove(operation.key);
        completed.add(operation);
      } on ApiException catch (e) {
        if (e.code == 'operation_not_found') {
          await _store.upsert(operation.withState(PendingState.notFound));
        }
        // Any other failure (offline, expired session): leave it for next time.
      } finally {
        _busy.remove(operation.key);
      }
    }
    await _reload();
    return completed;
  }

  /// Forgets an operation. Only do this after the server has said it has no
  /// record of it, or after the user has confirmed they accept the risk.
  Future<void> discard(String key) async {
    await _store.remove(key);
    await _reload();
  }

  Future<OperationOutcome> _send(PendingOperation operation) async {
    if (!_busy.add(operation.key)) {
      return OperationUnknown(
        operation,
        const ApiException(kind: ApiErrorKind.network, code: 'busy'),
      );
    }
    try {
      final response = await api.post(
        operation.path,
        body: operation.body,
        idempotencyKey: operation.key,
      );
      await _store.remove(operation.key);
      await _reload();
      return OperationCompleted(response);
    } on ApiException catch (e) {
      // 4xx means the server refused and changed nothing. The one exception is an
      // ended session (401): the action was not performed, but keep it so it can
      // be sent after signing in again.
      if (e.isDefinitive && e.kind != ApiErrorKind.unauthorized) {
        await _store.remove(operation.key);
        await _reload();
        return OperationRejected(e);
      }
      final unknown = operation.withState(PendingState.unknown);
      await _store.upsert(unknown);
      await _reload();
      return OperationUnknown(unknown, e);
    } finally {
      _busy.remove(operation.key);
    }
  }

  Future<void> _reload() async {
    _pending = [
      for (final o in await _store.load())
        if (o.userId == userId) o,
    ]..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    notifyListeners();
  }
}
