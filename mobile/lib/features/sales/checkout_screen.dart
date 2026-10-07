import 'package:flutter/material.dart';

import '../../core/api/api_error_text.dart';
import '../../core/api/api_exception.dart';
import '../../core/connectivity/connection_monitor.dart';
import '../../core/money/decimal_math.dart';
import '../../core/operations/operation_runner.dart';
import '../../core/session/session_controller.dart';
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

/// The last step: check the lines, say how the customer paid (cash or card) and save. The
/// sale is sent through the [OperationRunner]: the request and its operation key are saved
/// on the device before sending, so a timeout, crash or restart can never turn one sale into
/// two. Success is shown only after the server confirms.
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
  String _method = 'cash';
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
    super.dispose();
  }

  Future<void> _confirm() async {
    if (_busy) return;
    final cart = widget.cart;
    final repo = widget.repository;
    final body = repo.saleBody(
      locationId: widget.locationId,
      customerId: cart.customer?.id,
      paymentMethod: _method,
      lines: cart.saleLines,
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
    return method == 'cash' ? l.payCash : l.payCard;
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
                                      '${quantityWithUnit(cart.quantityMilli(line) ?? 0, line.product.unit)}'
                                      ' · ${formatMoney(cart.priceMinor(line) ?? 0, 'TMT')}',
                                      maxLines: 3,
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
                          Text(
                            l.saleTotal(formatMoney(_total, 'TMT')),
                            key: const ValueKey('checkout-total'),
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    SurfaceCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l.paidBy,
                            style: const TextStyle(color: AppColors.muted),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            key: const ValueKey('pay-method'),
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final m in paymentMethods)
                                ChoiceChip(
                                  key: ValueKey('pay-$m'),
                                  label: Text(_methodLabel(m)),
                                  selected: _method == m,
                                  onSelected: _busy
                                      ? null
                                      : (_) => setState(() => _method = m),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
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
                            onPressed: _busy || !widget.monitor.online
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
}
