import 'package:flutter/material.dart';

import '../../core/api/api_error_text.dart';
import '../../core/api/api_exception.dart';
import '../../core/connectivity/connection_monitor.dart';
import '../../core/money/decimal_math.dart';
import '../../core/operations/operation_runner.dart';
import '../../core/session/session_controller.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../inventory/quantity_input.dart';
import '../workspace/unsaved_work.dart';
import 'cart_controller.dart';
import 'sales_models.dart';
import 'sales_repository.dart';

/// How the checkout ended.
sealed class CheckoutOutcome {
  const CheckoutOutcome();
}

/// The server confirmed the sale.
class SaleCompleted extends CheckoutOutcome {
  const SaleCompleted(this.sale);
  final SaleDetail sale;
}

/// No usable answer: the sale may or may not exist. The request and its key are saved
/// on the device and listed in the pending banner; the cart must not be sold again.
class SaleUnknown extends CheckoutOutcome {
  const SaleUnknown();
}

/// The server refused because prices moved since the cart was prepared.
class PricesChanged extends CheckoutOutcome {
  const PricesChanged();
}

class _PaymentRow {
  _PaymentRow(this.method, String amount)
    : controller = TextEditingController(text: amount);
  String method;
  final TextEditingController controller;
}

/// Review and pay. The sale is sent through the [OperationRunner]: the request and its
/// operation key are saved on the device before sending, so a timeout, crash or restart can
/// never turn one sale into two. Success is shown only after the server confirms.
class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({
    super.key,
    required this.cart,
    required this.session,
    required this.repository,
    required this.runner,
    required this.monitor,
    required this.unsaved,
    required this.locationId,
    required this.locationName,
  });

  final CartController cart;
  final SessionController session;
  final SalesRepository repository;
  final OperationRunner runner;
  final ConnectionMonitor monitor;
  final UnsavedWork unsaved;
  final String locationId;
  final String locationName;

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  late final int _total = widget.cart.totalMinor;
  late final List<_PaymentRow> _rows = [
    if (_total > 0)
      _PaymentRow('cash', toServerDecimal(_total, 2).replaceAll('.', ',')),
  ];
  bool _busy = false;
  ApiException? _error;
  String? _named; // a translated, product-specific refusal

  @override
  void initState() {
    super.initState();
    widget.unsaved.mark(this, dirty: true);
  }

  @override
  void dispose() {
    widget.unsaved.mark(this, dirty: false);
    for (final row in _rows) {
      row.controller.dispose();
    }
    super.dispose();
  }

  int? _amount(_PaymentRow row) {
    final value = parseScaled(row.controller.text, 2);
    return value == null || value <= 0 ? null : value;
  }

  bool get _amountsValid => _rows.every((r) => _amount(r) != null);
  int get _paid => _rows.fold(0, (s, r) => s + (_amount(r) ?? 0));
  int get _cash => _rows
      .where((r) => r.method == 'cash')
      .fold(0, (s, r) => s + (_amount(r) ?? 0));
  int get _change => _paid > _total ? _paid - _total : 0;
  int get _remaining => _paid < _total ? _total - _paid : 0;

  /// The same rule the server applies: paid in full, and only cash gives change.
  bool get _paymentsOk =>
      _amountsValid &&
      _paid >= _total &&
      _change <= _cash &&
      (_total > 0 || _paid == 0);

  Future<void> _confirm() async {
    if (_busy || !_paymentsOk) return;
    final cart = widget.cart;
    final repo = widget.repository;
    final body = repo.saleBody(
      locationId: widget.locationId,
      customerId: cart.customer?.id,
      expectedTotalMinor: _total,
      lines: cart.saleLines,
      payments: [
        for (final r in _rows) (method: r.method, amountMinor: _amount(r)!),
      ],
    );
    setState(() {
      _busy = true;
      _error = null;
      _named = null;
    });
    final outcome = await widget.runner.submit(
      action: 'sale_complete',
      businessId: widget.session.membership!.businessId,
      path: repo.salePath,
      body: body,
      subject: formatMoney(_total, 'TMT'),
    );
    if (!mounted) return;
    switch (outcome) {
      case OperationCompleted(:final response):
        widget.unsaved.mark(this, dirty: false);
        Navigator.of(
          context,
        ).pop(SaleCompleted(SaleDetail.fromJson(response.map)));
      case OperationUnknown():
        widget.unsaved.mark(this, dirty: false);
        Navigator.of(context).pop(const SaleUnknown());
      case OperationRejected(:final error):
        if (error.code == 'price_changed') {
          widget.unsaved.mark(this, dirty: false);
          Navigator.of(context).pop(const PricesChanged());
          return;
        }
        setState(() {
          _busy = false;
          _error = error;
          _named = _namedRefusal(error);
        });
    }
  }

  /// "Not enough PRODUCT: N available", when the server names the product.
  String? _namedRefusal(ApiException error) {
    if (error.code != 'insufficient_stock') return null;
    final id = error.params['product'];
    final line = widget.cart.lines.where((l) => l.product.id == id).firstOrNull;
    if (line == null) return null;
    final available =
        parseServerDecimal('${error.params['available']}', 3) ?? 0;
    return strings(context).errorInsufficientNamed(
      line.product.name,
      quantityWithUnit(available, line.product.unit),
    );
  }

  String _methodLabel(String method) {
    final l = strings(context);
    return switch (method) {
      'cash' => l.payCash,
      'card' => l.payCard,
      _ => l.payTransfer,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l = strings(context);
    final cart = widget.cart;
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(title: Text(l.paymentTitle)),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SurfaceCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.locationName,
                            style: const TextStyle(color: AppColors.muted),
                          ),
                          if (cart.customer != null)
                            Text(
                              '${l.customer}: ${cart.customer!.name}',
                              key: const ValueKey('checkout-customer'),
                            ),
                          const SizedBox(height: 8),
                          for (final line in cart.lines)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 3),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      '${line.product.name} × '
                                      '${quantityWithUnit(cart.quantityMilli(line) ?? 0, line.product.unit)}',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Flexible(
                                    child: Text(
                                      formatMoney(
                                        cart.lineTotalMinor(line) ?? 0,
                                        'TMT',
                                      ),
                                      textAlign: TextAlign.end,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          const Divider(),
                          if (cart.discountTotalMinor > 0)
                            Text(
                              l.saleDiscountSum(
                                formatMoney(cart.discountTotalMinor, 'TMT'),
                              ),
                              style: const TextStyle(color: AppColors.muted),
                            ),
                          Text(
                            l.saleTotal(formatMoney(_total, 'TMT')),
                            key: const ValueKey('checkout-total'),
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    for (var i = 0; i < _rows.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _paymentRow(i),
                      ),
                    if (_total > 0)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          key: const ValueKey('pay-add'),
                          onPressed: _busy || _rows.length >= 4
                              ? null
                              : () => setState(
                                  () => _rows.add(
                                    _PaymentRow(
                                      'card',
                                      _remaining == 0
                                          ? ''
                                          : toServerDecimal(
                                              _remaining,
                                              2,
                                            ).replaceAll('.', ','),
                                    ),
                                  ),
                                ),
                          icon: const Icon(Icons.add),
                          label: Text(l.addPayment),
                        ),
                      ),
                    const SizedBox(height: 8),
                    _summary(l),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          _named ?? apiErrorText(l, _error!),
                          key: const ValueKey('checkout-error'),
                          style: const TextStyle(color: AppColors.danger),
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
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
                            key: const ValueKey('checkout-confirm'),
                            label: l.completeSale,
                            icon: Icons.check,
                            onPressed:
                                _busy || !widget.monitor.online || !_paymentsOk
                                ? null
                                : _confirm,
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

  Widget _paymentRow(int i) {
    final l = strings(context);
    final row = _rows[i];
    return SurfaceCard(
      padding: 14,
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Wrap(
            key: ValueKey('pay-method-$i'),
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final m in paymentMethods)
                ChoiceChip(
                  key: ValueKey('pay-$m-$i'),
                  label: Text(_methodLabel(m)),
                  selected: row.method == m,
                  onSelected: _busy
                      ? null
                      : (_) => setState(() => row.method = m),
                ),
            ],
          ),
          SizedBox(
            width: 180,
            child: TextField(
              key: ValueKey('pay-amount-$i'),
              controller: row.controller,
              enabled: !_busy,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: l.payAmountLabel,
                errorText:
                    row.controller.text.trim().isNotEmpty &&
                        _amount(row) == null
                    ? l.fieldInvalid
                    : null,
              ),
            ),
          ),
          if (_rows.length > 1)
            IconButton(
              key: ValueKey('pay-remove-$i'),
              tooltip: l.removeLine,
              onPressed: _busy
                  ? null
                  : () => setState(() {
                      _rows.removeAt(i).controller.dispose();
                    }),
              icon: const Icon(Icons.delete_outline),
            ),
        ],
      ),
    );
  }

  Widget _summary(AppLocalizations l) {
    final lines = <Widget>[];
    if (_total > 0) {
      lines.add(
        Text(
          l.paidSum(formatMoney(_paid, 'TMT')),
          key: const ValueKey('checkout-paid'),
        ),
      );
      if (_remaining > 0) {
        lines.add(
          Text(
            l.remainingSum(formatMoney(_remaining, 'TMT')),
            key: const ValueKey('checkout-remaining'),
            style: const TextStyle(color: AppColors.warning),
          ),
        );
      }
      if (_change > 0) {
        lines.add(
          Text(
            l.changeSum(formatMoney(_change, 'TMT')),
            key: const ValueKey('checkout-change'),
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: _change <= _cash ? AppColors.success : AppColors.danger,
            ),
          ),
        );
        if (_change > _cash) {
          lines.add(
            Text(
              l.paymentCashOnlyChange,
              key: const ValueKey('checkout-change-error'),
              style: const TextStyle(color: AppColors.danger, fontSize: 13),
            ),
          );
        }
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: lines,
    );
  }
}
