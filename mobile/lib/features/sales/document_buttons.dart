import 'package:flutter/material.dart';

import '../../widgets/common.dart';
import 'document_actions.dart';
import 'sales_models.dart';
import 'sales_repository.dart';

/// Print or share the receipt of one sale. The PDF is made by the server (permission-checked,
/// fonts embedded, in the business's document language); the device's own dialogs print or
/// share it.
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
  bool _busy = false;

  Future<void> _run(bool print) async {
    if (_busy) return;
    final l = strings(context);
    final actions = DocumentsScope.of(context);
    setState(() => _busy = true);
    try {
      final bytes = await widget.repository.receipt(widget.saleId);
      final name = 'receipt-${saleNumber(widget.saleNumber)}';
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

  @override
  Widget build(BuildContext context) {
    final l = strings(context);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        OutlinedButton.icon(
          key: const ValueKey('doc-receipt-print'),
          onPressed: _busy ? null : () => _run(true),
          icon: const Icon(Icons.print_outlined),
          label: Text('${l.receiptAction} · ${l.printAction}'),
        ),
        OutlinedButton.icon(
          key: const ValueKey('doc-receipt-share'),
          onPressed: _busy ? null : () => _run(false),
          icon: const Icon(Icons.ios_share_outlined),
          label: Text('${l.receiptAction} · ${l.shareAction}'),
        ),
        if (_busy)
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
      ],
    );
  }
}
