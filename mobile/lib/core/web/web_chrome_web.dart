import 'dart:js_interop';

@JS('erpSetScheme')
external void _setScheme(bool dark);

@JS('erpFullScreen')
external bool? get _fullScreen;
@JS('erpSafeTop')
external double _safeTop();
@JS('erpSafeRight')
external double _safeRight();
@JS('erpSafeBottom')
external double _safeBottom();
@JS('erpSafeLeft')
external double _safeLeft();
@JS('erpObserveViewport')
external void _observeViewport(JSFunction callback);
@JS('erpUnobserveViewport')
external void _unobserveViewport(JSFunction callback);

bool fullScreenMode() {
  try {
    return _fullScreen == true;
  } on Object {
    return false;
  }
}

({double top, double right, double bottom, double left}) browserSafeAreas() {
  try {
    if (fullScreenMode()) {
      return (
        top: _safeTop(),
        right: _safeRight(),
        bottom: _safeBottom(),
        left: _safeLeft(),
      );
    }
  } on Object {
    // A normal/older page has no fullscreen bridge.
  }
  return (top: 0, right: 0, bottom: 0, left: 0);
}

void Function() observeBrowserViewport(void Function() onChanged) {
  if (!fullScreenMode()) return () {};
  final callback = onChanged.toJS;
  try {
    _observeViewport(callback);
  } on Object {
    return () {};
  }
  return () {
    try {
      _unobserveViewport(callback);
    } on Object {
      // The document may already have gone away.
    }
  };
}

/// Calls the page's own `erpSetScheme` (see web/index.html).
void syncBrowserChrome({required bool dark}) {
  try {
    _setScheme(dark);
  } on Object {
    // an old page without the function: nothing to do
  }
}
