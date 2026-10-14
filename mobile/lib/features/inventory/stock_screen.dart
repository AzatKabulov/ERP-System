import 'dart:async';

import 'package:flutter/material.dart';
import '../../widgets/app_icons.dart';

import '../../core/connectivity/connection_monitor.dart';
import '../../l10n/app_localizations.dart';
import '../../core/money/decimal_math.dart';
import '../../core/operations/operation_runner.dart';
import '../../core/session/session_controller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../admin/admin_repository.dart';
import '../catalog/catalog_repository.dart';
import '../counts/counts_repository.dart';
import '../counts/counts_screen.dart';
import '../intake/intake_draft_store.dart';
import '../intake/intake_screen.dart';
import '../scanning/barcode_input.dart';
import '../shared/async_section.dart';
import '../transfers/transfers_repository.dart';
import '../transfers/transfers_screen.dart';
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
  String? _condition; // null = every condition
  _StockTab _tab = _StockTab.location;
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
        condition: _condition,
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

  Future<void> _intake() async {
    final result = await Navigator.of(context).push<EntryResult>(
      MaterialPageRoute(
        builder: (_) => IntakeScreen(
          session: session,
          catalog: widget.catalog,
          runner: widget.runner,
          monitor: widget.monitor,
          store: IntakeDraftStore(
            session.preferences,
            businessId: widget.repository.businessId,
            userId: session.user?.id ?? '',
          ),
        ),
      ),
    );
    if (!mounted) return;
    // whatever happened, the list may have changed (goods received, or answer still pending)
    if (result != null) {
      showFeedback(
        context,
        result == EntryResult.posted
            ? strings(context).entryPosted
            : strings(context).outcomeUnknownNotice,
      );
    }
    _load(reset: true);
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
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) =>
        _page(context, constraints.maxWidth < 600, constraints.maxWidth),
  );

  List<(_StockTab, String)> _tabsFor(AppLocalizations l) => [
    (_StockTab.location, l.stockTabByLocation),
    if (session.can('stock.history.view'))
      (_StockTab.movements, l.movementHistory),
    if (session.can('transfer.view')) (_StockTab.transfers, l.transfersTitle),
    if (session.can('count.view')) (_StockTab.counts, l.countsTitle),
  ];

  Widget _page(BuildContext context, bool compact, double width) {
    final l = strings(context);
    final locations = session.membership?.locations ?? const [];
    final tabs = _tabsFor(l);
    final tab = tabs.any((t) => t.$1 == _tab) ? _tab : _StockTab.location;
    final intake = session.can('intake.create')
        ? PrimaryButton(
            key: const ValueKey('stock-intake'),
            label: l.intakeTitle,
            icon: AppIcons.scan,
            onPressed: _intake,
          )
        : null;
    final others = <Widget>[
      if (session.can('stock.opening.post'))
        OutlinedButton.icon(
          key: const ValueKey('stock-opening'),
          onPressed: () => _enter(StockEntryMode.opening),
          icon: const AppIcon(AppIcons.listPlus, size: 20),
          label: Text(l.openingStock),
        ),
      if (session.can('stock.adjust'))
        OutlinedButton.icon(
          key: const ValueKey('stock-adjust'),
          onPressed: () => _enter(StockEntryMode.adjustment),
          icon: const AppIcon(AppIcons.tune, size: 20),
          label: Text(l.adjustStock),
        ),
    ];
    return ListView(
      padding: EdgeInsets.fromLTRB(
        compact ? 16 : 32,
        compact ? 20 : 32,
        compact ? 16 : 32,
        40,
      ),
      children: [
        PageHead(
          title: l.inventory,
          subtitle: _locationId == null
              ? session.location?.name
              : locations
                    .where((x) => x.id == _locationId)
                    .map((x) => x.name)
                    .firstOrNull,
          actions: [...others, ?intake],
        ),
        const SizedBox(height: 24),
        if (tabs.length > 1) ...[
          AppTabs<_StockTab>(
            keyPrefix: 'stock-tab',
            keyName: (t) => t.name,
            tabs: tabs,
            value: tab,
            onChanged: (t) => setState(() => _tab = t),
          ),
          const SizedBox(height: 24),
        ],
        switch (tab) {
          _StockTab.location => _locationTab(context, compact),
          _StockTab.movements => MovementsScreen(
            embedded: true,
            repository: widget.repository,
            canSeeCost: session.can('stock.cost.view'),
          ),
          _StockTab.transfers => TransfersScreen(
            embedded: true,
            session: session,
            repository: TransfersRepository(
              widget.repository.api,
              widget.repository.businessId,
            ),
            admin: AdminRepository(
              widget.repository.api,
              widget.repository.businessId,
            ),
            catalog: widget.catalog,
            runner: widget.runner,
            monitor: widget.monitor,
            unsaved: widget.unsaved,
          ),
          _StockTab.counts => CountsScreen(
            embedded: true,
            session: session,
            repository: CountsRepository(
              widget.repository.api,
              widget.repository.businessId,
            ),
            catalog: widget.catalog,
            runner: widget.runner,
            monitor: widget.monitor,
            unsaved: widget.unsaved,
          ),
        },
      ],
    );
  }

  /// The "by location" tab: search, the condition and location filters, and the table.
  Widget _locationTab(BuildContext context, bool compact) {
    final l = strings(context);
    final locations = session.membership?.locations ?? const [];
    final searching =
        _search.text.trim().isNotEmpty ||
        _locationId != null ||
        _condition != null;
    final search = BarcodeInput(
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
    );
    final chips = <Widget>[
      ChoiceChip(
        key: const ValueKey('stock-condition-all'),
        label: Text(l.statusAll),
        selected: _condition == null,
        onSelected: (_) {
          _condition = null;
          _load(reset: true);
        },
      ),
      for (final c in _conditions)
        ChoiceChip(
          key: ValueKey('stock-condition-$c'),
          label: Text(conditionLabel(l, c)),
          selected: _condition == c,
          onSelected: (_) {
            _condition = c;
            _load(reset: true);
          },
        ),
      if (locations.length > 1) ...[
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
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (compact) ...[
          search,
          const SizedBox(height: 12),
          _chipScroll(chips),
        ] else
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 420, child: search),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: _chipScroll(chips),
                ),
              ),
            ],
          ),
        const SizedBox(height: 16),
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
                    icon: AppIcons.box,
                  ),
          )
        else ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: _StockTable(
              rows: _items,
              compact: compact,
              onOpen: session.can('stock.history.view')
                  ? (row) => _history(product: row.product)
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

  /// One row of filter chips that scrolls sideways.
  Widget _chipScroll(List<Widget> chips) => SizedBox(
    height: 48,
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final chip in chips)
            Padding(padding: const EdgeInsets.only(right: 8), child: chip),
        ],
      ),
    ),
  );
}

