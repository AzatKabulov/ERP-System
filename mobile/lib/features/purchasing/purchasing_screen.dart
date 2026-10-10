import 'package:flutter/material.dart';

import '../../core/connectivity/connection_monitor.dart';
import '../../core/money/decimal_math.dart';
import '../../core/operations/operation_runner.dart';
import '../../core/session/session_controller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../catalog/catalog_repository.dart';
import '../shared/async_section.dart';
import '../workspace/unsaved_work.dart';
import 'order_detail_screen.dart';
import 'order_form_screen.dart';
import 'order_labels.dart';
import 'purchasing_models.dart';
import 'purchasing_repository.dart';
import 'reorder_screen.dart';
import 'supplier_returns_screen.dart';
import 'suppliers_screen.dart';

/// Purchase orders, newest first, with a status filter. From here: create an order,
/// manage suppliers, open an order to receive goods.
class PurchasingScreen extends StatefulWidget {
  const PurchasingScreen({
    super.key,
    required this.session,
    required this.repository,
    required this.catalog,
    required this.runner,
    required this.monitor,
    required this.unsaved,
  });

  final SessionController session;
  final PurchasingRepository repository;
  final CatalogRepository catalog;
  final OperationRunner runner;
  final ConnectionMonitor monitor;
  final UnsavedWork unsaved;

  @override
  State<PurchasingScreen> createState() => _PurchasingScreenState();
}

class _PurchasingScreenState extends State<PurchasingScreen> {
  static const _pageSize = 30;
  List<OrderSummary> _items = const [];
  int _count = 0;
  bool _loading = true;
  Object? _error;
  String? _status; // null = all
  int _request = 0;

  SessionController get session => widget.session;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  Future<void> _load({required bool reset}) async {
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = null;
      if (reset) _items = const [];
    });
    try {
      final page = await widget.repository.orders(
        statuses: _status == null ? const [] : [_status!],
        offset: reset ? 0 : _items.length,
        limit: _pageSize,
      );
      if (!mounted || request != _request) return;
      setState(() {
        _items = reset ? page.items : [..._items, ...page.items];
        _count = page.count;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || request != _request) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _open(OrderSummary order) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => OrderDetailScreen(
          orderId: order.id,
          session: session,
          repository: widget.repository,
          catalog: widget.catalog,
          runner: widget.runner,
          monitor: widget.monitor,
          unsaved: widget.unsaved,
        ),
      ),
    );
    if (changed == true && mounted) _load(reset: true);
  }

  Future<void> _openReorder() async {
    final saved = await Navigator.of(context).push<PurchaseOrder>(
      MaterialPageRoute(
        builder: (_) => ReorderScreen(
          session: session,
          repository: widget.repository,
          catalog: widget.catalog,
          unsaved: widget.unsaved,
        ),
      ),
    );
    if (saved == null || !mounted) return;
    await _load(reset: true);
    if (mounted && _items.isNotEmpty) {
      await _open(
        _items.firstWhere((o) => o.id == saved.id, orElse: () => _items.first),
      );
    }
  }

  Future<void> _create() async {
    final saved = await Navigator.of(context).push<PurchaseOrder>(
      MaterialPageRoute(
        builder: (_) => OrderFormScreen(
          session: session,
          repository: widget.repository,
          catalog: widget.catalog,
          unsaved: widget.unsaved,
        ),
      ),
    );
    if (saved != null && mounted) {
      showFeedback(context, strings(context).orderSaved);
      await _load(reset: true);
      if (mounted) {
        await _open(
          _items.firstWhere(
            (o) => o.id == saved.id,
            orElse: () => _items.first,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = strings(context);
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (session.can('purchasing.manage'))
              GradientButton(
                key: const ValueKey('order-new'),
                label: l.newOrder,
                icon: Icons.add,
                onPressed: _create,
              ),
            if (session.can('supplier.view'))
              OutlinedButton.icon(
                key: const ValueKey('order-suppliers'),
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute(
                    builder: (_) => SuppliersScreen(
                      session: session,
                      repository: widget.repository,
                    ),
                  ),
                ),
                icon: const Icon(Icons.local_shipping_outlined),
                label: Text(l.suppliersTitle),
              ),
            if (session.can('reorder.view'))
              OutlinedButton.icon(
                key: const ValueKey('purchasing-reorder'),
                onPressed: () => _openReorder(),
                icon: const Icon(Icons.shopping_cart_outlined),
                label: Text(l.reorderTitle),
              ),
            if (session.can('supplier_return.view'))
              OutlinedButton.icon(
                key: const ValueKey('purchasing-returns'),
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute(
                    builder: (_) => SupplierReturnsScreen(
                      session: session,
                      repository: widget.repository,
                    ),
                  ),
                ),
                icon: const Icon(Icons.undo),
                label: Text(l.supplierReturnsTitle),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ChoiceChip(
              key: const ValueKey('order-filter-all'),
              label: Text(l.statusAll),
              selected: _status == null,
              onSelected: (_) {
                _status = null;
                _load(reset: true);
              },
            ),
            for (final status in orderStatuses)
              ChoiceChip(
                key: ValueKey('order-filter-$status'),
                label: Text(orderStatusLabel(l, status)),
                selected: _status == status,
                onSelected: (_) {
                  _status = status;
                  _load(reset: true);
                },
              ),
          ],
        ),
        const SizedBox(height: 20),
        if (_error != null)
          ErrorPanel(error: _error!, onRetry: () => _load(reset: true))
        else if (_loading && _items.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_items.isEmpty)
          SurfaceCard(
            child: EmptyState(
              key: const ValueKey('orders-empty'),
              title: l.noOrders,
              subtitle: l.noOrdersHint,
              icon: Icons.local_shipping_outlined,
            ),
          )
        else ...[
          for (final order in _items)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _OrderTile(order: order, onTap: () => _open(order)),
            ),
          if (_items.length < _count)
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton(
                key: const ValueKey('orders-load-more'),
                onPressed: _loading ? null : () => _load(reset: false),
                child: Text(l.loadMore),
              ),
            ),
        ],
      ],
    );
  }
}

class _OrderTile extends StatelessWidget {
  const _OrderTile({required this.order, required this.onTap});
  final OrderSummary order;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = strings(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: ValueKey('order-${orderNumber(order.number)}'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: SurfaceCard(
          padding: 16,
          child: Wrap(
            spacing: 16,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            alignment: WrapAlignment.spaceBetween,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 200, maxWidth: 520),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${orderNumber(order.number)} · ${order.supplierName}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      order.locationName,
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      l.orderProgress(
                        formatQuantity(order.orderedMilli, 0),
                        formatQuantity(order.receivedMilli, 0),
                      ),
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  StatusPill(
                    label: orderStatusLabel(l, order.status),
                    warning: order.status != 'received',
                  ),
                  if (order.totalMinor != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        formatMoney(order.totalMinor!, 'TMT'),
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
