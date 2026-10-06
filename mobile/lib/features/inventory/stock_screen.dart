import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/connectivity/connection_monitor.dart';
import '../../core/money/decimal_math.dart';
import '../../core/operations/operation_runner.dart';
import '../../core/session/session_controller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../catalog/catalog_repository.dart';
import '../scanning/barcode_input.dart';
import '../shared/async_section.dart';
import '../workspace/unsaved_work.dart';
import 'inventory_models.dart';
import 'inventory_repository.dart';
import 'movements_screen.dart';
import 'quantity_input.dart';
import 'stock_entry_screen.dart';
import 'stock_labels.dart';

/// Current stock per product, location and condition, read from the ledger's
/// balances. Everything shown is what the server returned for this person: only
/// their locations, and costs only for roles that may see them.
class StockScreen extends StatefulWidget {
  const StockScreen({
    super.key,
    required this.session,
    required this.repository,
    required this.catalog,
    required this.runner,
    required this.monitor,
    required this.unsaved,
  });

  final SessionController session;
  final InventoryRepository repository;
  final CatalogRepository catalog;
  final OperationRunner runner;
  final ConnectionMonitor monitor;
  final UnsavedWork unsaved;

  @override
  State<StockScreen> createState() => _StockScreenState();
}

class _StockScreenState extends State<StockScreen> {
  static const _pageSize = 30;

  final _search = TextEditingController();
  Timer? _debounce;
  List<StockRow> _items = const [];
  int _count = 0;
  bool _loading = true;
  Object? _error;
  String? _locationId; // null = every location this person may see
  int _request = 0;

  SessionController get session => widget.session;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({required bool reset}) async {
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = null;
      if (reset) _items = const [];
    });
    try {
      final page = await widget.repository.stock(
        query: _search.text,
        locationId: _locationId,
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

  void _typed(String _) {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 350),
      () => _load(reset: true),
    );
  }

  Future<void> _enter(StockEntryMode mode) async {
    final result = await Navigator.of(context).push<EntryResult>(
      MaterialPageRoute(
        builder: (_) => StockEntryScreen(
          mode: mode,
          session: session,
          repository: widget.repository,
          catalog: widget.catalog,
          runner: widget.runner,
          monitor: widget.monitor,
          unsaved: widget.unsaved,
        ),
      ),
    );
    if (result == null || !mounted) return;
    final l = strings(context);
    showFeedback(
      context,
      result == EntryResult.posted ? l.entryPosted : l.outcomeUnknownNotice,
    );
    if (result == EntryResult.posted) _load(reset: true);
  }

  void _history({ProductRef? product}) => Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => MovementsScreen(
        repository: widget.repository,
        product: product,
        canSeeCost: session.can('stock.cost.view'),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final l = strings(context);
    final locations = session.membership?.locations ?? const [];
    final searching = _search.text.trim().isNotEmpty || _locationId != null;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.start,
          children: [
            SizedBox(
              width: 440,
              child: BarcodeInput(
                fieldKey: const ValueKey('stock-search'),
                controller: _search,
                label: l.searchProducts,
                onChanged: _typed,
                onSubmitted: (_) {
                  _debounce?.cancel();
                  _load(reset: true);
                },
                onScanned: (_) {
                  _debounce?.cancel();
                  _load(reset: true);
                },
              ),
            ),
            if (session.can('stock.history.view'))
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: OutlinedButton.icon(
                  key: const ValueKey('stock-history'),
                  onPressed: () => _history(),
                  icon: const Icon(Icons.history),
                  label: Text(l.movementHistory),
                ),
              ),
            if (session.can('stock.opening.post'))
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: OutlinedButton.icon(
                  key: const ValueKey('stock-opening'),
                  onPressed: () => _enter(StockEntryMode.opening),
                  icon: const Icon(Icons.playlist_add),
                  label: Text(l.openingStock),
                ),
              ),
            if (session.can('stock.adjust'))
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: OutlinedButton.icon(
                  key: const ValueKey('stock-adjust'),
                  onPressed: () => _enter(StockEntryMode.adjustment),
                  icon: const Icon(Icons.tune),
                  label: Text(l.adjustStock),
                ),
              ),
          ],
        ),
        if (locations.length > 1) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                key: const ValueKey('stock-location-all'),
                label: Text(l.allLocationsLabel),
                selected: _locationId == null,
                onSelected: (_) {
                  _locationId = null;
                  _load(reset: true);
                },
              ),
              for (final location in locations)
                ChoiceChip(
                  key: ValueKey('stock-location-${location.name}'),
                  label: Text(location.name),
                  selected: _locationId == location.id,
                  onSelected: (_) {
                    _locationId = location.id;
                    _load(reset: true);
                  },
                ),
            ],
          ),
        ],
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
            child: searching
                ? EmptyState(title: l.noResults, subtitle: l.noResultsHint)
                : EmptyState(
                    key: const ValueKey('stock-empty'),
                    title: l.stockEmpty,
                    subtitle: l.stockEmptyHint,
                    icon: Icons.inventory_2_outlined,
                  ),
          )
        else ...[
          for (final row in _items)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _StockTile(
                row: row,
                onTap: session.can('stock.history.view')
                    ? () => _history(product: row.product)
                    : null,
              ),
            ),
          if (_items.length < _count)
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton(
                key: const ValueKey('stock-load-more'),
                onPressed: _loading ? null : () => _load(reset: false),
                child: Text(l.loadMore),
              ),
            ),
        ],
      ],
    );
  }
}

class _StockTile extends StatelessWidget {
  const _StockTile({required this.row, this.onTap});
  final StockRow row;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l = strings(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: ValueKey(
          'stock-${row.product.sku}-${row.locationName}-${row.condition}',
        ),
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
                constraints: const BoxConstraints(minWidth: 200, maxWidth: 560),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      row.product.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${row.product.sku} · ${row.locationName}',
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
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    quantityWithUnit(row.quantityMilli, row.product.unit),
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                  if (row.valueMinor != null)
                    Text(
                      l.stockValueLabel(formatMoney(row.valueMinor!, 'TMT')),
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 12,
                      ),
                    ),
                  if (row.condition != 'sellable')
                    StatusPill(
                      label: conditionLabel(l, row.condition),
                      warning: true,
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
