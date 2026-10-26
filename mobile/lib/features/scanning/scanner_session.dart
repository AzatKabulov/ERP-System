import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'scanner_streams.dart';

/// Serializes camera ownership, including permission/decoder startup that finishes
/// after the scanner route has already closed. Controllers use autoStart: false.
class ScannerSession with WidgetsBindingObserver {
  ScannerSession(this.controller) {
    if (kIsWeb) {
      // Keep auto selection (browser detector where available, WASM otherwise),
      // but never make the fallback depend on an external CDN loading.
      MobileScannerPlatform.instance.setBarcodeLibraryScriptUrl(
        Uri.base.resolve('scanner/zxing-wasm-3.1.3/reader.js').toString(),
      );
    }
    WidgetsBinding.instance.addObserver(this);
  }

  final MobileScannerController controller;
  final _streams = ScannerStreams();
  static Future<void> _tail = Future<void>.value();
  bool _closed = false;
  bool _foreground = true;
  Future<void>? _closing;

  Future<void> _enqueue(Future<void> Function() action) {
    _tail = _tail.then((_) => action()).catchError((
      Object error,
      StackTrace stack,
    ) {
      FlutterError.reportError(
        FlutterErrorDetails(exception: error, stack: stack),
      );
    });
    return _tail;
  }

  Future<void> start() => _enqueue(() async {
    if (_closed || !_foreground) return;
    await _streams.duringStart(controller.start);
    if (_closed || !_foreground) await _stop();
  });

  Future<void> _stop() async {
    _streams.stop();
    await controller.stop();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_closed) return;
    _foreground = state == AppLifecycleState.resumed;
    unawaited(_foreground ? start() : _enqueue(_stop));
  }

  Future<void> close() {
    _closed = true;
    WidgetsBinding.instance.removeObserver(this);
    return _closing ??= _enqueue(() async {
      try {
        await _stop();
      } finally {
        await controller.dispose();
      }
    });
  }
}