enum _StockTab { location, movements, transfers, counts }

const _conditions = ['sellable', 'damaged', 'inspection', 'in_transit'];

/// The stock list as one card: on a wide screen a header and a column per fact, on a phone two
/// lines per row. A row opens the product's movement history when the person may see it.
class _StockTable extends StatelessWidget {
  const _StockTable({required this.rows, required this.compact, this.onOpen});
  final List<StockRow> rows;
  final bool compact;
  final void Function(StockRow)? onOpen;

  static const _header = TextStyle(
    color: AppColors.muted,
    fontSize: 11,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.7,
  );

  @override
  Widget build(BuildContext context) {
    final l = strings(context);
    final showValue = rows.any((r) => r.valueMinor != null);
    Widget cell(
      int flex,
      Widget child, {
      Alignment align = Alignment.centerLeft,
    }) => Expanded(
      flex: flex,
      child: Align(alignment: align, child: child),
    );
    return SurfaceCard(
      padding: 0,
      child: Column(
        key: const ValueKey('stock-table'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!compact)
            Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              color: AppColors.surfaceSoft,
              child: Row(
                children: [
                  cell(5, Text(l.productName.toUpperCase(), style: _header)),
                  cell(
                    3,
                    Text(l.locationFieldLabel.toUpperCase(), style: _header),
                  ),
                  cell(3, Text(l.conditionLabel.toUpperCase(), style: _header)),
                  cell(
                    2,
                    Text(l.quantity.toUpperCase(), style: _header),
                    align: Alignment.centerRight,
                  ),
                  if (showValue)
                    cell(
                      2,
                      Text(l.stockValue.toUpperCase(), style: _header),
                      align: Alignment.centerRight,
                    ),
                ],
              ),
            ),
          for (var i = 0; i < rows.length; i++)
            InkWell(
              key: ValueKey(
                'stock-${rows[i].product.sku}-${rows[i].locationName}-${rows[i].condition}',
              ),
              onTap: onOpen == null ? null : () => onOpen!(rows[i]),
              hoverColor: AppColors.surfaceSoft,
              child: Container(
                constraints: const BoxConstraints(minHeight: 64),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  border: i == 0 && compact
                      ? null
                      : const Border(top: BorderSide(color: AppColors.line)),
                ),
                child: compact
                    ? _CompactRow(row: rows[i])
                    : _WideRow(row: rows[i], showValue: showValue),
              ),
            ),
        ],
      ),
    );
  }
}

