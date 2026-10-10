import 'package:flutter/material.dart';

import '../../core/api/api_error_text.dart';
import '../../core/api/api_exception.dart';
import '../../core/connectivity/connection_monitor.dart';
import '../../core/operations/operation_runner.dart';
import '../../core/session/session_controller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../inventory/quantity_input.dart';
import '../returns/return_form_screen.dart' show ReturnResult;
import '../returns/returns_models.dart';
import '../workspace/unsaved_work.dart';
import 'purchasing_models.dart';
import 'purchasing_repository.dart';

/// Send goods of one delivery back to the supplier: how many of each line, taken from the
/// sellable or the damaged pile, and why. Only what the delivery brought and has not been sent
/// back yet is offered; the server checks the stock.
class SupplierReturnFormScreen extends StatefulWidget {
  const SupplierReturnFormScreen({
    super.key,
    required this.order,
    required this.delivery,
    required this.session,
    required this.repository,
    required this.runner,
    required this.monitor,
    required this.unsaved,
  });

  final PurchaseOrder order;
  final DeliveryRecord delivery;
  final SessionController session;
  final PurchasingRepository repository;
  final OperationRunner runner;
  final ConnectionMonitor monitor;
  final UnsavedWork unsaved;

  @override
  State<SupplierReturnFormScreen> createState() =>
      _SupplierReturnFormScreenState();
}

class _SupplierReturnFormScreenState extends State<SupplierReturnFormScreen> {
  late final List<DeliveryLineRecord> _lines = [
    for (final l in widget.delivery.lines)
      if (l.returnableMilli > 0) l,
  ];
  late final Map<String, TextEditingController> _qty = {
    for (final l in _lines) l.id: TextEditingController(),
  };
  final Map<String, String> _condition = {};
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
    for (final c in _qty.values) {
      c.dispose();
    }
    _reason.dispose();
    super.dispose();
  }

  int? _milli(DeliveryLineRecord line) {
    final text = _qty[line.id]!.text.trim();
    if (text.isEmpty) return 0;
    final milli = parseQuantity(text, line.product.unit);
    if (milli == null || milli > line.returnableMilli) return null;
    return milli;
  }

  bool get _allValid => _lines.every((l) => _milli(l) != null);
  bool get _any => _lines.any((l) => (_milli(l) ?? 0) > 0);
  bool get _canSubmit => _allValid && _any && _reason.text.trim().isNotEmpty;

  Future<void> _submit() async {
    if (_busy || !_canSubmit) return;
    final repo = widget.repository;
    setState(() {
      _busy = true;
      _error = null;
    });
    final outcome = await widget.runner.submit(
      action: 'supplier_return_create',
      businessId: widget.session.membership!.businessId,
      path: repo.supplierReturnPath,
      body: repo.supplierReturnBody(
        deliveryId: widget.delivery.id,
        reason: _reason.text.trim(),
        lines: [
          for (final l in _lines)
            if ((_milli(l) ?? 0) > 0)
              (
                deliveryLineId: l.id,
                quantityMilli: _milli(l)!,
                condition: _condition[l.id] ?? 'sellable',
              ),
        ],
      ),
      subject: 'PO-${widget.order.number.toString().padLeft(4, '0')}',
    );
    if (!mounted) return;
    switch (outcome) {
      case OperationCompleted():
        widget.unsaved.mark(this, dirty: false);
        Navigator.of(context).pop(ReturnResult.done);
      case OperationUnknown():
        widget.unsaved.mark(this, dirty: false);
        Navigator.of(context).pop(ReturnResult.unknown);
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
    return Scaffold(
      appBar: AppBar(title: Text(l.supplierReturnNew)),
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
                    l.supplierReturnSource(
                      widget.order.supplierName,
                      widget.delivery.number.toString(),
                    ),
                    key: const ValueKey('sr-source'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 16),
                  for (final line in _lines)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: SurfaceCard(
                        padding: 12,
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
                              l.returnableLine(
                                quantityWithUnit(
                                  line.returnableMilli,
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
                                  key: ValueKey('sr-qty-${line.id}'),
                                  controller: _qty[line.id],
                                  enabled: !_busy,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                  onChanged: (_) => setState(() {}),
                                  decoration: InputDecoration(
                                    labelText: l.returnQtyLabel,
                                    suffixText: line.product.unit.symbol,
                                    errorText: _milli(line) == null
                                        ? l.fieldInvalid
                                        : null,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              children: [
                                for (final c in const ['sellable', 'damaged'])
                                  ChoiceChip(
                                    key: ValueKey('sr-cond-${line.id}-$c'),
                                    label: Text(returnConditionLabel(l, c)),
                                    selected:
                                        (_condition[line.id] ?? 'sellable') ==
                                        c,
                                    onSelected: _busy
                                        ? null
                                        : (_) => setState(
                                            () => _condition[line.id] = c,
                                          ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  TextField(
                    key: const ValueKey('sr-reason'),
                    controller: _reason,
                    enabled: !_busy,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(labelText: l.returnReasonLabel),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        apiErrorText(l, _error!),
                        key: const ValueKey('sr-error'),
                        style: const TextStyle(color: AppColors.danger),
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  ListenableBuilder(
                    listenable: widget.monitor,
                    builder: (context, _) => GradientButton(
                      key: const ValueKey('sr-confirm'),
                      label: l.supplierReturnNew,
                      icon: Icons.undo,
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
