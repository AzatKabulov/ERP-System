import 'package:flutter/material.dart';

import '../../core/api/api_error_text.dart';
import '../../core/api/api_exception.dart';
import '../../core/connectivity/connection_monitor.dart';
import '../../core/operations/operation_runner.dart';
import '../../core/money/decimal_math.dart';
import '../../core/session/session_controller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../inventory/quantity_input.dart';
import '../inventory/stock_entry_screen.dart' show EntryResult;
import '../workspace/unsaved_work.dart';
import 'purchasing_models.dart';
import 'purchasing_repository.dart';

/// Receive goods against an order, in full or in part. Sent through the
/// [OperationRunner]: the request and its operation key are saved on the device
/// before sending, so after a timeout, a crash or a restart the same key is used
/// again and the goods can never be received twice.
class ReceiveScreen extends StatefulWidget {
  const ReceiveScreen({
    super.key,
    required this.order,
    required this.session,
    required this.repository,
    required this.runner,
    required this.monitor,
    required this.unsaved,
  });

  final PurchaseOrder order;
  final SessionController session;
  final PurchasingRepository repository;
  final OperationRunner runner;
  final ConnectionMonitor monitor;
  final UnsavedWork unsaved;

  @override
  State<ReceiveScreen> createState() => _ReceiveScreenState();
}

class _ReceiveScreenState extends State<ReceiveScreen> {
  late final List<OrderLine> _open = [
    for (final line in widget.order.lines)
      if (line.outstandingMilli > 0) line,
  ];
  late final Map<String, TextEditingController> _controllers = {
    for (final line in _open)
      line.id: TextEditingController(
        text: formatQuantity(
          line.outstandingMilli,
          line.product.unit.decimalPlaces,
        ),
      ),
  };
  final _note = TextEditingController();
  bool _dirty = false;
  bool _submitted = false;
  bool _busy = false;
  ApiException? _error;

  @override
  void dispose() {
    widget.unsaved.mark(this, dirty: false);
    for (final c in _controllers.values) {
      c.dispose();
    }
    _note.dispose();
    super.dispose();
  }

  void _touch() {
    if (!_dirty) {
      _dirty = true;
      widget.unsaved.mark(this, dirty: true);
    }
    setState(() {});
  }

  /// null: left empty or zero (skipped). -1: not a valid quantity for this line.
  int? _milli(OrderLine line) {
    final text = _controllers[line.id]!.text.trim();
    if (text.isEmpty || parseScaled(text, 3) == 0) return null;
    final milli = parseQuantity(text, line.product.unit);
    if (milli == null || milli > line.outstandingMilli) return -1;
    return milli;
  }

  String? _lineError(OrderLine line) {
    if (!_submitted) return null;
    final l = strings(context);
    final milli = _milli(line);
    if (milli != -1) return null;
    final typed = parseQuantity(_controllers[line.id]!.text, line.product.unit);
    return typed == null ? l.fieldQuantityPrecision : l.errorOverReceipt;
  }

  List<({String lineId, int quantityMilli})> _entered() => [
    for (final line in _open)
      if (_milli(line) case final m? when m > 0)
        (lineId: line.id, quantityMilli: m),
  ];

  bool get _hasInvalid => _open.any((line) => _milli(line) == -1);

  Future<void> _submit() async {
    if (_busy) return;
    setState(() {
      _submitted = true;
      _error = null;
    });
    final lines = _entered();
    if (lines.isEmpty || _hasInvalid) return;
    setState(() => _busy = true);
    final repo = widget.repository;
    final outcome = await widget.runner.submit(
      action: 'purchase_receive',
      businessId: widget.session.membership!.businessId,
      path: repo.receivePath(widget.order.id),
      body: repo.receiveBody(lines: lines, note: _note.text.trim()),
      subject: orderNumber(widget.order.number),
    );
    if (!mounted) return;
    switch (outcome) {
      case OperationCompleted():
        _finish(EntryResult.posted);
      case OperationUnknown():
        _finish(EntryResult.unknown);
      case OperationRejected(:final error):
        setState(() {
          _busy = false;
          _error = error;
        });
    }
  }

  void _finish(EntryResult result) {
    _dirty = false;
    widget.unsaved.mark(this, dirty: false);
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final l = strings(context);
    final showCost = widget.order.lines.any((x) => x.unitCostMinor != null);
    return PopScope(
      canPop: !_dirty || _busy,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final leave = await confirmAction(
          context,
          l.receiveGoods,
          l.unsavedChangeConflict,
        );
        if (leave && context.mounted) {
          _dirty = false;
          widget.unsaved.mark(this, dirty: false);
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(l.receiveTitle(orderNumber(widget.order.number))),
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
                    Text(
                      '${widget.order.supplierName} → ${widget.order.locationName}',
                      style: const TextStyle(color: AppColors.muted),
                    ),
                    const SizedBox(height: 16),
                    for (final line in _open)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: SurfaceCard(
                          padding: 14,
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
                                '${line.product.sku} · '
                                '${l.outstandingLabel(quantityWithUnit(line.outstandingMilli, line.product.unit))}'
                                '${showCost && line.unitCostMinor != null ? ' · ${formatMoney(line.unitCostMinor!, 'TMT')}' : ''}',
                                style: const TextStyle(
                                  color: AppColors.muted,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 12),
                              SizedBox(
                                width: 220,
                                child: TextField(
                                  key: ValueKey(
                                    'receive-qty-${line.product.sku}',
                                  ),
                                  controller: _controllers[line.id],
                                  enabled: !_busy,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                  onChanged: (_) => _touch(),
                                  decoration: InputDecoration(
                                    labelText: l.receiveQuantityLabel,
                                    suffixText: line.product.unit.symbol,
                                    errorText: _lineError(line),
                                    errorMaxLines: 3,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        key: const ValueKey('receive-all'),
                        onPressed: _busy
                            ? null
                            : () {
                                for (final line in _open) {
                                  _controllers[line.id]!.text = formatQuantity(
                                    line.outstandingMilli,
                                    line.product.unit.decimalPlaces,
                                  );
                                }
                                _touch();
                              },
                        icon: const Icon(Icons.done_all),
                        label: Text(l.receiveAll),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      key: const ValueKey('receive-note'),
                      controller: _note,
                      enabled: !_busy,
                      onChanged: (_) => _touch(),
                      decoration: InputDecoration(labelText: l.noteLabel),
                    ),
                    if (_submitted && _entered().isEmpty && !_hasInvalid)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          l.receiveNothing,
                          key: const ValueKey('receive-nothing'),
                          style: const TextStyle(color: AppColors.danger),
                        ),
                      ),
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          apiErrorText(l, _error!),
                          key: const ValueKey('receive-error'),
                          style: const TextStyle(color: AppColors.danger),
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    ListenableBuilder(
                      listenable: widget.monitor,
                      builder: (context, _) => Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (!widget.monitor.online)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Text(
                                l.offlineBanner,
                                style: const TextStyle(
                                  color: AppColors.danger,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          GradientButton(
                            key: const ValueKey('receive-submit'),
                            label: l.receiveGoods,
                            icon: Icons.inventory_2_outlined,
                            onPressed: _busy || !widget.monitor.online
                                ? null
                                : _submit,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
