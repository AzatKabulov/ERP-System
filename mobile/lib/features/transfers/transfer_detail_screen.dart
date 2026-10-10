import 'package:flutter/material.dart';

import '../../core/api/api_error_text.dart';
import '../../core/api/api_exception.dart';
import '../../core/connectivity/connection_monitor.dart';
import '../../core/format/format_stamp.dart';
import '../../core/money/decimal_math.dart';
import '../../core/operations/operation_runner.dart';
import '../../core/session/session_controller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../inventory/quantity_input.dart';
import '../shared/async_section.dart';
import '../workspace/unsaved_work.dart';
import 'transfers_models.dart';
import 'transfers_repository.dart';

/// One transfer: what was sent, where it is, and (while it is in transit) buttons to
/// receive or cancel it. Receiving and cancelling go through the [OperationRunner] too.
class TransferDetailScreen extends StatefulWidget {
  const TransferDetailScreen({
    super.key,
    required this.transferId,
    required this.session,
    required this.repository,
    required this.runner,
    required this.monitor,
    required this.unsaved,
  });

  final String transferId;
  final SessionController session;
  final TransfersRepository repository;
  final OperationRunner runner;
  final ConnectionMonitor monitor;
  final UnsavedWork unsaved;

  @override
  State<TransferDetailScreen> createState() => _TransferDetailScreenState();
}

class _TransferDetailScreenState extends State<TransferDetailScreen> {
  final _section = GlobalKey<AsyncSectionState<Transfer>>();
  bool _changed = false;

  SessionController get session => widget.session;

  bool _mayUse(String locationId) {
    final m = session.membership;
    return m != null && m.locations.any((x) => x.id == locationId);
  }

