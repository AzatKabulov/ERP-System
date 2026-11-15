import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

@JS('document.createElement')
external _Script _createElement(String tag);
@JS('document.head.appendChild')
external void _append(_Script script);
@JS('erpReadLabelText')
external JSPromise<JSString> _read(JSUint8Array bytes);
extension type _Script(JSObject _) implements JSObject {
  external set src(String value);
  external set onload(JSFunction value);
  external set onerror(JSFunction value);
  external void remove();
}
Future<void>? _loading;
Future<void> _load() => _loading ??= (() async {
  final done = Completer<void>();
  final script = _createElement('script');
  script.src = Uri.base.resolve('scanner/label_reader.js').toString();
  script.onload = ((JSAny? _) {
    if (!done.isCompleted) done.complete();
  }).toJS;
  script.onerror = ((JSAny? _) {
    if (!done.isCompleted) done.completeError(StateError('OCR unavailable'));
  }).toJS;
  _append(script);
  try {
    await done.future.timeout(const Duration(seconds: 20));
  } catch (_) {
    script.remove();
    _loading = null;
    rethrow;
  }
})();
Future<String> readLabelText(Uint8List bytes) async {
  if (bytes.isEmpty || bytes.length > 12 * 1024 * 1024) {
    throw StateError('Invalid photo size');
  }
  await _load();
  return (await _read(
    bytes.toJS,
  ).toDart.timeout(const Duration(seconds: 50))).toDart;
}
