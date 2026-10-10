import 'package:erp_system/features/scanning/barcode_scanner.dart';
import 'package:flutter/widgets.dart';

/// Stands in for the camera: hands back whatever the test queued, or null (the
/// person closed the camera). Counts how often it was opened.
class FakeScanner implements BarcodeScanner {
  FakeScanner({this.available = true, List<String?> results = const []})
    : _results = [...results];

  final bool available;
  final List<String?> _results;
  int opened = 0;

  /// Codes the continuous camera "sees", one per item shown to it, handed over in order each
  /// time it is opened.
  final List<String> continuous = [];

  void queue(String? code) => _results.add(code);

  @override
  bool get isAvailable => available;

  @override
  Future<String?> scan(BuildContext context) async {
    opened++;
    return _results.isEmpty ? null : _results.removeAt(0);
  }

  @override
  Future<void> scanContinuously(
    BuildContext context, {
    required ValueChanged<String> onCode,
    Listenable? changes,
    WidgetBuilder? status,
  }) async {
    opened++;
    for (final code in continuous) {
      onCode(code);
    }
    continuous.clear();
  }
}
