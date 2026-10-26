import 'dart:async';

import 'package:erp_system/features/scanning/scanner_session.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class Camera extends MobileScannerController {
  Camera({this.startGate}) : super(autoStart: false);
  final Completer<void>? startGate;
  final calls = <String>[];
  bool running = false;

  @override
  Future<void> start({
    CameraFacing? cameraDirection,
    CameraLensType? cameraLensType,
  }) async {
    calls.add('start');
    await startGate?.future;
    running = true;
  }

  @override
  Future<void> stop() async {
    calls.add('stop');
    running = false;
  }

  @override
  // A recording fake: no platform session is allocated.
  // ignore: must_call_super
  Future<void> dispose() async {
    calls.add('dispose');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'closing during permission startup stops the late stream before disposal',
    () async {
      final gate = Completer<void>();
      final camera = Camera(startGate: gate);
      final session = ScannerSession(camera);
      final starting = session.start();
      await Future<void>.delayed(Duration.zero);
      final closing = session.close();
      expect(camera.calls, ['start']);
      gate.complete();
      await starting;
      await closing;
      expect(camera.running, false);
      expect(camera.calls.last, 'dispose');
      expect(
        camera.calls.indexOf('stop'),
        greaterThan(camera.calls.indexOf('start')),
      );
      final count = camera.calls.length;
      await session.close();
      await session.start();
      expect(camera.calls.length, count);
    },
  );

  test(
    'reopening waits for the previous owner to release the platform camera',
    () async {
      final gate = Completer<void>();
      final first = Camera(startGate: gate);
      final session = ScannerSession(first);
      final starting = session.start();
      await Future<void>.delayed(Duration.zero);
      final closing = session.close();
      final next = Camera();
      final second = ScannerSession(next);
      final opening = second.start();
      expect(next.calls, isEmpty);
      gate.complete();
      await starting;
      await closing;
      await opening;
      expect(first.running, false);
      expect(next.running, true);
      await second.close();
    },
  );

  test(
    'background stops the camera and resuming restarts only an open session',
    () async {
      final camera = Camera();
      final session = ScannerSession(camera);
      await session.start();
      session.didChangeAppLifecycleState(AppLifecycleState.hidden);
      await Future<void>.delayed(Duration.zero);
      expect(camera.running, false);
      session.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await Future<void>.delayed(Duration.zero);
      expect(camera.running, true);
      await session.close();
      session.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await Future<void>.delayed(Duration.zero);
      expect(camera.running, false);
    },
  );
}
