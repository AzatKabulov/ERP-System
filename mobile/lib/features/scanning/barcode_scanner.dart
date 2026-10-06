import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

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
