import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'continuous_scan_screen.dart';
import 'scan_screen.dart';
import 'photo_scan_screen.dart';

/// Reads a barcode with the device camera. A scan only ever **returns a code**:
/// it never submits a form, completes a sale or moves stock. The screen that asked
/// decides what to do with the code (fill a field, look a product up).
abstract class BarcodeScanner {
  /// Whether a scanning workflow can be offered (live camera or browser photo).
  /// Permission denial and missing hardware are handled by the scan screen.
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

/// Browsers require HTTPS or a loopback origin for camera access. This only
/// checks the origin; the camera screen handles permission and hardware errors.
bool cameraScanningAvailable({bool isWeb = kIsWeb, Uri? origin}) {
  if (!isWeb) return true;
  final address = origin ?? Uri.base;
  if (address.scheme == 'https') return true;
  if (address.scheme != 'http') return false;
  final host = address.host;
  final octets = host.split('.').map(int.tryParse).toList();
  final loopbackIpv4 =
      octets.length == 4 &&
      octets.every((n) => n != null && n >= 0 && n <= 255) &&
      octets.first == 127;
  return host == 'localhost' ||
      host == '[::1]' ||
      host == '::1' ||
      loopbackIpv4;
}

/// Tablet cameras and browser webcams share the same scan screen.
class CameraBarcodeScanner implements BarcodeScanner {
  const CameraBarcodeScanner();

  @override
  bool get isAvailable => true;

  @override
  Future<String?> scan(BuildContext context) =>
      Navigator.of(context).push<String>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => kIsWeb && !cameraScanningAvailable()
              ? const PhotoScanScreen()
              : const ScanScreen(),
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
      builder: (_) => kIsWeb && !cameraScanningAvailable()
          ? PhotoScanScreen(onCode: onCode, changes: changes, status: status)
          : ContinuousScanScreen(
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
