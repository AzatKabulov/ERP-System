import 'package:flutter/material.dart';

import '../../widgets/common.dart';
import 'barcode_scanner.dart';

/// A text field for a barcode, with a camera button beside it. Typing is always
/// possible, so the camera is a convenience and never a requirement. A scan only
/// fills the field and calls [onScanned]; it never submits anything by itself.
class BarcodeInput extends StatelessWidget {
  const BarcodeInput({
    super.key,
    required this.controller,
    required this.label,
    this.onScanned,
    this.onSubmitted,
    this.onChanged,
    this.enabled = true,
    this.fieldKey,
    this.errorText,
  });

  final TextEditingController controller;
  final String label;

  /// Called after the camera read a code (the field already shows it).
  final ValueChanged<String>? onScanned;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final bool enabled;
  final Key? fieldKey;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final l = strings(context);
    final scanner = ScannerScope.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: TextField(
            key: fieldKey,
            controller: controller,
            enabled: enabled,
            autocorrect: false,
            enableSuggestions: false,
            onSubmitted: onSubmitted,
            onChanged: onChanged,
            decoration: InputDecoration(
              labelText: label,
              prefixIcon: const Icon(Icons.qr_code_2),
              errorText: errorText,
              errorMaxLines: 3,
            ),
          ),
        ),
        if (scanner.isAvailable) ...[
          const SizedBox(width: 8),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: IconButton.filledTonal(
              key: const ValueKey('scan-button'),
              tooltip: l.scanWithCamera,
              iconSize: 28,
              constraints: const BoxConstraints(minWidth: 52, minHeight: 52),
              onPressed: enabled
                  ? () async {
                      final code = await scanner.scan(context);
                      if (code == null || !context.mounted) return;
                      controller.text = code;
                      onChanged?.call(code);
                      onScanned?.call(code);
                    }
                  : null,
              icon: const Icon(Icons.qr_code_scanner),
            ),
          ),
        ],
      ],
    );
  }
}
