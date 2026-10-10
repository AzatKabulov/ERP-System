import 'package:flutter/material.dart';

import '../../core/api/api_error_text.dart';
import '../../core/api/api_exception.dart';
import '../../core/connectivity/connection_monitor.dart';
import '../../core/money/decimal_math.dart';
import '../../l10n/app_localizations.dart';
import '../../core/operations/operation_runner.dart';
import '../../core/session/session_controller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../sales/sales_models.dart';
import '../workspace/unsaved_work.dart';
import 'returns_models.dart';
import 'returns_repository.dart';

/// What the form hands back: the return was made, or nobody knows yet (the saved record owns
/// it and the pending-operations banner follows it).
enum ReturnResult { done, unknown }

/// Bring goods back against a sale: how many of each line, in which condition, and why. The
/// refund is what the customer was charged for those goods (the same rule as the server's).
/// Nothing is shown as done before the server confirms.
class ReturnFormScreen extends StatefulWidget {
  const ReturnFormScreen({
    super.key,
    required this.sale,
    required this.session,
    required this.repository,
    required this.runner,
    required this.monitor,
    required this.unsaved,
  });

  final SaleDetail sale;
  final SessionController session;
  final ReturnsRepository repository;
  final OperationRunner runner;
  final ConnectionMonitor monitor;
  final UnsavedWork unsaved;

  @override
  State<ReturnFormScreen> createState() => _ReturnFormScreenState();
}

