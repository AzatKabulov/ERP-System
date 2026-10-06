import 'package:flutter/material.dart';

import '../../core/api/api_error_text.dart';
import '../../core/api/api_exception.dart';
import '../../core/money/decimal_math.dart';
import '../../core/session/session_controller.dart';
import '../../core/session/session_models.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../catalog/catalog_models.dart';
import '../catalog/catalog_repository.dart';
import '../catalog/product_picker.dart';
import '../catalog/reference_picker.dart';
import '../inventory/inventory_models.dart';
import '../inventory/quantity_input.dart';
import '../shared/async_section.dart';
import '../workspace/unsaved_work.dart';
import 'purchasing_models.dart';
import 'purchasing_repository.dart';
import 'suppliers_screen.dart';

/// Create a purchase order, or edit one that is still a draft. An order never moves
/// stock: only receiving goods does. Returns the saved order, or null if abandoned.
class OrderFormScreen extends StatefulWidget {
  const OrderFormScreen({
    super.key,
    required this.session,
    required this.repository,
    required this.catalog,
    required this.unsaved,
    this.existing,
  });

  final SessionController session;
  final PurchasingRepository repository;
  final CatalogRepository catalog;
  final UnsavedWork unsaved;
  final PurchaseOrder? existing;

  @override
  State<OrderFormScreen> createState() => _OrderFormScreenState();
}

class _OrderFormScreenState extends State<OrderFormScreen> {
  late final Future<List<Supplier>> _suppliers = widget.repository
      .suppliers(limit: 200)
      .then((page) => page.items);
  List<Supplier> _supplierList = const [];
  late String? _supplierId = widget.existing?.supplierId;
  late String? _locationId =
      widget.existing?.locationId ??
      widget.session.location?.id ??
      widget.session.membership?.locations.firstOrNull?.id;
  late String? _date = widget.existing?.expectedDate;
  late final _notes = TextEditingController(text: widget.existing?.notes ?? '');
  late final List<OrderDraftLine> _lines = [
    for (final l in widget.existing?.lines ?? const <OrderLine>[])
      OrderDraftLine(
        product: l.product,
        quantityText: formatQuantity(
          l.quantityMilli,
          l.product.unit.decimalPlaces,
        ),
        costText: l.unitCostMinor == null
            ? ''
            : toServerDecimal(l.unitCostMinor!, 2).replaceAll('.', ','),
      ),
  ];
  bool _dirty = false;
  bool _submitted = false;
  bool _saving = false;
  ApiException? _error;

