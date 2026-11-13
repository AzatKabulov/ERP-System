import 'dart:js_interop';

@JS('window.erpPrepareConfirmationSound')
external void _prepare();
@JS('window.erpPlayConfirmationSound')
external void _play();
void prepare() {
  try {
    _prepare();
  } catch (_) {}
}

Future<void> play() async {
  try {
    _play();
  } catch (_) {}
}
