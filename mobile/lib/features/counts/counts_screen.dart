import 'package:flutter/material.dart';

import '../../core/api/api_error_text.dart';
import '../../core/api/api_exception.dart';
import '../../core/connectivity/connection_monitor.dart';
import '../../core/format/format_stamp.dart';
import '../../core/operations/operation_runner.dart';
import '../../core/session/session_controller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../catalog/catalog_repository.dart';
import '../catalog/product_picker.dart';
import '../inventory/inventory_models.dart';
import '../shared/async_section.dart';
import '../workspace/unsaved_work.dart';
import 'count_screen.dart';
import 'counts_models.dart';
import 'counts_repository.dart';

/// Stock counts, newest first. From here: start a count, or open one to enter the quantities
/// found on the shelf, send it for approval, or (for an approver) review and approve it.
class CountsScreen extends StatefulWidget {
  const CountsScreen({
    super.key,
    required this.session,
    required this.repository,
    required this.catalog,
    required this.runner,
    required this.monitor,
    required this.unsaved,
  });

  final SessionController session;
  final CountsRepository repository;
  final CatalogRepository catalog;
  final OperationRunner runner;
  final ConnectionMonitor monitor;
  final UnsavedWork unsaved;

  @override
  State<CountsScreen> createState() => _CountsScreenState();
}

