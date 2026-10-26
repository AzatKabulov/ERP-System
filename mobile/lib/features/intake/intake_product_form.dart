import 'package:flutter/material.dart';

import '../../core/api/api_error_text.dart';
import '../../core/api/api_exception.dart';
import '../../core/files/file_services.dart';
import '../../core/money/decimal_math.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_icons.dart';
import '../../widgets/common.dart';
import '../catalog/catalog_models.dart';
import '../catalog/catalog_repository.dart';
import '../inventory/quantity_input.dart';
import 'intake_controller.dart';
import 'intake_models.dart';

/// One reviewable form after a scan. Suggestions never save a product or supply prices.
class IntakeProductForm extends StatefulWidget {
  const IntakeProductForm({
    super.key,
    required this.entry,
    required this.controller,
    required this.catalog,
    required this.canCost,
    required this.canManage,
  });
  final IntakeEntry entry;
  final IntakeController controller;
  final CatalogRepository catalog;
  final bool canCost;
  final bool canManage;

  @override
  State<IntakeProductForm> createState() => _IntakeProductFormState();
}

class _IntakeProductFormState extends State<IntakeProductForm> {
  late final _name = TextEditingController(
    text: widget.entry.form['name'] ?? '',
  );
  late final _sku = TextEditingController(
    text:
        widget.entry.form['sku'] ??
        widget.entry.product?.sku ??
        (!widget.entry.isManual && codeFitsAsArticle(widget.entry.code)
            ? widget.entry.code
            : ''),
  );
  late final _brand = TextEditingController(
    text: widget.entry.form['brand'] ?? '',
  );
  late final _category = TextEditingController(
    text: widget.entry.form['category'] ?? '',
  );
  late final _quantity = TextEditingController(
    text:
        widget.entry.form['quantity'] ??
        formatQuantity(
          widget.entry.quantityMilli,
          widget.entry.product?.unit.decimalPlaces ?? 0,
        ).replaceAll(' ', ''),
  );
  late final _price = TextEditingController(
    text: widget.entry.form['price'] ?? '',
  );
  late final _cost = TextEditingController(
    text: widget.canCost
        ? widget.entry.form['cost'] ??
              (widget.entry.costMinor == null
                  ? ''
                  : toServerDecimal(widget.entry.costMinor!, 2))
        : '',
  );
  late final _warranty = TextEditingController(
    text: widget.entry.form['warranty_months'] ?? '',
  );
  late final _expiryText = TextEditingController(
    text:
        widget.entry.form['expiry_date'] ??
        widget.entry.expiryDate?.split('-').reversed.join('.') ??
        '',
  );

  String? get _expiryDate {
    final raw = _expiryText.text.trim();
    final dotted = RegExp(r'^(\d{2})\.(\d{2})\.(\d{4})$').firstMatch(raw);
    final iso = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(raw);
    if (dotted == null && iso == null) return null;
    final year = int.parse(dotted?.group(3) ?? iso!.group(1)!);
    final month = int.parse(dotted?.group(2) ?? iso!.group(2)!);
    final day = int.parse(dotted?.group(1) ?? iso!.group(3)!);
    if (year < 1 || year > 9999) return null;
    final date = DateTime(year, month, day);
    if (date.year != year || date.month != month || date.day != day) {
      return null;
    }
    return '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
  }

  List<UnitRef> _units = const [];
  UnitRef? _unit;
  Product? _existing;
  String? _loadingId;
  bool _loading = true;
  bool _productLoading = false;
  bool _busy = false;
  bool _submitted = false;
  Object? _loadError;
  Object? _saveError;
  PickedFile? _photo;

