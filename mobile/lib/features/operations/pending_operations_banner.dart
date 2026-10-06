import 'package:flutter/material.dart';

import '../../core/format/format_stamp.dart';
import '../../core/operations/operation_runner.dart';
import '../../core/operations/pending_operation.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';

/// Names the stock-changing actions that can be left unconfirmed. Extended as
/// workflows are added; an unknown slug gets a neutral label, never raw text.
String operationActionLabel(AppLocalizations l, String action) =>
    switch (action) {
      'purchase_receive' => l.actionReceive,
      'stock_opening' => l.actionOpening,
      'stock_adjust' => l.actionAdjust,
      _ => l.unknownActionLabel,
    };

/// A notice that some actions have not been confirmed by the server, with a way
/// to review them. Shown on every page while any exist, because an unconfirmed
/// sale or delivery must never be forgotten silently.
class PendingOperationsBanner extends StatelessWidget {
  const PendingOperationsBanner({
    super.key,
    required this.runner,
    this.onResolved,
  });

  final OperationRunner runner;

  /// Called after operations were found completed, so screens can reload.
  final VoidCallback? onResolved;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: runner,
    builder: (context, _) {
      if (!runner.hasPending) return const SizedBox.shrink();
      final l = strings(context);
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        color: const Color(0xFFFFFBEB),
        child: Wrap(
          spacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Icon(Icons.hourglass_top, size: 18, color: AppColors.warning),
            Text(
              l.pendingBanner(runner.pending.length),
              key: const ValueKey('pending-banner'),
              style: const TextStyle(color: AppColors.warning, fontSize: 13),
            ),
            TextButton(
              key: const ValueKey('pending-review'),
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => PendingOperationsDialog(
                  runner: runner,
                  onResolved: onResolved,
                ),
              ),
              child: Text(l.pendingTitle),
            ),
          ],
        ),
      );
    },
  );
}

class PendingOperationsDialog extends StatefulWidget {
  const PendingOperationsDialog({
    super.key,
    required this.runner,
    this.onResolved,
  });
  final OperationRunner runner;
  final VoidCallback? onResolved;

  @override
  State<PendingOperationsDialog> createState() =>
      _PendingOperationsDialogState();
}

class _PendingOperationsDialogState extends State<PendingOperationsDialog> {
  bool _busy = false;
  String? _message;

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _check() => _run(() async {
    final done = await widget.runner.recover();
    if (done.isNotEmpty) {
      widget.onResolved?.call();
      if (mounted) setState(() => _message = strings(context).pendingResolved);
    }
  });

  Future<void> _retry(PendingOperation operation) => _run(() async {
    final outcome = await widget.runner.retry(operation.key);
    if (outcome is OperationCompleted) {
      widget.onResolved?.call();
      if (mounted) setState(() => _message = strings(context).pendingResolved);
    }
  });

  Future<void> _discard(PendingOperation operation) async {
    final l = strings(context);
    if (!await confirmAction(
          context,
          l.pendingDiscard,
          l.pendingDiscardConfirm,
        ) ||
        !mounted) {
      return;
    }
    await _run(() => widget.runner.discard(operation.key));
  }

  @override
  Widget build(BuildContext context) {
    final l = strings(context);
    return ListenableBuilder(
      listenable: widget.runner,
      builder: (context, _) {
        final pending = widget.runner.pending;
        return AlertDialog(
          title: Text(l.pendingTitle),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l.pendingExplain, style: const TextStyle(height: 1.4)),
                  if (_message != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _message!,
                      key: const ValueKey('pending-message'),
                      style: const TextStyle(color: AppColors.success),
                    ),
                  ],
                  const SizedBox(height: 12),
                  for (final op in pending)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: SurfaceCard(
                        padding: 14,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              [
                                operationActionLabel(l, op.action),
                                if (op.subject.isNotEmpty) op.subject,
                              ].join(' · '),
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${formatStamp(op.createdAt)} · ${_stateText(l, op.state)}',
                              style: const TextStyle(
                                color: AppColors.muted,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              children: [
                                OutlinedButton(
                                  key: ValueKey('pending-retry-${op.key}'),
                                  onPressed: _busy ? null : () => _retry(op),
                                  child: Text(l.pendingRetry),
                                ),
                                TextButton(
                                  key: ValueKey('pending-discard-${op.key}'),
                                  onPressed: _busy ? null : () => _discard(op),
                                  child: Text(l.pendingDiscard),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              key: const ValueKey('pending-check'),
              onPressed: _busy ? null : _check,
              child: Text(l.pendingCheck),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l.close),
            ),
          ],
        );
      },
    );
  }

  String _stateText(AppLocalizations l, PendingState state) => switch (state) {
    PendingState.sending => l.pendingStateSending,
    PendingState.unknown => l.pendingStateUnknown,
    PendingState.notFound => l.pendingStateNotFound,
  };
}