class _Identity extends StatelessWidget {
  const _Identity({required this.row, this.withLocation = false});
  final StockRow row;
  final bool withLocation;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        row.product.name,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
      ),
      const SizedBox(height: 2),
      Text(
        withLocation
            ? '${row.product.sku} · ${row.locationName}'
            : row.product.sku,
        style: const TextStyle(
          fontFamily: AppFonts.mono,
          color: AppColors.muted,
          fontSize: 12,
        ),
      ),
    ],
  );
}

class _ConditionBadge extends StatelessWidget {
  const _ConditionBadge({required this.condition});
  final String condition;

  @override
  Widget build(BuildContext context) {
    final l = strings(context);
    final sellable = condition == 'sellable';
    final transit = condition == 'in_transit';
    return StatusPill(
      label: conditionLabel(l, condition),
      tone: sellable
          ? StatusTone.success
          : transit
          ? StatusTone.info
          : StatusTone.warning,
      icon: sellable
          ? AppIcons.check
          : transit
          ? AppIcons.truck
          : AppIcons.warning,
    );
  }
}

class _WideRow extends StatelessWidget {
  const _WideRow({required this.row, required this.showValue});
  final StockRow row;
  final bool showValue;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(flex: 5, child: _Identity(row: row)),
      Expanded(
        flex: 3,
        child: Text(row.locationName, style: const TextStyle(fontSize: 13)),
      ),
      Expanded(
        flex: 3,
        child: Align(
          alignment: Alignment.centerLeft,
          child: _ConditionBadge(condition: row.condition),
        ),
      ),
      Expanded(
        flex: 2,
        child: Text(
          quantityWithUnit(row.quantityMilli, row.product.unit),
          textAlign: TextAlign.right,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 13,
            fontFeatures: AppFonts.tabular,
          ),
        ),
      ),
      if (showValue)
        Expanded(
          flex: 2,
          child: Text(
            row.valueMinor == null ? '' : formatMoney(row.valueMinor!, 'TMT'),
            textAlign: TextAlign.right,
            style: const TextStyle(
              fontSize: 13,
              fontFeatures: AppFonts.tabular,
            ),
          ),
        ),
    ],
  );
}

class _CompactRow extends StatelessWidget {
  const _CompactRow({required this.row});
  final StockRow row;

  @override
  Widget build(BuildContext context) {
    final l = strings(context);
    return Wrap(
      spacing: 16,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      alignment: WrapAlignment.spaceBetween,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 160, maxWidth: 560),
          child: _Identity(row: row, withLocation: true),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              quantityWithUnit(row.quantityMilli, row.product.unit),
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 15,
                fontFeatures: AppFonts.tabular,
              ),
            ),
            if (row.valueMinor != null)
              Text(
                l.stockValueLabel(formatMoney(row.valueMinor!, 'TMT')),
                style: const TextStyle(color: AppColors.muted, fontSize: 12),
              ),
            if (row.condition != 'sellable') ...[
              const SizedBox(height: 4),
              _ConditionBadge(condition: row.condition),
            ],
          ],
        ),
      ],
    );
  }
}
