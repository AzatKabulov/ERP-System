import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import 'document_actions.dart';
import 'sales_models.dart';
import 'sales_repository.dart';

/// Print or share the receipt or the invoice of one sale, in a chosen language. The PDF is
/// made by the server (permission-checked, fonts embedded); the device's own dialogs print
/// or share it.
class DocumentButtons extends StatefulWidget {
  const DocumentButtons({
    super.key,
    required this.repository,
    required this.saleId,
    required this.saleNumber,
  });

  final SalesRepository repository;
  final String saleId;
  final int saleNumber;

  @override
  State<DocumentButtons> createState() => _DocumentButtonsState();
}

class _DocumentButtonsState extends State<DocumentButtons> {
  String? _lang; // null = the business's document language
  bool _busy = false;

  Future<void> _run(String kind, bool print) async {
    if (_busy) return;
    final l = strings(context);
    final actions = DocumentsScope.of(context);
    setState(() => _busy = true);
    try {
      final bytes = await widget.repository.document(
        widget.saleId,
        kind: kind,
        lang: _lang,
      );
      final name = '$kind-${saleNumber(widget.saleNumber)}';
      if (print) {
        await actions.printDocument(bytes, name);
      } else {
        await actions.shareDocument(bytes, name);
      }
    } catch (_) {
      if (mounted) showFeedback(context, l.documentFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _row(String kind, String label) {
    final l = strings(context);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 110,
          child: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        OutlinedButton.icon(
          key: ValueKey('doc-$kind-print'),
          onPressed: _busy ? null : () => _run(kind, true),
          icon: const Icon(Icons.print_outlined),
          label: Text(l.printAction),
        ),
        OutlinedButton.icon(
          key: ValueKey('doc-$kind-share'),
          onPressed: _busy ? null : () => _run(kind, false),
          icon: const Icon(Icons.ios_share_outlined),
          label: Text(l.shareAction),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = strings(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              l.documentLanguage,
              style: const TextStyle(color: AppColors.muted, fontSize: 13),
            ),
            SegmentedButton<String>(
              key: const ValueKey('doc-lang'),
              showSelectedIcon: false,
              segments: [
                ButtonSegment(
                  value: 'auto',
                  label: Text(
                    l.documentLangAuto,
                    key: const ValueKey('doc-lang-auto'),
                  ),
                ),
                ButtonSegment(
                  value: 'ru',
                  label: Text(
                    l.languageRussian,
                    key: const ValueKey('doc-lang-ru'),
                  ),
                ),
                ButtonSegment(
                  value: 'tk',
                  label: Text(
                    l.languageTurkmen,
                    key: const ValueKey('doc-lang-tk'),
                  ),
                ),
              ],
              selected: {_lang ?? 'auto'},
              onSelectionChanged: (s) =>
                  setState(() => _lang = s.first == 'auto' ? null : s.first),
            ),
            if (_busy)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
          ],
        ),
        const SizedBox(height: 12),
        _row('receipt', l.receiptAction),
        const SizedBox(height: 8),
        _row('invoice', l.invoiceAction),
      ],
    );
  }
}
