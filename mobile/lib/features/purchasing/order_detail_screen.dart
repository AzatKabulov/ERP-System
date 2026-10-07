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
import '../catalog/catalog_repository.dart';
import '../inventory/quantity_input.dart';
import '../inventory/stock_entry_screen.dart' show EntryResult;
import '../shared/async_section.dart';
import '../workspace/unsaved_work.dart';
import 'order_form_screen.dart';
import '../returns/return_form_screen.dart' show ReturnResult;
import 'order_labels.dart';
import 'purchasing_models.dart';
import 'purchasing_repository.dart';
import 'receive_screen.dart';
import 'supplier_return_form_screen.dart';

/// One purchase order: its lines, what has arrived and the deliveries so far, with
/// the actions the person's role allows. Closes with `true` when something changed
/// so the list can refresh.
class OrderDetailScreen extends StatefulWidget {
  const OrderDetailScreen({
    super.key,
    required this.orderId,
    required this.session,
    required this.repository,
    required this.catalog,
    required this.runner,
    required this.monitor,
    required this.unsaved,
  });

  final String orderId;
  final SessionController session;
  final PurchasingRepository repository;
  final CatalogRepository catalog;
  final OperationRunner runner;
  final ConnectionMonitor monitor;
  final UnsavedWork unsaved;