  Future<void> _receive(Transfer transfer) async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ReceiveTransferScreen(
          transfer: transfer,
          session: session,
          repository: widget.repository,
          runner: widget.runner,
          monitor: widget.monitor,
          unsaved: widget.unsaved,
        ),
      ),
    );
    if (result == null || !mounted) return;
    _changed = true;
    final l = strings(context);
    showFeedback(
      context,
      result ? l.transferReceivedDone : l.outcomeUnknownNotice,
    );
    if (result) {
      _section.currentState?.reload();
    } else {
      Navigator.of(context).popUntil((r) => r.isFirst); // where the banner is
    }
  }

  Future<void> _cancel(Transfer transfer) async {
    final reason = await showReasonDialog(
      context,
      title: strings(context).transferCancel,
      label: strings(context).reasonLabel,
      required: true,
    );
    if (reason == null || !mounted) return;
    final repo = widget.repository;
    final outcome = await widget.runner.submit(
      action: 'transfer_cancel',
      businessId: session.membership!.businessId,
      path: repo.cancelPath(transfer.id),
      body: repo.cancelBody(reason),
      subject: transferNumber(transfer.number),
    );
    if (!mounted) return;
    final l = strings(context);
    switch (outcome) {
      case OperationCompleted():
        _changed = true;
        showFeedback(context, l.transferCancelledDone);
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
        appBar: AppBar(title: Text(l.transfersTitle)),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: AsyncSection<Transfer>(
                  key: _section,
                  load: () => widget.repository.transfer(widget.transferId),
                  builder: (context, t) => Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SurfaceCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    l.transferNumberTitle(
                                      transferNumber(t.number),
                                    ),
                                    key: const ValueKey('td-number'),
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleLarge,
                                  ),
                                ),
                                Flexible(
                                  child: StatusPill(
                                    key: const ValueKey('td-status'),
                                    label: transferStatusLabel(l, t.status),
                                    warning: t.status != 'received',
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(l.transferRoute(t.fromName, t.toName)),
                            Text(
                              '${formatStamp(t.createdAt)} · ${t.createdBy}',
                              style: const TextStyle(color: AppColors.muted),
                            ),
                            if (t.note.isNotEmpty) Text(t.note),
                            if (t.inTransit)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(
                                  l.transferInTransitNote,
                                  style: const TextStyle(
                                    color: AppColors.warning,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            if (t.discrepancyReason.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(
                                  '${l.transferShortReasonLabel}: ${t.discrepancyReason}',
                                  key: const ValueKey('td-discrepancy'),
                                ),
                              ),
                            if (t.cancelReason.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(
                                  '${l.cancelReasonLabel}: ${t.cancelReason}',
                                  key: const ValueKey('td-cancel-reason'),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      SurfaceCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (final line in t.lines)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 6,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${line.product.name} · ${line.product.sku}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    Text(
                                      l.transferSentLine(
                                        quantityWithUnit(
                                          line.quantityMilli,
                                          line.product.unit,
                                        ),
                                      ),
                                    ),
                                    if (line.receivedMilli != null)
                                      Text(
                                        l.transferReceivedLine(
                                          quantityWithUnit(
                                            line.receivedMilli!,
                                            line.product.unit,
                                          ),
                                        ),
                                        style: TextStyle(
                                          color:
                                              line.receivedMilli! <
                                                  line.quantityMilli
                                              ? AppColors.danger
                                              : AppColors.muted,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (t.inTransit) ...[
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            if (session.can('transfer.receive') &&
                                _mayUse(t.toId))
                              GradientButton(
                                key: const ValueKey('td-receive'),
                                label: l.transferReceive,
                                icon: Icons.inventory_2_outlined,
                                onPressed: () => _receive(t),
                              ),
                            if (session.can('transfer.create') &&
                                _mayUse(t.fromId))
                              OutlinedButton.icon(
                                key: const ValueKey('td-cancel'),
                                onPressed: () => _cancel(t),
                                icon: const Icon(Icons.close),
                                label: Text(l.transferCancel),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Asks for a short text (a reason). Null when dismissed; never an empty string when
/// [required].
Future<String?> showReasonDialog(
  BuildContext context, {
  required String title,
  required String label,
  bool required = false,
}) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (context) {
      final l = strings(context);
      return StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(title),
          content: TextField(
            key: const ValueKey('reason-field'),
            controller: controller,
            autofocus: true,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(labelText: label),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l.cancel),
            ),
            FilledButton(
              key: const ValueKey('reason-confirm'),
              onPressed: required && controller.text.trim().isEmpty
                  ? null
                  : () => Navigator.pop(context, controller.text.trim()),
              child: Text(l.confirm),
            ),
          ],
        ),
      );
    },
  );
}

/// Confirm what arrived. Every line starts with everything that was sent; typing less asks
/// for a reason, and the missing goods are written off.
class ReceiveTransferScreen extends StatefulWidget {
  const ReceiveTransferScreen({
    super.key,
    required this.transfer,
    required this.session,
    required this.repository,
    required this.runner,
    required this.monitor,
    required this.unsaved,
  });

  final Transfer transfer;
  final SessionController session;
  final TransfersRepository repository;
  final OperationRunner runner;
  final ConnectionMonitor monitor;
  final UnsavedWork unsaved;

  @override
  State<ReceiveTransferScreen> createState() => _ReceiveTransferScreenState();
}

class _ReceiveTransferScreenState extends State<ReceiveTransferScreen> {
  late final Map<String, TextEditingController> _controllers = {
    for (final line in widget.transfer.lines)
      line.id: TextEditingController(
        text: formatQuantity(
          line.quantityMilli,
          line.product.unit.decimalPlaces,
        ),
      ),
  };
  final _reason = TextEditingController();
  bool _busy = false;
  ApiException? _error;

  @override
  void initState() {
    super.initState();
    widget.unsaved.mark(this, dirty: true);
  }

  @override
  void dispose() {
    widget.unsaved.mark(this, dirty: false);
    for (final c in _controllers.values) {
      c.dispose();
    }
    _reason.dispose();
    super.dispose();
  }

  /// Zero is allowed here (nothing arrived), unlike everywhere else.
  int? _arrived(TransferLineRecord line) {
    final text = _controllers[line.id]!.text.trim();
    if (text.isEmpty) return null;
    final milli = parseScaled(text, 3);
    if (milli == null || milli > line.quantityMilli) return null;
    if (milli == 0) return 0;
    return parseQuantity(text, line.product.unit);
  }

  bool get _allValid => widget.transfer.lines.every((l) => _arrived(l) != null);
  bool get _short => widget.transfer.lines.any(
    (l) => (_arrived(l) ?? l.quantityMilli) < l.quantityMilli,
  );
  bool get _canSubmit =>
      _allValid && (!_short || _reason.text.trim().isNotEmpty);

  Future<void> _submit() async {
    if (_busy || !_canSubmit) return;
    final repo = widget.repository;
    setState(() {
      _busy = true;
      _error = null;
    });
    final outcome = await widget.runner.submit(
      action: 'transfer_receive',
      businessId: widget.session.membership!.businessId,
      path: repo.receivePath(widget.transfer.id),
      body: repo.receiveBody(
        lines: [
          for (final line in widget.transfer.lines)
            (lineId: line.id, quantityMilli: _arrived(line)!),
        ],
        reason: _short ? _reason.text.trim() : '',
      ),
      subject: transferNumber(widget.transfer.number),
    );
    if (!mounted) return;
    switch (outcome) {
      case OperationCompleted():
        widget.unsaved.mark(this, dirty: false);
        Navigator.of(context).pop(true);
      case OperationUnknown():
        widget.unsaved.mark(this, dirty: false);
        Navigator.of(context).pop(false);
      case OperationRejected(:final error):
        setState(() {
          _busy = false;
          _error = error;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = strings(context);
    final t = widget.transfer;
    return Scaffold(
      appBar: AppBar(
        title: Text(l.transferNumberTitle(transferNumber(t.number))),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(l.transferRoute(t.fromName, t.toName)),
                  const SizedBox(height: 16),
                  for (final line in t.lines)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: SurfaceCard(
                        padding: 12,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              line.product.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              l.transferSentLine(
                                quantityWithUnit(
                                  line.quantityMilli,
                                  line.product.unit,
                                ),
                              ),
                              style: const TextStyle(
                                color: AppColors.muted,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Semantics(
                              container: true,
                              explicitChildNodes: true,
                              child: SizedBox(
                                width: 190,
                                child: TextField(
                                  key: ValueKey('receive-qty-${line.id}'),
                                  controller: _controllers[line.id],
                                  enabled: !_busy,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                  onChanged: (_) => setState(() {}),
                                  decoration: InputDecoration(
                                    labelText: l.transferArrivedLabel,
                                    suffixText: line.product.unit.symbol,
                                    errorText: _arrived(line) == null
                                        ? l.fieldInvalid
                                        : null,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (_short) ...[
                    Text(
                      l.transferShortHint,
                      style: const TextStyle(color: AppColors.warning),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      key: const ValueKey('receive-reason'),
                      controller: _reason,
                      enabled: !_busy,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        labelText: l.transferShortReasonLabel,
                      ),
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        apiErrorText(l, _error!),
                        key: const ValueKey('receive-error'),
                        style: const TextStyle(color: AppColors.danger),
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  ListenableBuilder(
                    listenable: widget.monitor,
                    builder: (context, _) => GradientButton(
                      key: const ValueKey('receive-confirm'),
                      label: l.transferReceive,
                      icon: Icons.check,
                      onPressed: _busy || !widget.monitor.online || !_canSubmit
                          ? null
                          : _submit,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