  IntakeEntry get entry => widget.controller.entries.contains(widget.entry)
      ? widget.entry
      : widget.controller.entries
                .where((e) => e.product?.id == widget.entry.product?.id)
                .firstOrNull ??
            widget.entry;
  bool get _known => entry.product != null;
  bool get _editable => widget.canManage && (!_known || !_productLoading);

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_sync);
    _loadUnits();
    _sync();
  }

  Future<void> _loadUnits() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final units = await widget.catalog.units();
      if (!mounted) return;
      setState(() {
        _units = units.where((u) => u.isActive).toList();
        _unit =
            entry.product?.unit ??
            _units.where((u) => u.id == entry.form['unit']).firstOrNull ??
            defaultPieceUnit(_units);
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadError = e;
        });
      }
    }
  }

  void _fill(String field, TextEditingController controller, String value) {
    if (!entry.form.containsKey(field)) controller.text = value;
  }

  void _sync() {
    if (!mounted || _busy) return;
    if (_known && _loadingId != entry.product!.id) {
      _loadingId = entry.product!.id;
      _loadProduct(_loadingId!);
    } else if (!_known) {
      final info = entry.suggestion;
      if (info != null) {
        _fill('name', _name, info.displayName);
        _fill('brand', _brand, info.brand);
        _fill('category', _category, info.category);
      }
    }
    setState(() {});
  }

  Future<void> _loadProduct(String id) async {
    setState(() {
      _productLoading = true;
      _loadError = null;
    });
    try {
      final product = await widget.catalog.product(id);
      if (!mounted) return;
      setState(() {
        _existing = product;
        _unit = product.unit;
        _fill('name', _name, product.name);
        _fill('sku', _sku, product.sku);
        _fill('brand', _brand, product.brand?.name ?? '');
        _fill('category', _category, product.category?.name ?? '');
        _fill(
          'warranty_months',
          _warranty,
          product.warrantyMonths == 0 ? '' : '${product.warrantyMonths}',
        );
        // Never prefill money from a lookup, including existing catalog prices/costs.
        _productLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _productLoading = false;
          _loadError = e;
        });
      }
    }
  }

  void _change(String field, String value) {
    widget.controller.saveFormField(entry, field, value);
    setState(() {});
  }

  int? get _qty => _unit == null ? null : parseQuantity(_quantity.text, _unit!);
  int? get _priceMinor =>
      _price.text.trim().isEmpty ? null : parseScaled(_price.text, 2);
  int? get _costMinor =>
      _cost.text.trim().isEmpty ? null : parseScaled(_cost.text, 2);
  bool get _moneyValid =>
      (_price.text.trim().isEmpty || _priceMinor != null) &&
      (!widget.canCost || _cost.text.trim().isEmpty || _costMinor != null);
  int? get _warrantyMonths =>
      _warranty.text.trim().isEmpty ? 0 : int.tryParse(_warranty.text.trim());
  bool get _warrantyValid =>
      _warrantyMonths != null &&
      _warrantyMonths! >= 0 &&
      _warrantyMonths! <= 120;
  bool get _waiting =>
      _loading || _productLoading || entry.state == IntakeEntryState.lookingUp;

  Future<void> _save() async {
    if (_busy || _waiting) return;
    setState(() {
      _submitted = true;
      _saveError = null;
    });
    if (_loadError != null ||
        entry.state == IntakeEntryState.lookupFailed ||
        _qty == null ||
        !_moneyValid ||
        (_expiryText.text.trim().isNotEmpty && _expiryDate == null) ||
        (widget.canManage && !_warrantyValid) ||
        _name.text.trim().isEmpty ||
        (!entry.isManual && _sku.text.trim().isEmpty) ||
        (!_known && !widget.canManage)) {
      return;
    }
    final qty = _qty!;
    setState(() => _busy = true);
    try {
      Product product;
      if (widget.canManage) {
        final brand = await widget.catalog.resolveReference(
          _brand.text,
          brand: true,
        );
        final category = await widget.catalog.resolveReference(
          _category.text,
          brand: false,
        );
        final current = _existing;
        if (current == null) {
          await widget.controller.addProduct(
            entry,
            name: _name.text,
            sku: _sku.text.trim().isEmpty && entry.isManual
                ? entry.code.replaceFirst('manual-', 'M-')
                : _sku.text,
            unit: _unit!,
            priceMinor: _priceMinor ?? 0,
            brandId: brand?.id,
            categoryId: category?.id,
            warrantyMonths: _warrantyMonths!,
          );
          product = await widget.catalog.product(entry.product!.id);
        } else {
          final changes = <String, dynamic>{
            if (_name.text.trim() != current.name) 'name': _name.text.trim(),
            if (_sku.text.trim().isNotEmpty && _sku.text.trim() != current.sku)
              'sku': _sku.text.trim(),
            if (_warrantyMonths != current.warrantyMonths)
              'warranty_months': _warrantyMonths,
            if (brand?.id != current.brand?.id) 'brand': brand?.id,
            if (category?.id != current.category?.id) 'category': category?.id,
            if (_priceMinor != null)
              'price_amount': toServerDecimal(_priceMinor!, 2),
          };
          product = changes.isEmpty
              ? current
              : await widget.catalog.updateReceivingDetails(
                  current.id,
                  changes,
                );
        }
      } else {
        product = _existing!;
      }
      if (!mounted) return;
      widget.controller.finishForm(
        entry,
        product,
        qty,
        widget.canCost ? _costMinor : entry.costMinor,
        expiryDate: _expiryDate,
      );
      if (_photo != null) {
        try {
          await widget.catalog.uploadPhoto(product.id, _photo!);
        } catch (_) {
          if (mounted) {
            showFeedback(context, strings(context).productPhotoPickFailed);
          }
        }
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _saveError = e;
        });
      }
    }
  }

  Future<void> _pickPhoto() async {
    try {
      final picking = FilesScope.pickingOf(context);
      final photo = await picking.pickPhoto(camera: picking.hasCamera);
      if (mounted && photo != null) setState(() => _photo = photo);
    } catch (_) {
      if (mounted) {
        showFeedback(context, strings(context).productPhotoPickFailed);
      }
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_sync);
    for (final field in [
      _name,
      _sku,
      _brand,
      _category,
      _quantity,
      _price,
      _cost,
      _warranty,
      _expiryText,
    ]) {
      field.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = strings(context);
    String? error(String field) {
      final e = _saveError;
      if (e is! ApiException) return null;
      final f = e.fields[field]?.firstOrNull;
      return f == null ? null : fieldErrorText(l, f);
    }

    Widget field(
      String id,
      String label,
      TextEditingController controller,
      String draftField, {
      bool enabled = true,
      bool numeric = false,
      String? errorText,
      String? helper,
    }) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: LabeledField(
        label: label,
        child: TextField(
          key: ValueKey(id),
          controller: controller,
          enabled: enabled && !_busy,
          keyboardType: numeric
              ? const TextInputType.numberWithOptions(decimal: true)
              : TextInputType.text,
          autocorrect: false,
          onChanged: (value) => _change(draftField, value),
          decoration: InputDecoration(
            errorText: errorText,
            errorMaxLines: 3,
            helperText: helper,
            helperMaxLines: 3,
          ),
        ),
      ),
    );
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        scrollable: true,
        title: Text(l.intakeFormTitle),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                entry.isManual
                    ? l.intakeNoBarcode
                    : l.intakeCodeLine(entry.code),
                style: const TextStyle(color: AppColors.muted),
              ),
              const SizedBox(height: 12),
              if (_waiting) const LinearProgressIndicator(),
              if (entry.suggesting)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(l.intakeOnlineLoading),
                ),
              if (!_known && entry.suggestion != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(l.intakeOnlineSource(entry.suggestion!.source)),
                ),
              if (entry.state == IntakeEntryState.lookupFailed) ...[
                Text(l.intakeLookupFailed),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => widget.controller.retryLookup(entry),
                  child: Text(l.retry),
                ),
              ],
              if (_loadError != null) ...[
                Text(l.loadFailed),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () {
                          _loadUnits();
                          if (_known) _loadProduct(entry.product!.id);
                        },
                  child: Text(l.retry),
                ),
              ],
              if (!widget.canManage && !_known)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(l.intakeCatalogPermission),
                ),
              field(
                'intake-new-name',
                l.productName,
                _name,
                'name',
                enabled: _editable,
                errorText: _submitted && _name.text.trim().isEmpty
                    ? l.fieldRequired
                    : error('name'),
              ),
              if (widget.canManage)
                OutlinedButton.icon(
                  key: const ValueKey('intake-new-photo'),
                  onPressed: _busy ? null : _pickPhoto,
                  icon: const AppIcon(AppIcons.image),
                  label: Text(
                    _photo == null
                        ? l.productPhotoChoose
                        : l.productPhotoChange,
                  ),
                ),
              if (_photo != null)
                Image.memory(
                  _photo!.bytes,
                  key: const ValueKey('intake-new-photo-preview'),
                  width: 56,
                  height: 56,
                ),

              field(
                'intake-edit-qty',
                l.quantity,
                _quantity,
                'quantity',
                numeric: true,
                errorText: _submitted && _qty == null
                    ? l.fieldQuantityPrecision
                    : null,
              ),
              if (widget.canCost)
                field(
                  'intake-edit-cost',
                  l.intakeCostLabel,
                  _cost,
                  'cost',
                  numeric: true,
                  errorText:
                      _submitted &&
                          _cost.text.trim().isNotEmpty &&
                          _costMinor == null
                      ? l.validAmount
                      : null,
                ),
              if (widget.canManage)
                field(
                  'intake-new-price',
                  l.intakeSellingPrice(_existing?.priceCurrency ?? 'TMT'),
                  _price,
                  'price',
                  enabled: !_waiting,
                  numeric: true,
                  helper: _known ? l.intakeKeepPrice : null,
                  errorText:
                      _submitted &&
                          _price.text.trim().isNotEmpty &&
                          _priceMinor == null
                      ? l.validAmount
                      : error('price_amount'),
                ),
              if (widget.canManage)
                field(
                  'intake-warranty-months',
                  l.intakeWarrantyMonths,
                  _warranty,
                  'warranty_months',
                  enabled: _editable,
                  numeric: true,
                  errorText: _submitted && !_warrantyValid
                      ? l.fieldOutOfRange
                      : error('warranty_months'),
                ),
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: LabeledField(
                  label: l.expiryDateOptional,
                  child: TextField(
                    key: const ValueKey('intake-expiry-date'),
                    controller: _expiryText,
                    enabled: !_busy,
                    keyboardType: TextInputType.datetime,
                    onChanged: (value) => _change('expiry_date', value),
                    decoration: InputDecoration(
                      hintText: l.expiryDateFormat,
                      errorText:
                          _submitted &&
                              _expiryText.text.trim().isNotEmpty &&
                              _expiryDate == null
                          ? l.expiryDateInvalid
                          : null,
                      suffixIcon: _expiryText.text.isEmpty
                          ? null
                          : IconButton(
                              key: const ValueKey('intake-expiry-clear'),
                              tooltip: l.clearExpiryDate,
                              onPressed: _busy
                                  ? null
                                  : () {
                                      _expiryText.clear();
                                      _change('expiry_date', '');
                                    },
                              icon: const AppIcon(AppIcons.close),
                            ),
                    ),
                  ),
                ),
              ),
              field(
                'intake-new-brand',
                l.brandLabel,
                _brand,
                'brand',
                enabled: _editable,
                errorText: error('brand'),
              ),
              field(
                'intake-new-category',
                l.categoryLabel,
                _category,
                'category',
                enabled: _editable,
                errorText: error('category'),
              ),
              field(
                'intake-new-sku',
                entry.isManual ? l.intakeArticleOptional : l.productSku,
                _sku,
                'sku',
                enabled: _editable,
                errorText:
                    _submitted && !entry.isManual && _sku.text.trim().isEmpty
                    ? l.fieldRequired
                    : error('sku') ?? error('barcodes'),
              ),
              if (_units.isNotEmpty || _unit != null)
                LabeledField(
                  label: l.unitLabel,
                  child: DropdownButtonFormField<String>(
                    key: ValueKey('intake-new-unit-${_unit?.id}'),
                    initialValue: _unit?.id,
                    isExpanded: true,
                    items: [
                      for (final unit in (_known ? [_unit!] : _units))
                        DropdownMenuItem(
                          value: unit.id,
                          child: Text('${unit.name} (${unit.symbol})'),
                        ),
                    ],
                    onChanged: _known || _busy
                        ? null
                        : (id) {
                            setState(
                              () =>
                                  _unit = _units.firstWhere((u) => u.id == id),
                            );
                            _change('unit', id!);
                          },
                  ),
                ),
              const SizedBox(height: 12),
              if (_saveError != null)
                Semantics(
                  liveRegion: true,
                  child: Text(
                    _saveError is ApiException
                        ? apiErrorText(l, _saveError! as ApiException)
                        : l.loadFailed,
                    key: const ValueKey('intake-new-error'),
                    style: const TextStyle(color: AppColors.danger),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(false),
            child: Text(l.cancel),
          ),
          FilledButton(
            key: ValueKey(_known ? 'intake-edit-save' : 'intake-new-save'),
            onPressed:
                _busy ||
                    _waiting ||
                    _loadError != null ||
                    entry.state == IntakeEntryState.lookupFailed ||
                    (!widget.canManage && !_known)
                ? null
                : _save,
            child: Text(_busy ? l.intakeLookingUp : l.save),
          ),
        ],
      ),
    );
  }
}
