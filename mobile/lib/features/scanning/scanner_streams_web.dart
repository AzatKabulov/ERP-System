import 'dart:js_interop';

@JS('navigator.mediaDevices')
external _Devices? get _devices;

extension type _Devices(JSObject _) implements JSObject {
  external JSFunction get getUserMedia;
  external set getUserMedia(JSFunction function);
}

extension type _Stream(JSObject _) implements JSObject {
  external JSArray<_Track> getTracks();
}

extension type _Track(JSObject _) implements JSObject {
  external void stop();
}

extension type _MediaPromise(JSObject _) implements JSObject {
  external JSPromise<JSObject> then(JSFunction onFulfilled);
}

/// mobile_scanner 7.4.2's polling web readers drop their MediaStream reference
/// without stopping its tracks. Retain ONLY streams requested during this
/// serialized scanner startup; detached video nodes are not a cleanup boundary.
/// Restore the browser method immediately after startup. Other tabs and streams
/// acquired outside that interval are never touched.
class ScannerStreams {
  final _streams = <_Stream>[];

  Future<void> duringStart(Future<void> Function() start) async {
    final devices = _devices;
    if (devices == null) return start();
    final original = devices.getUserMedia;
    devices.getUserMedia = ((JSObject constraints) {
      final result =
          original.callAsFunction(devices, constraints) as JSPromise<JSObject>;
      // Keep rejection in JavaScript: a Future round-trip wraps DOMException
      // and hides its NotAllowedError name from the scanner's permission mapper.
      return _MediaPromise(result).then(
        ((JSObject stream) {
          _streams.add(_Stream(stream));
          return stream;
        }).toJS,
      );
    }).toJS;
    try {
      await start();
    } finally {
      devices.getUserMedia = original;
    }
  }

  void stop() {
    for (final stream in _streams) {
      for (final track in stream.getTracks().toDart) {
        track.stop();
      }
    }
    _streams.clear();
  }
}
