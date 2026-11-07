// Tells the browser which colour the app has at the top and behind it (the status bar of a phone,
// the page background), so the app looks like one full-screen surface. A no-op outside the web.
export 'web_chrome_stub.dart'
    if (dart.library.js_interop) 'web_chrome_web.dart';
