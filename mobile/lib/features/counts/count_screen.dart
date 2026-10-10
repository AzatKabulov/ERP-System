import 'package:flutter/material.dart';

import '../../core/api/api_error_text.dart';
import '../../core/api/api_exception.dart';
import '../../core/connectivity/connection_monitor.dart';
import '../../l10n/app_localizations.dart';
import '../../core/format/format_stamp.dart';
import '../../core/money/decimal_math.dart';
import '../../core/operations/operation_runner.dart';
import '../../core/session/session_controller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../catalog/catalog_repository.dart';
import '../catalog/product_picker.dart';
import '../inventory/inventory_models.dart';
import '../inventory/quantity_input.dart';
import '../shared/async_section.dart';
import '../transfers/transfer_detail_screen.dart' show showReasonDialog;
import '../workspace/unsaved_work.dart';
import 'counts_models.dart';
import 'counts_repository.dart';

class _Row {
  _Row(this.product, this.baselineMilli, String text, {this.fresh = false})
    : controller = TextEditingController(text: text);
  final ProductRef product;
  final int baselineMilli;
  final TextEditingController controller;

  /// Added during the count (not on the list the count started with).
  final bool fresh;
}

/// One count. While it is open, type what you find on the shelf (by hand, or add a product
/// by search or camera scan) and send it for approval. An approver reviews the differences,
/// explains them and approves: only then does stock change, through the ledger.
class CountScreen extends StatefulWidget {
  const CountScreen({
    super.key,
    required this.countId,
    required this.session,
    required this.repository,
    required this.catalog,
    required this.runner,
    required this.monitor,
    required this.unsaved,
  });

  final String countId;
  final SessionController session;
  final CountsRepository repository;
  final CatalogRepository catalog;
  final OperationRunner runner;
  final ConnectionMonitor monitor;
  final UnsavedWork unsaved;

  @override
  State<CountScreen> createState() => _CountScreenState();
}

class _CountScreenState extends State<CountScreen> {
  StockCountDoc? _doc;
  Object? _loadError;
  bool _loading = true;
  List<_Row> _rows = [];
  final _reason = TextEditingController();
  bool _dirty = false;
  bool _busy = false;
  ApiException? _error;