  @override
  void dispose() {
    widget.unsaved.mark(this, dirty: false);
    _notes.dispose();
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
    final Product? product = await showProductPicker(context, widget.catalog);
    if (product == null || !mounted) return;
    if (_lines.any((l) => l.product.id == product.id)) {
      showFeedback(context, strings(context).fieldDuplicateProduct);
      return;
    }
    _lines.add(
      OrderDraftLine(
        product: ProductRef.fromProduct(product),
        costText: product.defaultCostMinor == null
            ? ''
            : toServerDecimal(
                product.defaultCostMinor!,
                2,
              ).replaceAll('.', ','),
      ),
    );
    _touch();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final initial = _date == null ? now : DateTime.tryParse(_date!) ?? now;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 3),
    );
    if (picked == null || !mounted) return;
    _date =
        '${picked.year.toString().padLeft(4, '0')}-'
        '${picked.month.toString().padLeft(2, '0')}-'
        '${picked.day.toString().padLeft(2, '0')}';
    _touch();
  }

  String? _quantityError(OrderDraftLine line) {
    final l = strings(context);
    if (line.quantityText.trim().isEmpty) return l.fieldRequired;
    return parseQuantity(line.quantityText, line.product.unit) == null
        ? l.fieldQuantityPrecision
        : null;
  }

  String? _costError(OrderDraftLine line) {
    final l = strings(context);
    if (line.costText.trim().isEmpty) return l.fieldRequired;
    return parseScaled(line.costText, 2) == null ? l.fieldInvalid : null;
  }

  bool get _valid =>
      _supplierId != null &&
      _locationId != null &&
      _lines.every((l) => _quantityError(l) == null && _costError(l) == null);

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _submitted = true;
      _error = null;
    });
    if (!_valid) return;
    final repo = widget.repository;
    final body = repo.orderBody(
      supplierId: _supplierId!,
      locationId: _locationId!,
      expectedDate: _date,
      notes: _notes.text.trim(),
      lines: [
        for (final l in _lines)
          (
            productId: l.product.id,
            quantityMilli: parseQuantity(l.quantityText, l.product.unit)!,
            costMinor: parseScaled(l.costText, 2)!,
          ),
      ],
    );
    setState(() => _saving = true);
    try {
      final saved = widget.existing == null
          ? await repo.createOrder(body)
          : await repo.updateOrder(widget.existing!.id, body);
      _dirty = false;
      widget.unsaved.mark(this, dirty: false);
      if (mounted) Navigator.of(context).pop(saved);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = strings(context);
    final locations = widget.session.membership?.locations ?? const [];
    return PopScope(
      canPop: !_dirty || _saving,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final leave = await confirmAction(
          context,
          widget.existing == null ? l.newOrder : l.editOrder,
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
          title: Text(widget.existing == null ? l.newOrder : l.editOrder),
        ),
        body: SafeArea(
          child: FutureBuilder<List<Supplier>>(
            future: _suppliers,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Padding(
                  padding: const EdgeInsets.all(24),
                  child: ErrorPanel(
                    error: snapshot.error!,
                    onRetry: () => Navigator.of(context).pop(),
                  ),
                );
              }
              if (_supplierList.isEmpty) _supplierList = [...snapshot.data!];
              return _form(context, locations);
            },
          ),
        ),
      ),
    );
  }

  Widget _form(BuildContext context, List<LocationInfo> locations) {
    final l = strings(context);
    final general = _error != null && _error!.fields.isEmpty
        ? apiErrorText(l, _error!)
        : null;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              NamedRefPicker(
                key: const ValueKey('of-supplier'),
                label: l.supplierFieldLabel,
                allowNone: false,
                items: [
                  for (final s in _supplierList)
                    NamedRef(id: s.id, name: s.name),
                ],
                value: _supplierId,
                enabled: !_saving,
                errorText: _submitted && _supplierId == null
                    ? l.fieldRequired
                    : fieldError(l, _error, 'supplier'),
                onChanged: (v) {
                  _supplierId = v;
                  _touch();
                },
                onAddNew: () async {
                  final created = await showSupplierDialog(
                    context,
                    widget.repository,
                  );
                  if (created == null) return null;
                  _supplierList = [..._supplierList, created];
                  return NamedRef(id: created.id, name: created.name);
                },
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                key: const ValueKey('of-location'),
                isExpanded: true,
                initialValue: locations.any((x) => x.id == _locationId)
                    ? _locationId
                    : null,
                decoration: InputDecoration(
                  labelText: l.deliverToLabel,
                  errorText: _submitted && _locationId == null
                      ? l.fieldRequired
                      : fieldError(l, _error, 'location'),
                ),
                items: [
                  for (final x in locations)
                    DropdownMenuItem<String>(value: x.id, child: Text(x.name)),
                ],
                onChanged: _saving
                    ? null
                    : (v) {
                        _locationId = v;
                        _touch();
                      },
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    _date == null
                        ? l.expectedDateLabel
                        : '${l.expectedDateLabel}: $_date',
                    key: const ValueKey('of-date-text'),
                  ),
                  OutlinedButton.icon(
                    key: const ValueKey('of-date'),
                    onPressed: _saving ? null : _pickDate,
                    icon: const Icon(Icons.event_outlined),
                    label: Text(l.pickDate),
                  ),
                  if (_date != null)
                    IconButton(
                      key: const ValueKey('of-date-clear'),
                      tooltip: l.widgetClearButtonTooltip,
                      onPressed: _saving
                          ? null
                          : () {
                              _date = null;
                              _touch();
                            },
                      icon: const Icon(Icons.close),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                key: const ValueKey('of-notes'),
                controller: _notes,
                enabled: !_saving,
                minLines: 1,
                maxLines: 4,
                onChanged: (_) => _touch(),
                decoration: InputDecoration(labelText: l.notesLabel),
              ),
              const SizedBox(height: 24),
              SectionHeading(l.orderLinesTitle),
              const SizedBox(height: 12),
              for (var i = 0; i < _lines.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _OrderLineEditor(
                    key: ObjectKey(_lines[i]),
                    index: i,
                    line: _lines[i],
                    enabled: !_saving,
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
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  key: const ValueKey('of-add-line'),
                  onPressed: _saving ? null : _addProduct,
                  icon: const Icon(Icons.add),
                  label: Text(l.addLineProduct),
                ),
              ),
              if (_error != null &&
                  _error!.fields['lines'] != null &&
                  _error!.fields['lines']!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    fieldError(l, _error, 'lines') ?? '',
                    style: const TextStyle(color: AppColors.danger),
                  ),
                ),
              if (general != null) ...[
                const SizedBox(height: 16),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    general,
                    key: const ValueKey('of-error'),
                    style: const TextStyle(color: AppColors.danger),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              GradientButton(
                key: const ValueKey('of-save'),
                label: l.save,
                icon: Icons.check,
                onPressed: _saving ? null : _save,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OrderLineEditor extends StatefulWidget {
  const _OrderLineEditor({
    super.key,
    required this.index,
    required this.line,
    required this.enabled,
    required this.onChanged,
    required this.onRemove,
    this.quantityError,
    this.costError,
  });

  final int index;
  final OrderDraftLine line;
  final bool enabled;
  final VoidCallback onChanged;
  final VoidCallback onRemove;
  final String? quantityError;
  final String? costError;

  @override
  State<_OrderLineEditor> createState() => _OrderLineEditorState();
}

class _OrderLineEditorState extends State<_OrderLineEditor> {
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
                key: ValueKey('of-remove-${widget.index}'),
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
              SizedBox(
                width: 180,
                child: TextField(
                  key: ValueKey('of-qty-${widget.index}'),
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
              SizedBox(
                width: 220,
                child: TextField(
                  key: ValueKey('of-cost-${widget.index}'),
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
            ],
          ),
        ],
      ),
    );
  }
}
