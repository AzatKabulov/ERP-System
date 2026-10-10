import 'package:flutter/material.dart';

import '../../core/api/api_error_text.dart';
import '../../core/connectivity/connection_monitor.dart';
import '../../core/format/format_stamp.dart';
import '../../core/money/decimal_math.dart';
import '../../core/operations/operation_runner.dart';
import '../../core/session/session_controller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../sales/sales_models.dart';
import '../shared/async_section.dart';
import '../workspace/unsaved_work.dart';
import 'returns_models.dart';
import 'returns_repository.dart';

/// One return: what came back, in which condition, and what was refunded. For goods that were
/// set aside "awaiting inspection", the owner or manager decides: sellable or damaged.
class ReturnDetailScreen extends StatefulWidget {
  const ReturnDetailScreen({
    super.key,
    required this.returnId,
    required this.session,
    required this.repository,
    required this.runner,
    required this.monitor,
    required this.unsaved,
  });

  final String returnId;
  final SessionController session;
  final ReturnsRepository repository;
  final OperationRunner runner;
  final ConnectionMonitor monitor;
  final UnsavedWork unsaved;

  @override
  State<ReturnDetailScreen> createState() => _ReturnDetailScreenState();
}

class _ReturnDetailScreenState extends State<ReturnDetailScreen> {
  final _section = GlobalKey<AsyncSectionState<SaleReturnDoc>>();
  bool _changed = false;
  bool _busy = false;

  SessionController get session => widget.session;

  bool _mayUse(String locationId) {
    final m = session.membership;
    return m != null && m.locations.any((x) => x.id == locationId);
  }

  Future<void> _decide(
    SaleReturnDoc doc,
    ReturnLineRecord line,
    String outcome,
  ) async {
    if (_busy) return;
    final repo = widget.repository;
    setState(() => _busy = true);
    final outcomeResult = await widget.runner.submit(
      action: 'return_inspect',
      businessId: session.membership!.businessId,
      path: repo.inspectPath(doc.id),
      body: repo.inspectBody([
        (
          returnLineId: line.id,
          outcome: outcome,
          quantityMilli: line.awaitingMilli,
        ),
      ]),
      subject: returnNumber(doc.number),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    final l = strings(context);
    switch (outcomeResult) {
      case OperationCompleted():
        _changed = true;
        showFeedback(context, l.returnInspectDone);
        _section.currentState?.reload();
      case OperationUnknown():
        showFeedback(context, l.outcomeUnknownNotice);
        Navigator.of(context).popUntil((r) => r.isFirst); // where the banner is
      case OperationRejected(:final error):
        showFeedback(context, apiErrorText(l, error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = strings(context);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_changed);
      },
      child: Scaffold(
        appBar: AppBar(title: Text(l.returnsTitle)),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: AsyncSection<SaleReturnDoc>(
                  key: _section,
                  load: () => widget.repository.returnDoc(widget.returnId),
                  builder: (context, doc) => _body(context, doc),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, SaleReturnDoc doc) {
    final l = strings(context);
    final canDecide = session.can('return.inspect') && _mayUse(doc.locationId);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l.returnNumberTitle(returnNumber(doc.number)),
                key: const ValueKey('rd-number'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              Text(
                '${formatStamp(doc.createdAt)} · ${doc.locationName}',
                style: const TextStyle(color: AppColors.muted),
              ),
              Text(
                '${l.returnFromSale(saleNumber(doc.saleNumber))} · ${doc.createdBy}',
              ),
              Text('${l.returnReasonShort}: ${doc.reason}'),
              if (doc.note.isNotEmpty) Text(doc.note),
              const SizedBox(height: 8),
              Text(
                l.returnRefundTotal(formatMoney(doc.refundMinor, 'TMT')),
                key: const ValueKey('rd-refund'),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        for (final line in doc.lines)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: SurfaceCard(
              padding: 12,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${line.name} · ${line.sku}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    '${formatQuantity(line.quantityMilli, line.unitDecimals)} ${line.unitSymbol} · ${returnConditionLabel(l, line.condition)}',
                  ),
                  Text(
                    formatMoney(line.refundMinor, 'TMT'),
                    style: const TextStyle(color: AppColors.muted),
                  ),
                  if (line.awaitingMilli > 0) ...[
                    const SizedBox(height: 6),
                    Text(
                      l.returnAwaiting(
                        '${formatQuantity(line.awaitingMilli, line.unitDecimals)} ${line.unitSymbol}',
                      ),
                      key: ValueKey('rd-awaiting-${line.id}'),
                      style: const TextStyle(color: AppColors.warning),
                    ),
                    if (canDecide)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Wrap(
                          spacing: 12,
                          runSpacing: 8,
                          children: [
                            ListenableBuilder(
                              listenable: widget.monitor,
                              builder: (context, _) => GradientButton(
                                key: ValueKey('rd-sellable-${line.id}'),
                                label: l.returnInspectSellable,
                                icon: Icons.check,
                                onPressed: _busy || !widget.monitor.online
                                    ? null
                                    : () => _decide(doc, line, 'sellable'),
                              ),
                            ),
                            OutlinedButton.icon(
                              key: ValueKey('rd-damaged-${line.id}'),
                              onPressed: _busy || !widget.monitor.online
                                  ? null
                                  : () => _decide(doc, line, 'damaged'),
                              icon: const Icon(Icons.heart_broken_outlined),
                              label: Text(l.returnInspectDamaged),
                            ),
                          ],
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }
}
