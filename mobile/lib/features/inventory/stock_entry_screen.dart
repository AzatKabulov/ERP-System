import 'package:flutter/material.dart';

import '../../core/api/api_error_text.dart';
import '../../core/api/api_exception.dart';
import '../../core/connectivity/connection_monitor.dart';
import '../../core/money/decimal_math.dart';
import '../../core/operations/operation_runner.dart';
import '../../core/session/session_controller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../catalog/catalog_repository.dart';
import '../catalog/product_picker.dart';
import '../workspace/unsaved_work.dart';
import 'inventory_models.dart';
import 'inventory_repository.dart';
import 'quantity_input.dart';
import 'stock_labels.dart';

enum StockEntryMode { opening, adjustment }

/// How a stock-changing form ended: the server confirmed, or the answer is
/// unknown and the saved operation is now listed in the pending banner.
enum EntryResult { posted, unknown }

/// Opening stock (first quantities, each with its unit cost) or a stock adjustment
/// (a correction or write-off with a mandatory reason). Both are sent through the
/// [OperationRunner], so a timeout, crash or restart can never post them twice.
class StockEntryScreen extends StatefulWidget {
  const StockEntryScreen({
    super.key,
    required this.mode,
    required this.session,
    required this.repository,
    required this.catalog,
    required this.runner,
    required this.monitor,
    required this.unsaved,
  });

  final StockEntryMode mode;
  final SessionController session;
  final InventoryRepository repository;
  final CatalogRepository catalog;
  final OperationRunner runner;
  final ConnectionMonitor monitor;
  final UnsavedWork unsaved;

  @override
  State<StockEntryScreen> createState() => _StockEntryScreenState();
}

class _StockEntryScreenState extends State<StockEntryScreen> {
  final _lines = <StockEntryLine>[];
  final _text = TextEditingController();
  late String? _locationId =
      widget.session.location?.id ??
      widget.session.membership?.locations.firstOrNull?.id;
  bool _dirty = false;
  bool _submitted = false;
  bool _busy = false;
  ApiException? _error;

  bool get _isOpening => widget.mode == StockEntryMode.opening;

  @override
  void dispose() {
    widget.unsaved.mark(this, dirty: false);
    _text.dispose();
    super.dispose();
  }

  void _touch() {
    if (!_dirty) {
      _dirty = true;
      widget.unsaved.mark(this, dirty: true);
    }
    setState(() {});
  }

  Future<void> _addProduct() async {
    final product = await showProductPicker(context, widget.catalog);
    if (product == null || !mounted) return;
    if (_lines.any((l) => l.product.id == product.id)) {
      showFeedback(context, strings(context).fieldDuplicateProduct);
      return;
    }
    _lines.add(
      StockEntryLine(
        product: ProductRef.fromProduct(product),
        // goods taken out is the common adjustment; opening stock is always incoming
        incoming: _isOpening,
      ),
    );
    _touch();
  }

  String? _quantityError(StockEntryLine line) {
    final l = strings(context);
    if (line.quantityText.trim().isEmpty) return l.fieldRequired;
    return parseQuantity(line.quantityText, line.product.unit) == null
        ? l.fieldQuantityPrecision
        : null;
  }

  bool _needsCost(StockEntryLine line) => _isOpening || line.incoming;

  String? _costError(StockEntryLine line) {
    if (!_needsCost(line)) return null;
    final l = strings(context);
    if (line.costText.trim().isEmpty) return l.fieldRequired;
    return parseScaled(line.costText, 2) == null ? l.fieldInvalid : null;
  }

  bool get _valid =>
      _lines.isNotEmpty &&
      _lines.every((l) => _quantityError(l) == null && _costError(l) == null) &&
      (_isOpening || _text.text.trim().isNotEmpty) &&
      _locationId != null;