class _CountsScreenState extends State<CountsScreen> {
  static const _pageSize = 30;
  List<CountSummary> _items = const [];
  int _count = 0;
  bool _loading = true;
  Object? _error;
  String? _status;
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
      final page = await widget.repository.counts(
        status: _status,
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

  Future<void> _open(String id) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => CountScreen(
          countId: id,
          session: session,
          repository: widget.repository,
          catalog: widget.catalog,
          runner: widget.runner,
          monitor: widget.monitor,
          unsaved: widget.unsaved,
        ),
      ),
    );
    if (mounted) _load(reset: true);
  }

  Future<void> _start() async {
    final created = await Navigator.of(context).push<StockCountDoc>(
      MaterialPageRoute(
        builder: (_) => CountStartScreen(
          session: session,
          repository: widget.repository,
          catalog: widget.catalog,
        ),
      ),
    );
    if (created == null || !mounted) return;
    await _open(created.id);
  }

  @override
  Widget build(BuildContext context) {
    final l = strings(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.countsTitle)),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                if (session.can('count.perform'))
                  Align(
                    alignment: Alignment.centerLeft,
                    child: GradientButton(
                      key: const ValueKey('count-new'),
                      label: l.countStart,
                      icon: Icons.add,
                      onPressed: _start,
                    ),
                  ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ChoiceChip(
                      key: const ValueKey('count-filter-all'),
                      label: Text(l.statusAll),
                      selected: _status == null,
                      onSelected: (_) {
                        _status = null;
                        _load(reset: true);
                      },
                    ),
                    for (final status in countStatuses)
                      ChoiceChip(
                        key: ValueKey('count-filter-$status'),
                        label: Text(countStatusLabel(l, status)),
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
                      key: const ValueKey('counts-empty'),
                      title: l.countsEmpty,
                      subtitle: '',
                      icon: Icons.fact_check_outlined,
                    ),
                  )
                else ...[
                  for (final c in _items)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          key: ValueKey('count-${countNumber(c.number)}'),
                          borderRadius: BorderRadius.circular(16),
                          onTap: () => _open(c.id),
                          child: SurfaceCard(
                            padding: 16,
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${countNumber(c.number)} · ${c.locationName}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      Text(
                                        formatStamp(c.createdAt),
                                        style: const TextStyle(
                                          color: AppColors.muted,
                                          fontSize: 12,
                                        ),
                                      ),
                                      Text(
                                        '${l.countProgress(c.countedCount, c.lineCount)} · ${l.countDifferences(c.differenceCount)}',
                                        style: const TextStyle(
                                          color: AppColors.muted,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Flexible(
                                  child: StatusPill(
                                    label: countStatusLabel(l, c.status),
                                    warning: c.status != 'approved',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (_items.length < _count)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton(
                        key: const ValueKey('counts-load-more'),
                        onPressed: _loading ? null : () => _load(reset: false),
                        child: Text(l.loadMore),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Choose where to count and whether to count everything there or only some products.
class CountStartScreen extends StatefulWidget {
  const CountStartScreen({
    super.key,
    required this.session,
    required this.repository,
    required this.catalog,
  });

  final SessionController session;
  final CountsRepository repository;
  final CatalogRepository catalog;

  @override
  State<CountStartScreen> createState() => _CountStartScreenState();
}

class _CountStartScreenState extends State<CountStartScreen> {
  late String? _locationId =
      widget.session.location?.id ??
      widget.session.membership?.locations.firstOrNull?.id;
  String _scope = 'full';
  final _products = <ProductRef>[];
  bool _busy = false;
  ApiException? _error;

  Future<void> _add() async {
    final product = await showProductPicker(context, widget.catalog);
    if (product == null || !mounted) return;
    if (_products.any((p) => p.id == product.id)) {
      showFeedback(context, strings(context).fieldDuplicateProduct);
      return;
    }
    setState(() => _products.add(ProductRef.fromProduct(product)));
  }

  bool get _valid =>
      _locationId != null && (_scope == 'full' || _products.isNotEmpty);

  Future<void> _start() async {
    if (_busy || !_valid) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final created = await widget.repository.start(
        locationId: _locationId!,
        scope: _scope,
        productIds: [for (final p in _products) p.id],
      );
      if (mounted) Navigator.of(context).pop(created);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = strings(context);
    final mine = widget.session.membership?.locations ?? const [];
    return Scaffold(
      appBar: AppBar(title: Text(l.countStart)),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DropdownButtonFormField<String>(
                    key: const ValueKey('count-location'),
                    isExpanded: true,
                    initialValue: mine.any((x) => x.id == _locationId)
                        ? _locationId
                        : null,
                    decoration: InputDecoration(
                      labelText: l.locationFieldLabel,
                    ),
                    items: [
                      for (final x in mine)
                        DropdownMenuItem(value: x.id, child: Text(x.name)),
                    ],
                    onChanged: _busy
                        ? null
                        : (v) => setState(() => _locationId = v),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    children: [
                      ChoiceChip(
                        key: const ValueKey('count-scope-full'),
                        label: Text(l.countScopeFull),
                        selected: _scope == 'full',
                        onSelected: (_) => setState(() => _scope = 'full'),
                      ),
                      ChoiceChip(
                        key: const ValueKey('count-scope-partial'),
                        label: Text(l.countScopePartial),
                        selected: _scope == 'partial',
                        onSelected: (_) => setState(() => _scope = 'partial'),
                      ),
                    ],
                  ),
                  if (_scope == 'partial') ...[
                    const SizedBox(height: 12),
                    for (var i = 0; i < _products.length; i++)
                      ListTile(
                        key: ValueKey('count-product-$i'),
                        contentPadding: EdgeInsets.zero,
                        title: Text(_products[i].name),
                        subtitle: Text(_products[i].sku),
                        trailing: IconButton(
                          tooltip: l.removeLine,
                          onPressed: () =>
                              setState(() => _products.removeAt(i)),
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                        key: const ValueKey('count-add-product'),
                        onPressed: _busy ? null : _add,
                        icon: const Icon(Icons.add),
                        label: Text(l.addLineProduct),
                      ),
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      apiErrorText(l, _error!),
                      style: const TextStyle(color: AppColors.danger),
                    ),
                  ],
                  const SizedBox(height: 20),
                  GradientButton(
                    key: const ValueKey('count-start'),
                    label: l.countStart,
                    icon: Icons.fact_check_outlined,
                    onPressed: _busy || !_valid ? null : _start,
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