  SessionController get session => widget.session;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    widget.unsaved.mark(this, dirty: false);
    _reason.dispose();
    for (final r in _rows) {
      r.controller.dispose();
    }
    super.dispose();
  }

  void _setDoc(StockCountDoc doc) {
    for (final r in _rows) {
      r.controller.dispose();
    }
    _doc = doc;
    _rows = [
      for (final line in doc.lines)
        _Row(
          line.product,
          line.baselineMilli,
          line.countedMilli == null
              ? ''
              : formatQuantity(
                  line.countedMilli!,
                  line.product.unit.decimalPlaces,
                ),
        ),
    ];
    _dirty = false;
    widget.unsaved.mark(this, dirty: false);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final doc = await widget.repository.count(widget.countId);
      if (!mounted) return;
      setState(() {
        _setDoc(doc);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e;
        _loading = false;
      });
    }
  }

  void _touch() {
    if (!_dirty) {
      _dirty = true;
      widget.unsaved.mark(this, dirty: true);
    }
    setState(() {});
  }

  /// A typed quantity: empty = not counted yet, 0 = none on the shelf. Null = not valid.
  ({bool counted, int? milli}) _parse(_Row row) {
    final text = row.controller.text.trim();
    if (text.isEmpty) return (counted: false, milli: null);
    final raw = parseScaled(text, 3);
    if (raw == 0) return (counted: true, milli: 0);
    return (counted: true, milli: parseQuantity(text, row.product.unit));
  }

  bool get _entriesValid =>
      _rows.every((r) => !_parse(r).counted || _parse(r).milli != null);

  Map<String, int> _entered() => {
    for (final r in _rows) r.product.id: ?_parse(r).milli,
  };

  Future<StockCountDoc?> _save() async {
    if (!_entriesValid) return null;
    try {
      return await widget.repository.enter(widget.countId, _entered());
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
      return null;
    }
  }

  Future<void> _saveEntries() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final doc = await _save();
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (doc != null) _setDoc(doc);
    });
    if (doc != null) showFeedback(context, strings(context).countEntriesSaved);
  }

  Future<void> _submit() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final saved = await _save();
    if (saved == null) {
      if (mounted) setState(() => _busy = false);
      return;
    }
    try {
      final doc = await widget.repository.submit(widget.countId);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _setDoc(doc);
      });
      showFeedback(context, strings(context).countSubmittedDone);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e;
        });
      }
    }
  }

  Future<void> _addProduct() async {
    final product = await showProductPicker(context, widget.catalog);
    if (product == null || !mounted) return;
    if (_rows.any((r) => r.product.id == product.id)) {
      showFeedback(context, strings(context).fieldDuplicateProduct);
      return;
    }
    // the server notes what the system showed for it when the count started
    _rows.add(_Row(ProductRef.fromProduct(product), 0, '', fresh: true));
    _touch();
  }

  Future<void> _approve(StockCountDoc doc) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final repo = widget.repository;
    final outcome = await widget.runner.submit(
      action: 'count_approve',
      businessId: session.membership!.businessId,
      path: repo.approvePath(doc.id),
      body: repo.approveBody(_reason.text.trim()),
      subject: countNumber(doc.number),
    );
    if (!mounted) return;
    final l = strings(context);
    switch (outcome) {
      case OperationCompleted():
        setState(() => _busy = false);
        showFeedback(context, l.countApprovedDone);
        await _load();
      case OperationUnknown():
        setState(() => _busy = false);
        showFeedback(context, l.outcomeUnknownNotice);
        widget.unsaved.mark(this, dirty: false);
        Navigator.of(context).popUntil((r) => r.isFirst); // where the banner is
      case OperationRejected(:final error):
        setState(() {
          _busy = false;
          _error = error;
        });
    }
  }

  Future<void> _cancel(StockCountDoc doc) async {
    final l = strings(context);
    final reason = await showReasonDialog(
      context,
      title: l.countCancel,
      label: l.cancelReasonLabel,
    );
    if (reason == null || !mounted) return;
    try {
      final done = await widget.repository.cancel(doc.id, reason);
      if (!mounted) return;
      setState(() => _setDoc(done));
      showFeedback(context, l.countCancelledDone);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  String _errorText(AppLocalizations l, ApiException e) {
    if (e.code == 'insufficient_stock') {
      final row = _rows
          .where((r) => r.product.id == e.params['product'])
          .firstOrNull;
      if (row != null) {
        final available =
            parseServerDecimal('${e.params['available']}', 3) ?? 0;
        return l.errorInsufficientNamed(
          row.product.name,
          quantityWithUnit(available, row.product.unit),
        );
      }
    }
    return apiErrorText(l, e);
  }

  @override
  Widget build(BuildContext context) {
    final l = strings(context);
    final doc = _doc;
    return PopScope(
      canPop: !_dirty || _busy,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final leave = await confirmAction(
          context,
          l.countsTitle,
          l.unsavedChangeConflict,
        );
        if (leave && context.mounted) {
          _dirty = false;
          widget.unsaved.mark(this, dirty: false);
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(title: Text(l.countsTitle)),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 820),
              child: _loadError != null
                  ? ErrorPanel(error: _loadError!, onRetry: _load)
                  : _loading || doc == null
                  ? const Center(child: CircularProgressIndicator())
                  : _body(context, doc),
            ),
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, StockCountDoc doc) {
    final l = strings(context);
    final editable = doc.isOpen && session.can('count.perform');
    final canApprove = doc.isSubmitted && session.can('count.approve');
    final needsReason = doc.differenceCount > 0;
    final counted = _rows.where((r) => _parse(r).counted).length;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      l.countNumberTitle(countNumber(doc.number)),
                      key: const ValueKey('cd-number'),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  Flexible(
                    child: StatusPill(
                      key: const ValueKey('cd-status'),
                      label: countStatusLabel(l, doc.status),
                      warning: doc.status != 'approved',
                    ),
                  ),
                ],
              ),
              Text(
                '${doc.locationName} · ${formatStamp(doc.createdAt)} · ${doc.createdBy}',
                style: const TextStyle(color: AppColors.muted),
              ),
              Text(
                doc.scope == 'full' ? l.countScopeFull : l.countScopePartial,
                style: const TextStyle(color: AppColors.muted),
              ),
              const SizedBox(height: 4),
              Text(
                l.countProgress(counted, _rows.length),
                key: const ValueKey('cd-progress'),
              ),
              if (doc.decisionReason.isNotEmpty)
                Text(
                  doc.decisionReason,
                  key: const ValueKey('cd-decision'),
                  style: const TextStyle(color: AppColors.muted),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        for (final row in _rows) _lineCard(context, doc, row, editable),
        if (editable)
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              key: const ValueKey('count-add-line'),
              onPressed: _busy ? null : _addProduct,
              icon: const Icon(Icons.add),
              label: Text(l.addLineProduct),
            ),
          ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Semantics(
            liveRegion: true,
            child: Text(
              _errorText(l, _error!),
              key: const ValueKey('count-error'),
              style: const TextStyle(color: AppColors.danger),
            ),
          ),
        ],
        const SizedBox(height: 16),
        if (editable)
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              OutlinedButton.icon(
                key: const ValueKey('count-save'),
                onPressed: _busy || !_entriesValid ? null : _saveEntries,
                icon: const Icon(Icons.save_outlined),
                label: Text(l.countSaveEntries),
              ),
              GradientButton(
                key: const ValueKey('count-submit'),
                label: l.countSubmit,
                icon: Icons.send_outlined,
                onPressed: _busy || !_entriesValid || counted == 0
                    ? null
                    : _submit,
              ),
            ],
          ),
        if (canApprove) ...[
          Text(
            needsReason
                ? l.countDifferences(doc.differenceCount)
                : l.countNoDifferences,
            key: const ValueKey('cd-differences'),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          if (needsReason)
            TextField(
              key: const ValueKey('count-reason'),
              controller: _reason,
              enabled: !_busy,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(labelText: l.countExplainLabel),
            ),
          const SizedBox(height: 12),
          ListenableBuilder(
            listenable: widget.monitor,
            builder: (context, _) => GradientButton(
              key: const ValueKey('count-approve'),
              label: l.countApprove,
              icon: Icons.check,
              onPressed:
                  _busy ||
                      !widget.monitor.online ||
                      (needsReason && _reason.text.trim().isEmpty)
                  ? null
                  : () => _approve(doc),
            ),
          ),
        ],
        if ((doc.isOpen || doc.isSubmitted) &&
            session.can('count.perform')) ...[
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const ValueKey('count-cancel'),
              onPressed: _busy ? null : () => _cancel(doc),
              icon: const Icon(Icons.close),
              label: Text(l.countCancel),
            ),
          ),
        ],
      ],
    );
  }

  Widget _lineCard(
    BuildContext context,
    StockCountDoc doc,
    _Row row,
    bool editable,
  ) {
    final l = strings(context);
    final parsed = _parse(row);
    final saved = doc.lines
        .where((x) => x.product.id == row.product.id)
        .firstOrNull;
    final variance = parsed.milli == null
        ? null
        : parsed.milli! - row.baselineMilli;
    final moved = saved?.movedSinceStart ?? false;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SurfaceCard(
        padding: 14,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${row.product.name} · ${row.product.sku}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            Text(
              row.fresh
                  ? ''
                  : l.countSystemLine(
                      quantityWithUnit(row.baselineMilli, row.product.unit),
                    ),
              style: const TextStyle(color: AppColors.muted, fontSize: 13),
            ),
            const SizedBox(height: 8),
            if (editable)
              Semantics(
                container: true,
                explicitChildNodes: true,
                child: SizedBox(
                  width: 200,
                  child: TextField(
                    key: ValueKey('count-counted-${row.product.sku}'),
                    controller: row.controller,
                    enabled: !_busy,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onChanged: (_) => _touch(),
                    decoration: InputDecoration(
                      labelText: l.countCountedLabel,
                      suffixText: row.product.unit.symbol,
                      errorText: parsed.counted && parsed.milli == null
                          ? l.fieldQuantityPrecision
                          : null,
                    ),
                  ),
                ),
              )
            else if (parsed.counted)
              Text(
                '${l.countCountedLabel}: ${quantityWithUnit(parsed.milli ?? 0, row.product.unit)}',
              ),
            if (!row.fresh && variance != null && variance != 0)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  l.countVarianceLine(
                    '${variance > 0 ? '+' : ''}${formatQuantity(variance, row.product.unit.decimalPlaces)} ${row.product.unit.symbol}',
                  ),
                  key: ValueKey('count-variance-${row.product.sku}'),
                  style: const TextStyle(
                    color: AppColors.danger,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            if (moved && parsed.counted)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  l.countMovedNote,
                  key: ValueKey('count-moved-${row.product.sku}'),
                  style: const TextStyle(
                    color: AppColors.warning,
                    fontSize: 12,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
