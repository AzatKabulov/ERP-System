import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../../widgets/app_icons.dart';

import '../../theme/app_theme.dart';
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
    this.focusNode,
    this.keepFocusOnSubmit = false,
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

  /// Lets the screen keep the field focused after a code was submitted, so a hand scanner (which
  /// types the code and presses Enter) can read the next item straight away.
  final FocusNode? focusNode;

  /// By default Enter closes the keyboard and leaves the field. A hand scanner presses Enter after
  /// every code, so a screen that expects several scans in a row keeps the field focused instead
  /// (not in the browser build, which blurs the field itself).
  final bool keepFocusOnSubmit;

  @override
  Widget build(BuildContext context) {
    final l = strings(context);
    final scanner = ScannerScope.of(context);
    // Its own semantics container: without it a text field next to plain texts can absorb
    // them into one node, and a screen reader then reads the whole page as the field's name.
    return Semantics(
      container: true,
      explicitChildNodes: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Semantics(
              label: label,
              child: TextField(
                key: fieldKey,
                controller: controller,
                focusNode: focusNode,
                enabled: enabled,
                autocorrect: false,
                enableSuggestions: false,
                onSubmitted: onSubmitted,
                onEditingComplete: keepFocusOnSubmit && !kIsWeb ? () {} : null,
                onChanged: onChanged,
                decoration: InputDecoration(
                  // The label is the placeholder (the design's search field) and, through the
                  // Semantics wrapper, the field's accessible name.
                  hint: ExcludeSemantics(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        color: AppColors.muted,
                      ),
                    ),
                  ),
                  prefixIcon: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 14),
                    child: AppIcon(AppIcons.search, size: 20),
                  ),
                  prefixIconConstraints: const BoxConstraints(minWidth: 48),
                  errorText: errorText,
                  errorMaxLines: 3,
                ),
              ),
            ),
          ),
          if (scanner.isAvailable) ...[
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(top: 0),
              child: Semantics(
                container: true,
                button: true,
                enabled: enabled,
                label: l.scanWithCamera,
                child: Tooltip(
                  message: l.scanWithCamera,
                  excludeFromSemantics: true,
                  child: Material(
                    color: AppColors.blue,
                    borderRadius: BorderRadius.circular(AppRadius.control),
                    child: InkWell(
                      key: const ValueKey('scan-button'),
                      borderRadius: BorderRadius.circular(AppRadius.control),
                      hoverColor: AppColors.blueDark,
                      onTap: enabled
                          ? () async {
                              final code = await scanner.scan(context);
                              if (code == null || !context.mounted) return;
                              controller.text = code;
                              onChanged?.call(code);
                              onScanned?.call(code);
                            }
                          : null,
                      child: const SizedBox(
                        width: 48,
                        height: 48,
                        child: Center(
                          child: AppIcon(
                            AppIcons.scan,
                            size: 20,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
