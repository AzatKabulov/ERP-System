import 'dart:js_interop';

@JS('erpSetScheme')
external void _setScheme(bool dark);

/// Calls the page's own `erpSetScheme` (see web/index.html).
void syncBrowserChrome({required bool dark}) {
  try {
    _setScheme(dark);
  } on Object {
    // an old page without the function: nothing to do
  }
}
