import 'package:erp_system/core/api/api_client.dart';
import 'package:erp_system/core/api/api_exception.dart';
import 'package:erp_system/core/operations/operation_runner.dart';
import 'package:erp_system/core/operations/pending_operation.dart';
import 'package:erp_system/core/operations/pending_operation_store.dart';
import 'package:erp_system/core/session/token_stores.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_server.dart';

const path = '/api/v1/businesses/b-1/demo/';

/// One "run" of the app: its own API client and runner on the same device storage.
class AppRun {
  AppRun(this.server, PendingOperationStore store, {String userId = 'u-1'})
    : api = ApiClient(
        baseUrl: 'https://api.example.test',
        tokens: MemoryTokenStore('refresh-1'),
        httpClient: server.client,
        timeout: const Duration(seconds: 2),
      ) {
    runner = OperationRunner(api: api, store: store, userId: userId);
  }

  final FakeServer server;
  final ApiClient api;
  late final OperationRunner runner;

  Future<void> signedIn() => api.login('aman', 'right-password');

  Future<OperationOutcome> receive({int n = 1, String subject = 'PO-000012'}) =>
      runner.submit(
        action: 'demo',
        businessId: 'b-1',
        path: path,
        body: {'n': n},
        subject: subject,
      );
}

void main() {
  test('happy path: confirmed, performed once, nothing left pending', () async {
    final server = FakeServer();
    final store = MemoryPendingOperationStore();
    final run = AppRun(server, store);
    await run.signedIn();
    final outcome = await run.receive();
    expect(outcome, isA<OperationCompleted>());
    expect(server.performed, hasLength(1));
    expect(run.runner.hasPending, isFalse);
    expect(store.backing, isEmpty);
  });

  test(
    'the record is saved on the device BEFORE the request is sent',
    () async {
      final server = FakeServer();
      final store = MemoryPendingOperationStore();
      final run = AppRun(server, store);
      await run.signedIn();
      // simulate "the app dies the moment it tries to send"
      server.reachable = false;
      final outcome = await run.receive();
      expect(outcome, isA<OperationUnknown>());
      expect(store.backing, hasLength(1));
      expect(store.backing.single.state, PendingState.unknown);
      expect(store.backing.single.subject, 'PO-000012');
      expect(server.performed, isEmpty);
    },
  );

  test(
    'RESTART: server committed, answer lost, app restarted -> found completed, exactly one record',
    () async {
      final server = FakeServer()..dropResponseAfterCommit = 1;
      final device = <PendingOperation>[]; // survives the "restart"

      // --- first run: the answer never arrives
      final first = AppRun(server, MemoryPendingOperationStore(device));
      await first.signedIn();
      final outcome = await first.receive();
      expect(outcome, isA<OperationUnknown>());
      expect(server.performed, hasLength(1)); // the server did commit
      expect(
        device,
        hasLength(1),
      ); // and the device remembers it is unconfirmed

      // --- the tablet restarts: new client, new runner, same device storage
      final second = AppRun(server, MemoryPendingOperationStore(device));
      await second.signedIn();
      final recovered = await second.runner.start();

      expect(recovered, hasLength(1));
      expect(recovered.single.subject, 'PO-000012');
      expect(device, isEmpty);
      expect(second.runner.hasPending, isFalse);
      expect(server.performed, hasLength(1)); // still exactly one
      expect(
        server.log.where((l) => l.startsWith('POST $path')),
        hasLength(1), // recovery asked, it did not re-send
      );
    },
  );

  test(
    'a retry after a lost answer reuses the same key and is not performed twice',
    () async {
      final server = FakeServer()..dropResponseAfterCommit = 1;
      final run = AppRun(server, MemoryPendingOperationStore());
      await run.signedIn();
      final first = await run.receive();
      expect(first, isA<OperationUnknown>());
      final key = (first as OperationUnknown).operation.key;

      final retried = await run.runner.retry(key);
      expect(retried, isA<OperationCompleted>());
      expect((retried as OperationCompleted).response.isReplay, isTrue);
      expect(server.performed, hasLength(1));
      expect(
        server.requestHeaders
            .where((h) => h['Idempotency-Key'] != null)
            .map((h) => h['Idempotency-Key'])
            .toSet(),
        {key},
      );
      expect(run.runner.hasPending, isFalse);
    },
  );

  test(
    'a 5xx before anything happened stays pending; the same-key retry then performs it once',
    () async {
      final server = FakeServer()..failBeforeCommit = 1;
      final run = AppRun(server, MemoryPendingOperationStore());
      await run.signedIn();
      final first = await run.receive();
      expect(first, isA<OperationUnknown>());
      expect(server.performed, isEmpty);
      final done = await run.runner.retry(
        (first as OperationUnknown).operation.key,
      );
      expect(done, isA<OperationCompleted>());
      expect(server.performed, hasLength(1));
    },
  );

  test(
    'after a restart, an operation the server never saw is listed as not found and can be retried or discarded',
    () async {
      final server = FakeServer();
      final device = <PendingOperation>[];
      final first = AppRun(server, MemoryPendingOperationStore(device));
      await first.signedIn();
      server.reachable = false;
      await first.receive();
      server.reachable = true;

      final second = AppRun(server, MemoryPendingOperationStore(device));
      await second.signedIn();
      final recovered = await second.runner.start();
      expect(recovered, isEmpty);
      expect(second.runner.pending.single.state, PendingState.notFound);
      expect(
        server.performed,
        isEmpty,
      ); // nothing was re-sent behind the user's back

      final retried = await second.runner.retry(
        second.runner.pending.single.key,
      );
      expect(retried, isA<OperationCompleted>());
      expect(server.performed, hasLength(1));

      // discard path
      server.reachable = false;
      await second.receive(n: 2);
      await second.runner.discard(second.runner.pending.single.key);
      expect(second.runner.hasPending, isFalse);
    },
  );

  test(
    'a refusal (4xx) clears the record and reports why; nothing was changed',
    () async {
      final server = FakeServer()..rejectWith = 'insufficient_stock';
      final store = MemoryPendingOperationStore();
      final run = AppRun(server, store);
      await run.signedIn();
      final outcome = await run.receive();
      expect(outcome, isA<OperationRejected>());
      expect((outcome as OperationRejected).error.code, 'insufficient_stock');
      expect(store.backing, isEmpty);
      expect(server.performed, isEmpty);
    },
  );

  test(
    'an ended session keeps the record so it can be sent after signing in again',
    () async {
      final server = FakeServer();
      final store = MemoryPendingOperationStore();
      final run = AppRun(server, store);
      await run.signedIn();
      server.expireAccess = true;
      server.refreshRejected = true;
      final outcome = await run.receive();
      expect(outcome, isA<OperationUnknown>());
      expect(
        (outcome as OperationUnknown).error.kind,
        ApiErrorKind.unauthorized,
      );
      expect(store.backing, hasLength(1));
      expect(server.performed, isEmpty);
    },
  );

  test('records are private to the signed-in user', () async {
    final server = FakeServer();
    final device = <PendingOperation>[];
    final aman = AppRun(server, MemoryPendingOperationStore(device));
    await aman.signedIn();
    server.reachable = false;
    await aman.receive();
    server.reachable = true;
    expect(aman.runner.pending, hasLength(1));

    final other = AppRun(
      server,
      MemoryPendingOperationStore(device),
      userId: 'u-2',
    );
    await other.signedIn();
    await other.runner.start();
    expect(other.runner.pending, isEmpty);
    expect(device, hasLength(1)); // untouched, waiting for its owner
  });

  test(
    'recover leaves everything alone while the server is unreachable',
    () async {
      final server = FakeServer();
      final device = <PendingOperation>[];
      final first = AppRun(server, MemoryPendingOperationStore(device));
      await first.signedIn();
      server.dropResponseAfterCommit = 1;
      await first.receive();

      final second = AppRun(server, MemoryPendingOperationStore(device));
      await second.signedIn();
      server.reachable = false;
      final recovered = await second.runner.start();
      expect(recovered, isEmpty);
      expect(device, hasLength(1));
      server.reachable = true;
      expect(await second.runner.recover(), hasLength(1));
      expect(device, isEmpty);
    },
  );

  test(
    'two submissions are two separate operations with different keys',
    () async {
      final server = FakeServer();
      final run = AppRun(server, MemoryPendingOperationStore());
      await run.signedIn();
      await run.receive(n: 1);
      await run.receive(n: 1); // same content, but a deliberate second action
      expect(server.performed, hasLength(2));
      final keys = server.requestHeaders
          .map((h) => h['Idempotency-Key'])
          .whereType<String>()
          .toSet();
      expect(keys, hasLength(2));
    },
  );

  group(
    'PreferencesPendingOperationStore (survives a real restart of the storage)',
    () {
      PendingOperation op(String key, {String user = 'u-1'}) =>
          PendingOperation(
            key: key,
            action: 'demo',
            userId: user,
            businessId: 'b-1',
            path: path,
            body: {'n': 1, 'note': 'Täze Dükan'},
            createdAt: DateTime.utc(2026, 10, 6, 12),
            subject: 'Ýüpek',
          );

      test(
        'round-trips records, including Turkmen text, through a new instance',
        () async {
          SharedPreferences.setMockInitialValues({});
          final prefs = await SharedPreferences.getInstance();
          await PreferencesPendingOperationStore(prefs).upsert(op('k1'));

          final reopened = PreferencesPendingOperationStore(
            await SharedPreferences.getInstance(),
          );
          final loaded = await reopened.load();
          expect(loaded.single.key, 'k1');
          expect(loaded.single.body['note'], 'Täze Dükan');
          expect(loaded.single.subject, 'Ýüpek');
          expect(loaded.single.createdAt, DateTime.utc(2026, 10, 6, 12));
        },
      );

      test('simultaneous writes never lose a record', () async {
        SharedPreferences.setMockInitialValues({});
        final store = PreferencesPendingOperationStore(
          await SharedPreferences.getInstance(),
        );
        await Future.wait([
          for (var i = 0; i < 20; i++) store.upsert(op('k$i')),
        ]);
        expect(await store.load(), hasLength(20));
        await Future.wait([
          for (var i = 0; i < 20; i += 2) store.remove('k$i'),
        ]);
        expect((await store.load()).map((o) => o.key).toSet(), {
          for (var i = 1; i < 20; i += 2) 'k$i',
        });
      });

      test('upsert replaces a record with the same key', () async {
        SharedPreferences.setMockInitialValues({});
        final store = PreferencesPendingOperationStore(
          await SharedPreferences.getInstance(),
        );
        await store.upsert(op('k1'));
        await store.upsert(op('k1').withState(PendingState.notFound));
        final loaded = await store.load();
        expect(loaded, hasLength(1));
        expect(loaded.single.state, PendingState.notFound);
      });

      test(
        'unreadable stored data is ignored rather than crashing the app',
        () async {
          SharedPreferences.setMockInitialValues({
            'pending_operations_v1': '{broken',
          });
          final store = PreferencesPendingOperationStore(
            await SharedPreferences.getInstance(),
          );
          expect(await store.load(), isEmpty);
          await store.upsert(op('k1'));
          expect(await store.load(), hasLength(1));
        },
      );
    },
  );
}
