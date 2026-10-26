import 'dart:async';
import 'package:flutter/material.dart';
import '../../widgets/app_icons.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../widgets/common.dart';
import 'scanner_session.dart';
import 'scan_screen.dart' show ScanErrorPanel;

/// Full-screen camera that stays open while a box is counted in. Each item shown to the camera
/// is passed to [onCode] once: a code is counted again only after nothing was read for a moment
/// (the item was taken away and the next one brought), and when a label carries several codes at
/// once the ordinary barcode wins over a QR code, so one item is never counted twice.
class ContinuousScanScreen extends StatefulWidget {
  const ContinuousScanScreen({
    super.key,
    required this.onCode,
    this.changes,
    this.status,
  });

  final ValueChanged<String> onCode;
  final Listenable? changes;
  final WidgetBuilder? status;

  @override
  State<ContinuousScanScreen> createState() => _ContinuousScanScreenState();
}

class _ContinuousScanScreenState extends State<ContinuousScanScreen> {
  /// How long the picture must stay empty before the next read counts as a new item.
  static const _gap = Duration(milliseconds: 700);

  final _controller = MobileScannerController(
    autoStart: false,
    detectionSpeed: DetectionSpeed.normal,
    detectionTimeoutMs: 250,
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
  DateTime? _lastSeen;

  late final _session = ScannerSession(_controller);
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_closing) unawaited(_session.start());
    });
  }

  void _close([String? code]) {
    if (_closing) return;
    _closing = true;
    unawaited(_session.close());
    Navigator.of(context).pop(code);
  }

  @override
  void dispose() {
    unawaited(_session.close());
    super.dispose();
  }

  static int _rank(BarcodeFormat format) =>
      format == BarcodeFormat.qrCode ? 1 : 0;

  void _onDetect(BarcodeCapture capture) {
    if (_closing) return;
    final seen = [
      for (final b in capture.barcodes)
        if ((b.rawValue ?? '').trim().isNotEmpty) b,
    ];
    if (seen.isEmpty) return;
    final now = DateTime.now();
    final fresh = _lastSeen == null || now.difference(_lastSeen!) > _gap;
    _lastSeen = now; // an item that stays in view keeps the same "visit" going
    if (!fresh) return;
    seen.sort((a, b) => _rank(a.format).compareTo(_rank(b.format)));
    HapticFeedback.mediumImpact();
    SystemSound.play(SystemSoundType.click);
    widget.onCode(seen.first.rawValue!.trim());
  }

  @override
  Widget build(BuildContext context) {
    final l = strings(context);
    return PopScope(
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          _closing = true;
          unawaited(_session.close());
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          leading: BackButton(onPressed: () => _close()),
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          title: Text(
            l.intakeCameraTitle,
            style: const TextStyle(fontSize: 16),
          ),
          actions: [
            ValueListenableBuilder(
              valueListenable: _controller,
              builder: (context, state, _) {
                if (state.torchState == TorchState.unavailable) {
                  return const SizedBox.shrink();
                }
                return IconButton(
                  key: const ValueKey('scan-torch'),
                  tooltip: l.scanTorch,
                  icon: const AppIcon(AppIcons.flash),
                  onPressed: () => _controller.toggleTorch(),
                );
              },
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
                onManual: () => _close(),
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 24,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (widget.status != null)
                    ListenableBuilder(
                      listenable: widget.changes ?? ValueNotifier<int>(0),
                      builder: (context, _) => DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.72),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: DefaultTextStyle.merge(
                            style: const TextStyle(color: Colors.white),
                            child: widget.status!(context),
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    key: const ValueKey('scan-done'),
                    onPressed: () => _close(),
                    icon: const AppIcon(AppIcons.check),
                    label: Text(l.intakeCameraDone),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