  Future<void> _submit() async {
    if (_busy) return;
    setState(() {
      _submitted = true;
      _error = null;
    });
    if (!_valid) return;
    final repo = widget.repository;
    final businessId = widget.session.membership!.businessId;
    final Map<String, dynamic> body;
    if (_isOpening) {
      body = repo.openingBody(
        locationId: _locationId!,
        note: _text.text.trim(),
        lines: [
          for (final l in _lines)
            (
              productId: l.product.id,
              quantityMilli: parseQuantity(l.quantityText, l.product.unit)!,
              costMinor: parseScaled(l.costText, 2)!,
            ),
        ],
      );
    } else {
      body = repo.adjustmentBody(
        locationId: _locationId!,
        reason: _text.text.trim(),
        lines: [
          for (final l in _lines)
            (
              productId: l.product.id,
              incoming: l.incoming,
              quantityMilli: parseQuantity(l.quantityText, l.product.unit)!,
              costMinor: l.incoming ? parseScaled(l.costText, 2) : null,
              condition: l.condition,
            ),
        ],
      );
    }
    setState(() => _busy = true);
    final outcome = await widget.runner.submit(
      action: _isOpening ? 'stock_opening' : 'stock_adjust',
      businessId: businessId,
      path: _isOpening ? repo.openingPath : repo.adjustmentPath,
      body: body,
    );
    if (!mounted) return;
    switch (outcome) {
      case OperationCompleted():
        _finish(EntryResult.posted);
      case OperationUnknown():
        _finish(EntryResult.unknown);
      case OperationRejected(:final error):
        setState(() {
          _busy = false;
          _error = error;
        });
    }
  }