class _ReturnFormScreenState extends State<ReturnFormScreen> {
  late final List<SaleLineRecord> _lines = [
    for (final l in widget.sale.lines)
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

  /// Zero when the box is empty; null when what was typed is not a valid quantity.
  int? _milli(SaleLineRecord line) {
    final text = _qty[line.id]!.text.trim();
    if (text.isEmpty) return 0;
    final milli = parseReturnQuantity(text, line.unitDecimals);
    if (milli == null || milli > line.returnableMilli) return null;
    return milli;
  }

  bool _blocked(SaleLineRecord line) => line.returnDays == 0;

  int _refund(SaleLineRecord line) {
    final milli = _milli(line) ?? 0;
    if (milli == 0) return 0;
    return refundMinor(
      quantityMilli: milli,
      returnableMilli: line.returnableMilli,
      unitPriceMinor: line.unitPriceMinor,
      lineTotalMinor: line.lineTotalMinor,
      refundedMinor: line.refundedMinor,
    );
  }

  int get _total => _lines.fold(0, (sum, l) => sum + _refund(l));
  bool get _allValid => _lines.every((l) => _milli(l) != null);
  bool get _any => _lines.any((l) => (_milli(l) ?? 0) > 0);
  bool get _canSubmit => _allValid && _any && _reason.text.trim().isNotEmpty;

  List<({String saleLineId, int quantityMilli, String condition})> _chosen() =>
      [
        for (final l in _lines)
          if ((_milli(l) ?? 0) > 0)
            (
              saleLineId: l.id,
              quantityMilli: _milli(l)!,
              condition: _condition[l.id] ?? 'sellable',
            ),
      ];

  String _summary() => [
    for (final l in _lines)
      if ((_milli(l) ?? 0) > 0)
        '${l.name} ${formatQuantity(_milli(l)!, l.unitDecimals)} ${l.unitSymbol}',
  ].join(', ');

  Future<void> _submit() async {
    if (_busy || !_canSubmit) return;
    final l = strings(context);
    final sure = await confirmAction(
      context,
      l.returnConfirmTitle,
      l.returnConfirmBody(_summary(), formatMoney(_total, 'TMT')),
    );
    if (!sure || !mounted) return;
    final repo = widget.repository;
    setState(() {
      _busy = true;
      _error = null;
    });
    final outcome = await widget.runner.submit(
      action: 'return_complete',
      businessId: widget.session.membership!.businessId,
      path: repo.returnPath(widget.sale.id),
      body: repo.returnBody(
        reason: _reason.text.trim(),
        note: '',
        lines: _chosen(),
      ),
      subject: saleNumber(widget.sale.number),
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

  String _errorText(AppLocalizations l, ApiException e) {
    if (e.code == 'over_return') {
      final line = _lines.where((x) => x.productId == e.params['product']);
      if (line.isNotEmpty) {
        final milli = parseServerDecimal(e.params['returnable'] as String?, 3);
        if (milli != null) {
          return l.errorOverReturnNamed(
            line.first.name,
            '${formatQuantity(milli, line.first.unitDecimals)} ${line.first.unitSymbol}',
          );
        }
      }
    }
    if (e.code == 'return_window_expired' || e.code == 'returns_not_accepted') {
      final line = _lines.where((x) => x.productId == e.params['product']);
      final name = line.isEmpty ? '' : '${line.first.name}: ';
      return '$name${apiErrorText(l, e)}';
    }
    return apiErrorText(l, e);
  }

  @override
  Widget build(BuildContext context) {
    final l = strings(context);
    final sale = widget.sale;
    return Scaffold(
      appBar: AppBar(title: Text(l.returnNew)),
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
                    l.returnFromSale(saleNumber(sale.number)),
                    key: const ValueKey('return-sale'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(
                    sale.locationName,
                    style: const TextStyle(color: AppColors.muted),
                  ),
                  const SizedBox(height: 16),
                  if (_lines.isEmpty)
                    SurfaceCard(
                      child: Text(
                        l.returnNothingToReturn,
                        key: const ValueKey('return-nothing'),
                      ),
                    ),
                  for (final line in _lines)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: SurfaceCard(
                        padding: 12,
                        child: _lineCard(context, line),
                      ),
                    ),
                  if (_lines.isNotEmpty) ...[
                    TextField(
                      key: const ValueKey('return-reason'),
                      controller: _reason,
                      enabled: !_busy,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        labelText: l.returnReasonLabel,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      l.returnRefundTotal(formatMoney(_total, 'TMT')),
                      key: const ValueKey('return-refund-total'),
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      l.returnRefundNote,
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 13,
                      ),
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        _errorText(l, _error!),
                        key: const ValueKey('return-error'),
                        style: const TextStyle(color: AppColors.danger),
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  ListenableBuilder(
                    listenable: widget.monitor,
                    builder: (context, _) => GradientButton(
                      key: const ValueKey('return-confirm'),
                      label: l.returnButton,
                      icon: Icons.assignment_return_outlined,
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

  Widget _lineCard(BuildContext context, SaleLineRecord line) {
    final l = strings(context);
    final blocked = _blocked(line);
    final until = line.returnUntil;
    final condition = _condition[line.id] ?? 'sellable';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${line.name} · ${line.sku}',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        Text(
          l.returnableLine(
            '${formatQuantity(line.returnableMilli, line.unitDecimals)} ${line.unitSymbol}',
          ),
          style: const TextStyle(color: AppColors.muted, fontSize: 13),
        ),
        if (blocked)
          Text(
            l.returnNotAccepted,
            key: ValueKey('return-blocked-${line.id}'),
            style: const TextStyle(color: AppColors.danger, fontSize: 13),
          )
        else if (until != null)
          Text(
            l.returnUntilLine(until),
            style: const TextStyle(color: AppColors.warning, fontSize: 13),
          ),
        const SizedBox(height: 8),
        Semantics(
          container: true,
          explicitChildNodes: true,
          child: SizedBox(
            width: 190,
            child: TextField(
              key: ValueKey('return-qty-${line.id}'),
              controller: _qty[line.id],
              enabled: !_busy && !blocked,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: l.returnQtyLabel,
                suffixText: line.unitSymbol,
                errorText: _milli(line) == null ? l.fieldInvalid : null,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final c in returnConditions)
              ChoiceChip(
                key: ValueKey('return-cond-${line.id}-$c'),
                label: Text(returnConditionLabel(l, c)),
                selected: condition == c,
                onSelected: _busy || blocked
                    ? null
                    : (_) => setState(() => _condition[line.id] = c),
              ),
          ],
        ),
        if (_refund(line) > 0)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              l.returnRefundLine(formatMoney(_refund(line), 'TMT')),
              style: const TextStyle(fontSize: 13),
            ),
          ),
      ],
    );
  }
}
