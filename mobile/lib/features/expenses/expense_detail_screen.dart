import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/api/api_error_text.dart';
import '../../core/api/api_exception.dart';
import '../../core/files/file_services.dart';
import '../../core/format/format_stamp.dart';
import '../../core/money/decimal_math.dart';
import '../../core/session/session_controller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../shared/async_section.dart';
import '../workspace/unsaved_work.dart';
import 'expense_form_screen.dart';
import 'expenses_models.dart';
import 'expenses_repository.dart';

/// One expense with its receipt (a photo is shown, a PDF can be shared), and for owners and
/// managers: change it, or void it with a reason (an expense is never deleted).
class ExpenseDetailScreen extends StatefulWidget {
  const ExpenseDetailScreen({
    super.key,
    required this.expenseId,
    required this.session,
    required this.repository,
    required this.unsaved,
  });

  final String expenseId;
  final SessionController session;
  final ExpensesRepository repository;
  final UnsavedWork unsaved;

  @override
  State<ExpenseDetailScreen> createState() => _ExpenseDetailScreenState();
}

class _ExpenseDetailScreenState extends State<ExpenseDetailScreen> {
  final _section = GlobalKey<AsyncSectionState<Expense>>();
  bool _changed = false;
  bool _busy = false;
  Future<Uint8List>? _receipt;
  String? _receiptOf;

  bool get _canManage => widget.session.can('expense.manage');

  Future<void> _edit(Expense e) async {
    final saved = await Navigator.of(context).push<Expense>(
      MaterialPageRoute(
        builder: (_) => ExpenseFormScreen(
          session: widget.session,
          repository: widget.repository,
          unsaved: widget.unsaved,
          existing: e,
        ),
      ),
    );
    if (saved != null && mounted) {
      _changed = true;
      showFeedback(context, strings(context).expenseSaved);
      _receiptOf = null;
      _section.currentState?.reload();
    }
  }

  Future<void> _void(Expense e) async {
    final l = strings(context);
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => DialogInput(
        builder: (context, controller) => StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            title: Text(l.expenseVoidTitle),
            content: TextField(
              key: const ValueKey('ed-void-reason'),
              controller: controller,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(labelText: l.expenseVoidReason),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(l.cancel),
              ),
              FilledButton(
                key: const ValueKey('ed-void-confirm'),
                onPressed: controller.text.trim().isEmpty
                    ? null
                    : () => Navigator.pop(context, controller.text.trim()),
                child: Text(l.confirm),
              ),
            ],
          ),
        ),
      ),
    );
    if (reason == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.repository.voidExpense(e.id, reason);
      if (!mounted) return;
      _changed = true;
      showFeedback(context, l.expenseVoided);
      _section.currentState?.reload();
    } on ApiException catch (err) {
      if (mounted) showFeedback(context, apiErrorText(l, err));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _shareReceipt(AttachmentRef a, Uint8List bytes) =>
      FilesScope.sharingOf(context).share(bytes, a.name, a.contentType);

  @override
  Widget build(BuildContext context) {
    final l = strings(context);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_changed);
      },
      child: Scaffold(
        appBar: AppBar(title: Text(l.expenseDetailTitle)),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: AsyncSection<Expense>(
                  key: _section,
                  load: () => widget.repository.expense(widget.expenseId),
                  builder: (context, e) => _body(context, e),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, Expense e) {
    final l = strings(context);
    final attachment = e.attachment;
    if (attachment != null && _receiptOf != attachment.id) {
      _receiptOf = attachment.id;
      _receipt = widget.repository.attachmentBytes(attachment.id);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                formatMoney(e.amountMinor, 'TMT'),
                key: const ValueKey('ed-amount'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              Text('${e.categoryName} · ${e.spentOn}'),
              Text(
                e.locationName,
                style: const TextStyle(color: AppColors.muted),
              ),
              if (e.description.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(e.description),
              ],
              const SizedBox(height: 8),
              Text(
                '${formatStamp(e.createdAt)} · ${e.createdBy}',
                style: const TextStyle(color: AppColors.muted, fontSize: 12),
              ),
              if (e.voided) ...[
                const SizedBox(height: 8),
                Text(
                  '${l.expenseVoidedBadge}: ${e.voidReason}',
                  key: const ValueKey('ed-voided'),
                  style: const TextStyle(color: AppColors.danger),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionHeading(l.expenseReceipt),
              const SizedBox(height: 8),
              if (attachment == null)
                Text(
                  l.expenseReceiptNone,
                  key: const ValueKey('ed-no-receipt'),
                  style: const TextStyle(color: AppColors.muted),
                )
              else
                FutureBuilder<Uint8List>(
                  future: _receipt,
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return Text(
                        l.expenseReceiptLoadFailed,
                        key: const ValueKey('ed-receipt-failed'),
                        style: const TextStyle(color: AppColors.danger),
                      );
                    }
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (attachment.isImage)
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 360),
                            child: Image.memory(
                              snapshot.data!,
                              key: const ValueKey('ed-receipt-image'),
                              fit: BoxFit.contain,
                              errorBuilder: (_, _, _) =>
                                  Text(l.expenseReceiptLoadFailed),
                            ),
                          ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          key: const ValueKey('ed-share-receipt'),
                          onPressed: () =>
                              _shareReceipt(attachment, snapshot.data!),
                          icon: const Icon(Icons.ios_share),
                          label: Text(
                            '${l.expenseOpenReceipt}: ${attachment.name}',
                          ),
                        ),
                      ],
                    );
                  },
                ),
            ],
          ),
        ),
        if (_canManage && !e.voided) ...[
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              GradientButton(
                key: const ValueKey('ed-edit'),
                label: l.expenseEdit,
                icon: Icons.edit_outlined,
                onPressed: _busy ? null : () => _edit(e),
              ),
              OutlinedButton.icon(
                key: const ValueKey('ed-void'),
                onPressed: _busy ? null : () => _void(e),
                icon: const Icon(Icons.block),
                label: Text(l.expenseVoid),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