  void _finish(EntryResult result) {
    _dirty = false;
    widget.unsaved.mark(this, dirty: false);
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final l = strings(context);
    final locations = widget.session.membership?.locations ?? const [];
    return PopScope(
      canPop: !_dirty || _busy,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final leave = await confirmAction(
          context,
          _isOpening ? l.openingStock : l.adjustStock,
          l.unsavedChangeConflict,
        );
        if (leave && context.mounted) {
          _dirty = false;
          widget.unsaved.mark(this, dirty: false);
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_isOpening ? l.openingStock : l.adjustStock),
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DropdownButtonFormField<String>(
                      key: const ValueKey('entry-location'),
                      isExpanded: true,
                      initialValue: locations.any((x) => x.id == _locationId)
                          ? _locationId
                          : null,
                      decoration: InputDecoration(
                        labelText: l.locationFieldLabel,
                        errorText: _submitted && _locationId == null
                            ? l.fieldRequired
                            : null,
                      ),
                      items: [
                        for (final location in locations)
                          DropdownMenuItem(
                            value: location.id,
                            child: Text(location.name),
                          ),
                      ],
                      onChanged: _busy
                          ? null
                          : (v) {
                              _locationId = v;
                              _touch();
                            },
                    ),
                    const SizedBox(height: 20),
                    for (var i = 0; i < _lines.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _EntryLineEditor(
                          key: ObjectKey(_lines[i]),
                          index: i,
                          line: _lines[i],
                          opening: _isOpening,
                          enabled: !_busy,
                          quantityError: _submitted
                              ? _quantityError(_lines[i])
                              : null,
                          costError: _submitted ? _costError(_lines[i]) : null,
                          onChanged: _touch,
                          onRemove: () {
                            _lines.removeAt(i);
                            _touch();
                          },
                        ),
                      ),
                    if (_submitted && _lines.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          l.entryNeedsLines,
                          key: const ValueKey('entry-needs-lines'),
                          style: const TextStyle(color: AppColors.danger),
                        ),
                      ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                        key: const ValueKey('entry-add-line'),
                        onPressed: _busy ? null : _addProduct,
                        icon: const Icon(Icons.add),
                        label: Text(l.addLineProduct),
                      ),
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      key: const ValueKey('entry-reason'),
                      controller: _text,
                      enabled: !_busy,
                      onChanged: (_) => _touch(),
                      decoration: InputDecoration(
                        labelText: _isOpening ? l.noteLabel : l.reasonLabel,
                        errorText:
                            _submitted &&
                                !_isOpening &&
                                _text.text.trim().isEmpty
                            ? l.fieldRequired
                            : null,
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          apiErrorText(l, _error!),
                          key: const ValueKey('entry-error'),
                          style: const TextStyle(color: AppColors.danger),
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
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
                            key: const ValueKey('entry-submit'),
                            label: _isOpening
                                ? l.postOpening
                                : l.postAdjustment,
                            icon: Icons.check,
                            onPressed: _busy || !widget.monitor.online
                                ? null
                                : _submit,
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

class _EntryLineEditor extends StatefulWidget {
  const _EntryLineEditor({
    super.key,
    required this.index,
    required this.line,
    required this.opening,
    required this.enabled,
    required this.onChanged,
    required this.onRemove,
    this.quantityError,
    this.costError,
  });

  final int index;
  final StockEntryLine line;
  final bool opening;
  final bool enabled;
  final VoidCallback onChanged;
  final VoidCallback onRemove;
  final String? quantityError;
  final String? costError;

  @override
  State<_EntryLineEditor> createState() => _EntryLineEditorState();
}

class _EntryLineEditorState extends State<_EntryLineEditor> {
  late final _quantity = TextEditingController(text: widget.line.quantityText);
  late final _cost = TextEditingController(text: widget.line.costText);

  @override
  void dispose() {
    _quantity.dispose();
    _cost.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = strings(context);
    final line = widget.line;
    final needsCost = widget.opening || line.incoming;
    return SurfaceCard(
      padding: 14,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      line.product.name,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      '${line.product.sku} · ${line.product.unit.symbol}',
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                key: ValueKey('entry-remove-${widget.index}'),
                tooltip: l.removeLine,
                onPressed: widget.enabled ? widget.onRemove : null,
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.start,
            children: [
              if (!widget.opening)
                SegmentedButton<bool>(
                  key: ValueKey('entry-direction-${widget.index}'),
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(
                      value: true,
                      label: Text(
                        l.directionIn,
                        key: ValueKey('entry-in-${widget.index}'),
                      ),
                    ),
                    ButtonSegment(
                      value: false,
                      label: Text(
                        l.directionOut,
                        key: ValueKey('entry-out-${widget.index}'),
                      ),
                    ),
                  ],
                  selected: {line.incoming},
                  onSelectionChanged: widget.enabled
                      ? (s) {
                          line.incoming = s.first;
                          widget.onChanged();
                        }
                      : null,
                ),
              SizedBox(
                width: 180,
                child: TextField(
                  key: ValueKey('entry-qty-${widget.index}'),
                  controller: _quantity,
                  enabled: widget.enabled,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  onChanged: (v) {
                    line.quantityText = v;
                    widget.onChanged();
                  },
                  decoration: InputDecoration(
                    labelText: l.quantity,
                    errorText: widget.quantityError,
                    errorMaxLines: 3,
                  ),
                ),
              ),
              if (needsCost)
                SizedBox(
                  width: 220,
                  child: TextField(
                    key: ValueKey('entry-cost-${widget.index}'),
                    controller: _cost,
                    enabled: widget.enabled,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onChanged: (v) {
                      line.costText = v;
                      widget.onChanged();
                    },
                    decoration: InputDecoration(
                      labelText: l.unitCostLabel,
                      errorText: widget.costError,
                      errorMaxLines: 3,
                    ),
                  ),
                ),
              if (!widget.opening)
                SizedBox(
                  width: 220,
                  child: DropdownButtonFormField<String>(
                    key: ValueKey('entry-condition-${widget.index}'),
                    isExpanded: true,
                    initialValue: line.condition,
                    decoration: InputDecoration(labelText: l.conditionLabel),
                    items: [
                      for (final c in const [
                        'sellable',
                        'damaged',
                        'inspection',
                      ])
                        DropdownMenuItem(
                          value: c,
                          child: Text(conditionLabel(l, c)),
                        ),
                    ],
                    onChanged: widget.enabled
                        ? (v) {
                            line.condition = v ?? 'sellable';
                            widget.onChanged();
                          }
                        : null,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
