import 'dart:js_interop';

@JS('erpSetScheme')
external void _setScheme(bool dark);

@JS('erpSafeTop')
external double _safeTop();

@JS('erpSafeBottom')
external double _safeBottom();

/// Calls the page's own `erpSetScheme` (see web/index.html).
void syncBrowserChrome({required bool dark}) {
  try {
    _setScheme(dark);
  } on Object {
    // an old page without the function: nothing to do
  }
}

/// The phone's own top and bottom areas, read from the page (`env(safe-area-inset-*)`).
({double top, double bottom}) safeAreaInsets() {
  try {
    return (top: _safeTop(), bottom: _safeBottom());
  } on Object {
    return (top: 0, bottom: 0);
  }
}