  @override
  State<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends State<OrderDetailScreen> {
  final _section = GlobalKey<AsyncSectionState<PurchaseOrder>>();
  bool _changed = false;
  bool _busy = false;

  bool get _canManage => widget.session.can('purchasing.manage');
  bool get _canReceive => widget.session.can('purchasing.receive');

  void _reload() => _section.currentState?.reload();

  Future<void> _returnToSupplier(
    PurchaseOrder order,
    DeliveryRecord delivery,
  ) async {
    final result = await Navigator.of(context).push<ReturnResult>(
      MaterialPageRoute(
        builder: (_) => SupplierReturnFormScreen(
          order: order,
          delivery: delivery,
          session: widget.session,
          repository: widget.repository,
          runner: widget.runner,
          monitor: widget.monitor,
          unsaved: widget.unsaved,
        ),
      ),
    );
    if (result == null || !mounted) return;
    final l = strings(context);
    _changed = true;
    if (result == ReturnResult.done) {
      showFeedback(context, l.supplierReturnDone);
      _reload();
    } else {
      showFeedback(context, l.outcomeUnknownNotice);
      Navigator.of(context).popUntil((r) => r.isFirst); // where the banner is
    }
  }

  Future<void> _run(
    Future<PurchaseOrder> Function() action,
    String done,
  ) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      _changed = true;
      if (mounted) showFeedback(context, done);
    } on ApiException catch (e) {
      if (mounted) showFeedback(context, apiErrorText(strings(context), e));
    } finally {
      if (mounted) setState(() => _busy = false);
      _reload();
    }
  }

  Future<void> _submitOrder(PurchaseOrder order) async {
    final l = strings(context);
    if (!await confirmAction(context, l.submitOrder, l.submitOrderConfirm)) {
      return;
    }
    await _run(() => widget.repository.submit(order.id), l.orderSubmitted);
  }

  Future<void> _cancel(PurchaseOrder order) async {
    final l = strings(context);
    // The dialog owns its text controller (DialogInput), so it is not disposed while
    // the closing animation is still running.
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => DialogInput(
        builder: (context, controller) => AlertDialog(
          title: Text(l.cancelOrder),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l.cancelOrderConfirm),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('od-cancel-reason'),
                controller: controller,
                decoration: InputDecoration(labelText: l.cancelReasonLabel),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l.cancel),
            ),
            FilledButton(
              key: const ValueKey('od-cancel-confirm'),
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: Text(l.confirm),
            ),
          ],
        ),
      ),
    );
    if (reason == null || !mounted) return;
    await _run(
      () => widget.repository.cancel(order.id, reason),
      l.orderCancelled,
    );
  }

  Future<void> _edit(PurchaseOrder order) async {
    final saved = await Navigator.of(context).push<PurchaseOrder>(
      MaterialPageRoute(
        builder: (_) => OrderFormScreen(
          session: widget.session,
          repository: widget.repository,
          catalog: widget.catalog,
          unsaved: widget.unsaved,
          existing: order,
        ),
      ),
    );
    if (saved != null && mounted) {
      _changed = true;
      showFeedback(context, strings(context).orderSaved);
      _reload();
    }
  }

  Future<void> _receive(PurchaseOrder order) async {
    final result = await Navigator.of(context).push<EntryResult>(
      MaterialPageRoute(
        builder: (_) => ReceiveScreen(
          order: order,
          session: widget.session,
          repository: widget.repository,
          runner: widget.runner,
          monitor: widget.monitor,
          unsaved: widget.unsaved,
        ),
      ),
    );
    if (result == null || !mounted) return;
    final l = strings(context);
    _changed = true;
    if (result == EntryResult.unknown) {
      // The pending-operations notice lives on the workspace pages: go back to
      // them, so the saved action is in plain view instead of hidden behind this one.
      showFeedback(context, l.outcomeUnknownNotice);
      Navigator.of(context).pop(true);
      return;
    }
    showFeedback(context, l.deliveryPosted);
    _reload();
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
        appBar: AppBar(title: Text(l.order)),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 860),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: AsyncSection<PurchaseOrder>(
                  key: _section,
                  load: () => widget.repository.order(widget.orderId),
                  builder: _body,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, PurchaseOrder order) {
    final l = strings(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    orderNumber(order.number),
                    key: const ValueKey('od-number'),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  StatusPill(
                    key: const ValueKey('od-status'),
                    label: orderStatusLabel(l, order.status),
                    warning: order.status != 'received',
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text('${order.supplierName} → ${order.locationName}'),
              if (order.expectedDate != null)
                Text(
                  l.expectedOn(order.expectedDate!),
                  style: const TextStyle(color: AppColors.muted),
                ),
              if (order.notes.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(order.notes),
              ],
              if (order.cancelReason.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  l.cancelledBecause(order.cancelReason),
                  style: const TextStyle(color: AppColors.warning),
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
              SectionHeading(l.orderLinesTitle),
              const SizedBox(height: 8),
              if (order.lines.isEmpty) const Text('—'),
              for (final line in order.lines)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Wrap(
                    spacing: 16,
                    runSpacing: 4,
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      ConstrainedBox(
                        constraints: const BoxConstraints(
                          minWidth: 200,
                          maxWidth: 480,
                        ),
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
                              line.product.sku,
                              style: const TextStyle(
                                color: AppColors.muted,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            l.orderProgress(
                              quantityWithUnit(
                                line.quantityMilli,
                                line.product.unit,
                              ),
                              quantityWithUnit(
                                line.receivedMilli,
                                line.product.unit,
                              ),
                            ),
                            key: ValueKey('od-line-${line.product.sku}'),
                          ),
                          if (line.unitCostMinor != null &&
                              line.lineTotalMinor != null)
                            Text(
                              '${formatMoney(line.unitCostMinor!, 'TMT')} → '
                              '${formatMoney(line.lineTotalMinor!, 'TMT')}',
                              style: const TextStyle(
                                color: AppColors.muted,
                                fontSize: 12,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              if (order.totalMinor != null) ...[
                const Divider(),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    l.orderTotal(formatMoney(order.totalMinor!, 'TMT')),
                    key: const ValueKey('od-total'),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
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
              SectionHeading(l.deliveriesTitle),
              const SizedBox(height: 8),
              if (order.deliveries.isEmpty)
                Text(
                  l.noDeliveries,
                  style: const TextStyle(color: AppColors.muted),
                ),
              for (final d in order.deliveries)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l.deliveryEntry(
                          d.number,
                          formatStamp(d.receivedAt),
                          d.receivedBy,
                        ),
                        key: ValueKey('od-delivery-${d.number}'),
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      for (final dl in d.lines)
                        Text(
                          '${dl.product.name}: '
                          '${quantityWithUnit(dl.quantityMilli, dl.product.unit)}',
                          style: const TextStyle(fontSize: 13),
                        ),
                      if (widget.session.can('supplier_return.create') &&
                          d.hasReturnable &&
                          d.id.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: OutlinedButton.icon(
                            key: ValueKey('od-return-${d.number}'),
                            onPressed: () => _returnToSupplier(order, d),
                            icon: const Icon(Icons.undo),
                            label: Text(l.supplierReturnNew),
                          ),
                        ),
                      if (d.note.isNotEmpty)
                        Text(
                          d.note,
                          style: const TextStyle(
                            color: AppColors.muted,
                            fontSize: 13,
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            if (order.isDraft && _canManage) ...[
              OutlinedButton.icon(
                key: const ValueKey('od-edit'),
                onPressed: _busy ? null : () => _edit(order),
                icon: const Icon(Icons.edit_outlined),
                label: Text(l.editOrder),
              ),
              GradientButton(
                key: const ValueKey('od-submit'),
                label: l.submitOrder,
                icon: Icons.send_outlined,
                onPressed: _busy ? null : () => _submitOrder(order),
              ),
            ],
            if (order.isOpen && _canReceive)
              GradientButton(
                key: const ValueKey('od-receive'),
                label: l.receiveGoods,
                icon: Icons.inventory_2_outlined,
                onPressed: _busy ? null : () => _receive(order),
              ),
            if (order.canCancel && _canManage)
              OutlinedButton.icon(
                key: const ValueKey('od-cancel'),
                onPressed: _busy ? null : () => _cancel(order),
                icon: const Icon(Icons.block_outlined),
                label: Text(l.cancelOrder),
              ),
          ],
        ),
      ],
    );
  }
}
