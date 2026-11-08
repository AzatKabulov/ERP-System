void syncBrowserChrome({required bool dark}) {}

bool fullScreenMode() => false;

({double top, double right, double bottom, double left}) browserSafeAreas() =>
    (top: 0, right: 0, bottom: 0, left: 0);

void Function() observeBrowserViewport(void Function() onChanged) => () {};
