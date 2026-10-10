import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'continuous_scan_screen.dart';
import 'scan_screen.dart';

/// Reads a barcode with the device camera. A scan only ever **returns a code**:
/// it never submits a form, completes a sale or moves stock. The screen that asked
/// decides what to do with the code (fill a field, look a product up).
abstract class BarcodeScanner {
  /// False where the camera cannot be used (the browser build, which is a
  /// development preview). Manual entry always remains available.
  bool get isAvailable;

  /// Opens the camera and returns the first code read, or null when the person
  /// closed the camera or chose to type the code instead.
  Future<String?> scan(BuildContext context);

  /// Opens the camera and keeps it open: every item shown to it is passed to [onCode] once
  /// (the same code again only after the item has left the view), so a whole box can be counted
  /// without touching the screen. [status], rebuilt when [changes] fires, is drawn over the
  /// picture to show what the scans did. Returns when the person closes the camera.
  Future<void> scanContinuously(
    BuildContext context, {
    required ValueChanged<String> onCode,
    Listenable? changes,
    WidgetBuilder? status,
  });
}

/// The first supported scanning method (decision D9): the tablet camera.
class CameraBarcodeScanner implements BarcodeScanner {
  const CameraBarcodeScanner();

  @override
  bool get isAvailable => !kIsWeb;

  @override
  Future<String?> scan(BuildContext context) =>
      Navigator.of(context).push<String>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => const ScanScreen(),
        ),
      );

  @override
  Future<void> scanContinuously(
    BuildContext context, {
    required ValueChanged<String> onCode,
    Listenable? changes,
    WidgetBuilder? status,
  }) => Navigator.of(context).push<void>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => ContinuousScanScreen(
        onCode: onCode,
        changes: changes,
        status: status,
      ),
    ),
  );
}

/// Makes the scanner available to every screen, and replaceable in tests.
class ScannerScope extends InheritedWidget {
  const ScannerScope({super.key, required this.scanner, required super.child});

  final BarcodeScanner scanner;

  static BarcodeScanner of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ScannerScope>()?.scanner ??
      const CameraBarcodeScanner();

  @override
  bool updateShouldNotify(ScannerScope oldWidget) =>
      scanner != oldWidget.scanner;
}
