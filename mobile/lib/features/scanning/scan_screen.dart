import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../widgets/common.dart';

/// Full-screen camera view. Returns the first code it reads. If the camera cannot
/// be used it explains why and offers to type the code instead.
class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  // Retail barcodes plus QR; reading fewer formats is faster and avoids false reads.
  final _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const [
      BarcodeFormat.ean13,
      BarcodeFormat.ean8,
      BarcodeFormat.upcA,
      BarcodeFormat.upcE,
      BarcodeFormat.code128,
      BarcodeFormat.code39,
      BarcodeFormat.itf14,
      BarcodeFormat.qrCode,
    ],
  );
  bool _done = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_done) return; // one result, however many frames contain the code
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue?.trim();
      if (value != null && value.isNotEmpty) {
        _done = true;
        HapticFeedback.mediumImpact();
        Navigator.of(context).pop(value);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = strings(context);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(l.scanTitle, style: const TextStyle(fontSize: 16)),
        actions: [
          IconButton(
            key: const ValueKey('scan-torch'),
            tooltip: l.scanTorch,
            icon: const Icon(Icons.flashlight_on_outlined),
            onPressed: () => _controller.toggleTorch(),
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error) => ScanErrorPanel(
              denied:
                  error.errorCode == MobileScannerErrorCode.permissionDenied,
              onManual: () => Navigator.of(context).pop(),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 24,
            child: Center(
              child: FilledButton.tonalIcon(
                key: const ValueKey('scan-manual'),
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.keyboard_outlined),
                label: Text(l.enterManually),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shown instead of the camera when it cannot be used. Typing the code is always an
/// alternative, so the person is never stuck.
class ScanErrorPanel extends StatelessWidget {
  const ScanErrorPanel({
    super.key,
    required this.denied,
    required this.onManual,
  });

  final bool denied;
  final VoidCallback onManual;

  @override
  Widget build(BuildContext context) {
    final l = strings(context);
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.no_photography_outlined,
                color: Colors.white70,
                size: 40,
              ),
              const SizedBox(height: 16),
              Text(
                key: const ValueKey('scan-error'),
                denied ? l.cameraDenied : l.cameraUnavailable,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, height: 1.5),
              ),
              const SizedBox(height: 20),
              GradientButton(
                key: const ValueKey('scan-error-manual'),
                label: l.enterManually,
                icon: Icons.keyboard_outlined,
                onPressed: onManual,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
