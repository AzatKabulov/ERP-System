void syncBrowserChrome({required bool dark}) {}

/// How far the phone's own areas (the clock and camera at the top, the home bar at the bottom)
/// reach into the page, in logical pixels. Zero outside a phone's full-screen web app.
({double top, double bottom}) safeAreaInsets() => (top: 0, bottom: 0);

/// True only in the full-screen test copy of the web app.
bool fullScreenMode() => false;
