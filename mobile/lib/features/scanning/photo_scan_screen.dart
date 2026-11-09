import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/files/file_services.dart';
import '../../widgets/app_icons.dart';
import '../../widgets/common.dart';
import 'barcode_photo_decoder.dart';

/// On HTTP a browser cannot stream video, but can offer its own photo capture.
/// Images are decoded locally; only a selected code is returned to the caller.
class PhotoScanScreen extends StatefulWidget {
  const PhotoScanScreen({
    super.key,
    this.decode = decodeBarcodePhoto,
    this.onCode,
    this.changes,
    this.status,
  });

  final Future<List<String>> Function(Uint8List bytes) decode;
  final ValueChanged<String>? onCode;
  final Listenable? changes;
  final WidgetBuilder? status;

  @override
  State<PhotoScanScreen> createState() => _PhotoScanScreenState();
}

class _PhotoScanScreenState extends State<PhotoScanScreen> {
  bool _busy = false;
  String? _error;
  String? _lastCode;
  List<String> _choices = const [];

  void _selected(String code) {
    if (widget.onCode == null) {
      Navigator.of(context).pop(code);
    } else {
      widget.onCode!(code);
      setState(() {
        _lastCode = code;
        _choices = const [];
      });
    }
  }

  Future<void> _pick({required bool camera}) async {
    if (_busy) return;
    final l = strings(context);
    final picker = FilesScope.pickingOf(context);
    setState(() {
      _busy = true;
      _error = null;
      _choices = const [];
    });
    try {
      final photo = await picker.pickPhoto(camera: camera);
      if (photo == null || !mounted) return;
      if (photo.bytes.isEmpty || photo.bytes.length > 12 * 1024 * 1024) {
        setState(() => _error = l.photoScanFailed);
        return;
      }
      final codes = (await widget.decode(photo.bytes))
          .map((c) => c.trim())
          .where((c) => c.isNotEmpty && c.length <= 64)
          .toSet()
          .toList();
      if (!mounted) return;
      if (codes.length == 1) {
        _selected(codes.single);
      } else {
        setState(() {
          _choices = codes;
          _error = codes.isEmpty ? l.photoScanNotFound : null;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = l.photoScanFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = strings(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.scanTitle)),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text(l.photoScanHint),
                const SizedBox(height: 24),
                PrimaryButton(
                  key: const ValueKey('photo-scan-camera'),
                  label: l.photoScanTake,
                  icon: AppIcons.scan,
                  onPressed: _busy ? null : () => _pick(camera: true),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  key: const ValueKey('photo-scan-gallery'),
                  onPressed: _busy ? null : () => _pick(camera: false),
                  icon: const AppIcon(AppIcons.image),
                  label: Text(l.photoScanChoose),
                ),
                if (_busy) ...[
                  const SizedBox(height: 24),
                  const Center(child: CircularProgressIndicator()),
                  const SizedBox(height: 12),
                  Text(l.photoScanReading, textAlign: TextAlign.center),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 20),
                  Text(_error!, key: const ValueKey('photo-scan-error')),
                ],
                if (_choices.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Text(l.photoScanMultiple),
                  for (final code in _choices)
                    OutlinedButton(
                      onPressed: () => _selected(code),
                      child: Text(code),
                    ),
                ],
                if (_lastCode != null) Text(l.scannedCode(_lastCode!)),
                if (widget.status != null)
                  widget.changes == null
                      ? widget.status!(context)
                      : ListenableBuilder(
                          listenable: widget.changes!,
                          builder: (context, _) => widget.status!(context),
                        ),
                const SizedBox(height: 20),
                TextButton.icon(
                  key: const ValueKey('photo-scan-manual'),
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const AppIcon(AppIcons.keyboard),
                  label: Text(l.enterManually),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
