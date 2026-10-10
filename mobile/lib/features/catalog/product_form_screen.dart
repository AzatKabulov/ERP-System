import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api/api_error_text.dart';
import '../../core/api/api_exception.dart';
import '../../core/money/decimal_math.dart';
import '../../core/session/session_controller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../scanning/barcode_input.dart';
import '../shared/async_section.dart';
import '../workspace/unsaved_work.dart';
import 'catalog_models.dart';
import 'catalog_repository.dart';
import 'reference_picker.dart';

class _FormData {
  const _FormData(this.units, this.categories, this.brands, this.rate);
  final List<UnitRef> units;
  final List<NamedRef> categories;
  final List<NamedRef> brands;

  /// TMT per 1 USD, or null when no rate has been entered.
  final String? rate;
}

/// Create or edit a product. Returns the saved [Product], or null if abandoned.
class ProductFormScreen extends StatefulWidget {
  const ProductFormScreen({
    super.key,
    required this.repository,
    required this.session,
    required this.unsaved,
    this.existing,
    this.initialBarcode,
  });

  final CatalogRepository repository;
  final SessionController session;
  final UnsavedWork unsaved;
  final Product? existing;

  /// Pre-fills a barcode, e.g. after a scan found no product.
  final String? initialBarcode;

  @override
  State<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends State<ProductFormScreen> {
  late final Future<_FormData> _data = _load();
  late final _sku = TextEditingController(text: widget.existing?.sku ?? '');
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _price = TextEditingController(
    text: widget.existing == null
        ? ''
        : toServerDecimal(widget.existing!.priceMinor, 2).replaceAll('.', ','),
  );
  late final _cost = TextEditingController(
    text: widget.existing?.defaultCostMinor == null
        ? ''
        : toServerDecimal(
            widget.existing!.defaultCostMinor!,
            2,
          ).replaceAll('.', ','),
  );
  late final _warrantyMonths = TextEditingController(
    text: '${widget.existing?.warrantyMonths ?? 0}',
  );
  late final _warrantyTerms = TextEditingController(
    text: widget.existing?.warrantyTerms ?? '',
  );
  late final _returnDays = TextEditingController(
    text: widget.existing?.returnDays?.toString() ?? '',
  );
  final _barcodeEntry = TextEditingController();

  late String? _categoryId = widget.existing?.category?.id;
  late String? _brandId = widget.existing?.brand?.id;
  late String? _unitId = widget.existing?.unit.id;
  late String _currency = widget.existing?.priceCurrency ?? 'TMT';
  late final List<String> _barcodes = [
    ...?widget.existing?.barcodes,
    if (widget.initialBarcode != null && widget.initialBarcode!.isNotEmpty)
      widget.initialBarcode!,
  ];

  // Lists can grow while the form is open (an entry created through "add new").
  List<UnitRef> _units = const [];
  List<NamedRef> _categories = const [];
  List<NamedRef> _brands = const [];
  String? _rate;

  bool _dirty = false;
  bool _saving = false;
  ApiException? _error;
  final Map<String, String> _local = {};

  bool get _canSeeCost => widget.session.can('catalog.cost.view');

  Future<_FormData> _load() async {
    final results = await Future.wait([
      widget.repository.units(),
      widget.repository.categories(),
      widget.repository.brands(),
      widget.repository.exchangeRates(limit: 1),
    ]);
    final rates = results[3] as List<ExchangeRateEntry>;
    final data = _FormData(
      results[0] as List<UnitRef>,
      results[1] as List<NamedRef>,
      results[2] as List<NamedRef>,
      rates.isEmpty ? null : rates.first.rate,
    );
    _units = [...data.units];
    _categories = [...data.categories];
    _brands = [...data.brands];
    _rate = data.rate;
    return data;
  }

  @override
  void initState() {
    super.initState();
    if (widget.initialBarcode != null) _dirty = true;
    widget.unsaved.mark(this, dirty: _dirty);
  }

  @override
  void dispose() {
    widget.unsaved.mark(this, dirty: false);
    for (final c in [
      _sku,
      _name,
      _price,
      _cost,
      _warrantyMonths,
      _warrantyTerms,
      _returnDays,
      _barcodeEntry,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void _touch() {
    if (!_dirty) {
      _dirty = true;
      widget.unsaved.mark(this, dirty: true);
    }
    setState(() {});
  }

  void _addBarcode([String? scanned]) {
    final code = (scanned ?? _barcodeEntry.text).trim();
    if (code.isEmpty) return;
    if (!_barcodes.contains(code)) _barcodes.add(code);
    _barcodeEntry.clear();
    _touch();
  }

  /// Informational only: the server converts at the moment of sale.
  int? _previewTmt() {
    if (_currency != 'USD') return null;
    final minor = parseScaled(_price.text, 2);
    final rate = parseServerDecimal(_rate, 6);
    if (minor == null || rate == null) return null;
    return (minor * rate + 500000) ~/ 1000000; // half up, exact integer maths
  }

  ProductDraft? _validate() {
    final l = strings(context);
    final errors = <String, String>{};
    if (_sku.text.trim().isEmpty) errors['sku'] = l.fieldRequired;
    if (_name.text.trim().isEmpty) errors['name'] = l.fieldRequired;
    if (_unitId == null) errors['unit'] = l.fieldRequired;
    final price = parseScaled(_price.text, 2);
    if (price == null) errors['price_amount'] = l.fieldInvalid;
    int? cost;
    if (_canSeeCost && _cost.text.trim().isNotEmpty) {
      cost = parseScaled(_cost.text, 2);
      if (cost == null) errors['default_purchase_cost'] = l.fieldInvalid;
    }
    final months = int.tryParse(_warrantyMonths.text.trim());
    if (months == null || months < 0 || months > 120) {
      errors['warranty_months'] = l.fieldOutOfRange;
    }
    int? returnDays;
    if (_returnDays.text.trim().isNotEmpty) {
      returnDays = int.tryParse(_returnDays.text.trim());
      if (returnDays == null || returnDays < 0 || returnDays > 3650) {
        errors['return_days'] = l.fieldOutOfRange;
      }
    }
    setState(() {
      _local
        ..clear()
        ..addAll(errors);
    });
    if (errors.isNotEmpty) return null;
    return ProductDraft(
      sku: _sku.text.trim(),
      name: _name.text.trim(),
      unitId: _unitId!,
      categoryId: _categoryId,
      brandId: _brandId,
      priceMinor: price!,
      priceCurrency: _currency,
      defaultCostMinor: cost,
      includeCost: _canSeeCost,
      warrantyMonths: months!,
      warrantyTerms: _warrantyTerms.text.trim(),
      returnDays: returnDays,
      barcodes: List.of(_barcodes),
    );
  }

  Future<void> _save() async {
    if (_saving) return; // never two saves at once
    final draft = _validate();
    if (draft == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final saved = widget.existing == null
          ? await widget.repository.createProduct(draft)
          : await widget.repository.updateProduct(widget.existing!.id, draft);
      _dirty = false;
      widget.unsaved.mark(this, dirty: false);
      if (mounted) Navigator.of(context).pop(saved);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String? _fieldText(String field) {
    final l = strings(context);
    return _local[field] ?? fieldError(l, _error, field);
  }

  @override
  Widget build(BuildContext context) {
    final l = strings(context);
    return PopScope(
      canPop: !_dirty || _saving,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final leave = await confirmAction(
          context,
          widget.existing == null ? l.addProduct : l.editProduct,
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
          title: Text(widget.existing == null ? l.addProduct : l.editProduct),
        ),
        body: SafeArea(
          child: FutureBuilder<_FormData>(
            future: _data,
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
              return _form(context);
            },
          ),
        ),
      ),
    );
  }

  Widget _form(BuildContext context) {
    final l = strings(context);
    final preview = _previewTmt();
    final general = _error != null && _error!.fields.isEmpty
        ? apiErrorText(l, _error!)
        : null;
    final unit = _units.where((u) => u.id == _unitId).firstOrNull;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                key: const ValueKey('pf-sku'),
                controller: _sku,
                enabled: !_saving,
                autocorrect: false,
                onChanged: (_) => _touch(),
                decoration: InputDecoration(
                  labelText: l.productSku,
                  errorText: _fieldText('sku'),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                key: const ValueKey('pf-name'),
                controller: _name,
                enabled: !_saving,
                onChanged: (_) => _touch(),
                decoration: InputDecoration(
                  labelText: l.productName,
                  errorText: _fieldText('name'),
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  _wide(
                    NamedRefPicker(
                      key: const ValueKey('pf-category'),
                      label: l.categoryLabel,
                      items: _categories,
                      value: _categoryId,
                      enabled: !_saving,
                      errorText: _fieldText('category'),
                      onChanged: (v) {
                        _categoryId = v;
                        _touch();
                      },
                      onAddNew: () async {
                        final created = await showCreateNamedDialog(
                          context,
                          title: l.addCategory,
                          create: widget.repository.createCategory,
                        );
                        if (created != null) {
                          _categories = [..._categories, created];
                        }
                        return created;
                      },
                    ),
                  ),
                  _wide(
                    NamedRefPicker(
                      key: const ValueKey('pf-brand'),
                      label: l.brandLabel,
                      items: _brands,
                      value: _brandId,
                      enabled: !_saving,
                      errorText: _fieldText('brand'),
                      onChanged: (v) {
                        _brandId = v;
                        _touch();
                      },
                      onAddNew: () async {
                        final created = await showCreateNamedDialog(
                          context,
                          title: l.addBrand,
                          create: widget.repository.createBrand,
                        );
                        if (created != null) _brands = [..._brands, created];
                        return created;
                      },
                    ),
                  ),
                  _wide(
                    NamedRefPicker(
                      key: const ValueKey('pf-unit'),
                      label: l.unitLabel,
                      allowNone: false,
                      items: [
                        for (final u in _units)
                          NamedRef(id: u.id, name: '${u.name} (${u.symbol})'),
                      ],
                      value: _unitId,
                      enabled: !_saving,
                      errorText: _fieldText('unit'),
                      onChanged: (v) {
                        _unitId = v;
                        _touch();
                      },
                      onAddNew: () async {
                        final created = await showCreateUnitDialog(
                          context,
                          widget.repository,
                        );
                        if (created == null) return null;
                        _units = [..._units, created];
                        return NamedRef(
                          id: created.id,
                          name: '${created.name} (${created.symbol})',
                        );
                      },
                    ),
                  ),
                ],
              ),
              if (unit != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    '${l.unitDecimals}: ${unit.decimalPlaces}',
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 12,
                    ),
                  ),
                ),
              const SizedBox(height: 24),
              Text(
                l.priceLabel,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 16,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 220,
                    child: TextField(
                      key: const ValueKey('pf-price'),
                      controller: _price,
                      enabled: !_saving,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,  ]')),
                      ],
                      onChanged: (_) => _touch(),
                      decoration: InputDecoration(
                        labelText: l.priceLabel,
                        errorText: _fieldText('price_amount'),
                        errorMaxLines: 3,
                      ),
                    ),
                  ),
                  SegmentedButton<String>(
                    key: const ValueKey('pf-currency'),
                    segments: const [
                      ButtonSegment(
                        value: 'TMT',
                        label: Text('TMT', key: ValueKey('pf-currency-tmt')),
                      ),
                      ButtonSegment(
                        value: 'USD',
                        label: Text('USD', key: ValueKey('pf-currency-usd')),
                      ),
                    ],
                    selected: {_currency},
                    onSelectionChanged: _saving
                        ? null
                        : (s) {
                            _currency = s.first;
                            _touch();
                          },
                  ),
                ],
              ),
              if (_currency == 'USD') ...[
                const SizedBox(height: 8),
                if (_rate == null)
                  Text(
                    l.rateMissingNote,
                    key: const ValueKey('pf-rate-missing'),
                    style: const TextStyle(color: AppColors.warning),
                  )
                else if (preview != null)
                  Text(
                    l.priceInTmt(formatMoney(preview, 'TMT')),
                    key: const ValueKey('pf-price-preview'),
                    style: const TextStyle(color: AppColors.muted),
                  ),
              ],
              if (_canSeeCost) ...[
                const SizedBox(height: 16),
                SizedBox(
                  width: 320,
                  child: TextField(
                    key: const ValueKey('pf-cost'),
                    controller: _cost,
                    enabled: !_saving,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onChanged: (_) => _touch(),
                    decoration: InputDecoration(
                      labelText: l.defaultCostLabel,
                      errorText: _fieldText('default_purchase_cost'),
                      errorMaxLines: 3,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              Text(
                l.barcodesLabel,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              if (_barcodes.isNotEmpty)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final code in _barcodes)
                      InputChip(
                        key: ValueKey('pf-barcode-chip-$code'),
                        label: Text(code),
                        onDeleted: _saving
                            ? null
                            : () {
                                _barcodes.remove(code);
                                _touch();
                              },
                      ),
                  ],
                ),
              const SizedBox(height: 8),
              BarcodeInput(
                fieldKey: const ValueKey('pf-barcode'),
                controller: _barcodeEntry,
                label: l.barcodeFieldLabel,
                enabled: !_saving,
                errorText: _fieldText('barcodes'),
                onSubmitted: (_) => _addBarcode(),
                // scanning only fills the draft of THIS form; nothing is saved yet
                onScanned: _addBarcode,
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: const ValueKey('pf-barcode-add'),
                  onPressed: _saving ? null : _addBarcode,
                  icon: const Icon(Icons.add),
                  label: Text(l.addBarcode),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: 260,
                child: TextField(
                  key: const ValueKey('pf-warranty-months'),
                  controller: _warrantyMonths,
                  enabled: !_saving,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onChanged: (_) => _touch(),
                  decoration: InputDecoration(
                    labelText: l.warrantyMonthsLabel,
                    errorText: _fieldText('warranty_months'),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                key: const ValueKey('pf-warranty-terms'),
                controller: _warrantyTerms,
                enabled: !_saving,
                minLines: 2,
                maxLines: 5,
                onChanged: (_) => _touch(),
                decoration: InputDecoration(
                  labelText: l.warrantyTermsLabel,
                  errorText: _fieldText('warranty_terms'),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: 260,
                child: TextField(
                  key: const ValueKey('pf-return-days'),
                  controller: _returnDays,
                  enabled: !_saving,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onChanged: (_) => _touch(),
                  decoration: InputDecoration(
                    labelText: l.productReturnDays,
                    helperText: l.productReturnDaysHint,
                    helperMaxLines: 3,
                    errorText: _fieldText('return_days'),
                  ),
                ),
              ),
              if (general != null) ...[
                const SizedBox(height: 16),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    general,
                    key: const ValueKey('pf-error'),
                    style: const TextStyle(color: AppColors.danger),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              GradientButton(
                key: const ValueKey('pf-save'),
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

  Widget _wide(Widget child) => ConstrainedBox(
    constraints: const BoxConstraints(minWidth: 200, maxWidth: 320),
    child: child,
  );
}
