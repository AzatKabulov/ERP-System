/// Native camera resources are released by MobileScannerController.stop().
class ScannerStreams {
  Future<void> duringStart(Future<void> Function() start) => start();
  void stop() {}
}
