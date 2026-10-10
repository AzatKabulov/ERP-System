import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api/api_error_text.dart';
import '../../core/api/api_exception.dart';
import '../../core/connectivity/connection_monitor.dart';
import '../../l10n/app_localizations.dart';
import '../../core/money/decimal_math.dart';
import '../../core/operations/operation_runner.dart';
import '../../core/session/session_controller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../catalog/catalog_models.dart';
import '../catalog/catalog_repository.dart';
import '../inventory/quantity_input.dart';
import '../inventory/stock_entry_screen.dart' show EntryResult;
import '../scanning/barcode_scanner.dart';
import 'intake_controller.dart';
import 'intake_draft_store.dart';
import 'intake_models.dart';
import 'intake_repository.dart';

/// Receiving goods by scanning: open a box, scan every item (camera, a hand scanner that types
/// the code and presses Enter, or by typing) and each scan adds one to that product's line.
/// A code the catalog does not know is added with just a name. Then one tap puts everything on
/// the shelf. The list is kept on the device while it is built, and the final posting goes
/// through the [OperationRunner], so a lost answer, a crash or a restart can never receive
/// the same box twice.
class IntakeScreen extends StatefulWidget {
  const IntakeScreen({
    super.key,
    required this.session,
    required this.catalog,
    required this.runner,
    required this.monitor,
    required this.store,
  });

  final SessionController session;
  final CatalogRepository catalog;
  final OperationRunner runner;
  final ConnectionMonitor monitor;
  final IntakeDraftStore store;

  @override
  State<IntakeScreen> createState() => _IntakeScreenState();
}

class _IntakeScreenState extends State<IntakeScreen> {
  late final IntakeController _ctl;
  final _input = TextEditingController();
  final _focus = FocusNode();
  final _note = TextEditingController();
  bool _resumed = false;
  bool _busy = false;
  bool _wasOnline = true;
  String? _blocked;
  ApiException? _error;

  SessionController get session => widget.session;
  bool get _canCost => session.can('stock.cost.view');

  @override
  void initState() {
    super.initState();
    final mine = session.membership?.locations ?? const [];
    final preferred = session.location?.id ?? mine.firstOrNull?.id;
    _ctl = IntakeController(
      catalog: widget.catalog,
      store: widget.store,
      locationId: preferred,
    );
    _resumed = _ctl.restore();
    if (!mine.any((x) => x.id == _ctl.locationId)) {
      _ctl.locationId = mine.firstOrNull?.id;
    }
    _wasOnline = widget.monitor.online;
    widget.monitor.addListener(_connectionChanged);
  }

  @override
  void dispose() {
    widget.monitor.removeListener(_connectionChanged);
    _ctl.dispose();
    _input.dispose();
    _focus.dispose();
    _note.dispose();
    super.dispose();
  }

  /// When the connection comes back, lines that could not be looked up try again.
  void _connectionChanged() {
    final online = widget.monitor.online;
    if (online && !_wasOnline) {
      for (final e in _ctl.entries) {
        if (e.state == IntakeEntryState.lookupFailed) _ctl.retryLookup(e);
      }
    }
    _wasOnline = online;
  }

  void _onCode(String code) {
    if (_ctl.scan(code) == null) return;
    setState(() {
      _blocked = null;
      _error = null;
    });
  }

  void _typed(String text) {
    _onCode(text);
    _input.clear();
  }

  Future<void> _camera() async {
    final scanner = ScannerScope.of(context);
    await scanner.scanContinuously(
      context,
      onCode: _onCode,
      changes: _ctl,
      status: _cameraStatus,
    );
    if (mounted) setState(() {});
  }

  Widget _cameraStatus(BuildContext context) {
    final l = strings(context);
    final last = _ctl.lastScanned;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          last == null
              ? l.intakeCameraHint
              : '${last.product?.name ?? last.code} · ${quantityWithUnit(last.quantityMilli, last.product?.unit ?? _pieces)}',
          key: const ValueKey('intake-last'),
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        Text(l.intakeSummary(_ctl.lineCount, _unitsText())),
      ],
    );
  }

  static const _pieces = UnitRef(
    id: '',
    name: '',
    symbol: '',
    decimalPlaces: 0,
  );

  String _unitsText() {
    final decimals = _ctl.entries.fold<int>(
      0,
      (m, e) => (e.product?.unit.decimalPlaces ?? 0) > m
          ? e.product!.unit.decimalPlaces
          : m,
    );
    return formatQuantity(_ctl.unitsMilli, decimals);
  }

  String get _locationName =>
      (session.membership?.locations ?? const [])
          .where((x) => x.id == _ctl.locationId)
          .firstOrNull
          ?.name ??
      '';

  Future<void> _startOver() async {
    final l = strings(context);
    final ok = await confirmAction(
      context,
      l.intakeStartOver,
      l.intakeStartOverBody,
    );
    if (!ok) return;
    await _ctl.clear();
    if (mounted) setState(() => _resumed = false);
  }

  Future<void> _edit(IntakeEntry entry) async {
    final result = await showDialog<_Edit>(
      context: context,
      builder: (_) => _EditDialog(entry: entry, canCost: _canCost),
    );
    if (result == null) return;
    _ctl.setQuantity(entry, result.quantityMilli);
    if (_canCost) _ctl.setCost(entry, result.costMinor);
  }

  Future<void> _addProduct(IntakeEntry entry) async {
    final added = await showDialog<bool>(
      context: context,
      builder: (_) => _NewProductDialog(
        entry: entry,
        controller: _ctl,
        catalog: widget.catalog,
      ),
    );
    if (added == true && mounted) {
      showFeedback(context, strings(context).intakeProductAdded);
    }
  }

  Future<void> _submit() async {
    if (_busy || _ctl.isEmpty) return;
    final l = strings(context);
    if (_ctl.unresolvedCount > 0) {
      setState(() => _blocked = l.intakeUnresolvedBlock);
      return;
    }
    final ok = await confirmAction(
      context,
      l.intakeConfirmTitle,
      l.intakeConfirmBody(_locationName, _ctl.lineCount, _unitsText()),
    );
    if (!ok || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
      _blocked = null;
    });
    final repo = IntakeRepository(session.membership!.businessId);
    final outcome = await widget.runner.submit(
      action: 'stock_intake',
      businessId: session.membership!.businessId,
      path: repo.path,
      body: repo.body(
        locationId: _ctl.locationId!,
        note: _note.text.trim(),
        entries: _ctl.entries,
        withCost: _canCost,
      ),
      subject: _locationName,
    );
    if (!mounted) return;
    switch (outcome) {
      case OperationCompleted():
        await _finish(EntryResult.posted);
      case OperationUnknown():
        // the saved operation now carries the goods; the pending banner follows it up
        await _finish(EntryResult.unknown);
      case OperationRejected(:final error):
        setState(() {
          _busy = false;
          _error = error;
        });
    }
  }

  Future<void> _finish(EntryResult result) async {
    await _ctl.clear();
    if (mounted) Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final l = strings(context);
    final mine = session.membership?.locations ?? const [];
    final scanner = ScannerScope.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.intakeTitle)),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: ListenableBuilder(
              listenable: _ctl,
              builder: (context, _) => ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  if (mine.length > 1) ...[
                    DropdownButtonFormField<String>(
                      key: const ValueKey('intake-location'),
                      isExpanded: true,
                      initialValue: mine.any((x) => x.id == _ctl.locationId)
                          ? _ctl.locationId
                          : null,
                      decoration: InputDecoration(
                        labelText: l.intakeLocationLabel,
                      ),
                      items: [
                        for (final x in mine)
                          DropdownMenuItem(value: x.id, child: Text(x.name)),
                      ],
                      onChanged: _busy ? null : (v) => _ctl.setLocation(v),
                    ),
                    const SizedBox(height: 16),
                  ],
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextField(
                          key: const ValueKey('intake-input'),
                          controller: _input,
                          focusNode: _focus,
                          enabled: !_busy,
                          autocorrect: false,
                          enableSuggestions: false,
                          textInputAction: TextInputAction.done,
                          // Enter must not close the field on a device: a hand scanner presses
                          // it after every code and the next code follows at once. (The browser
                          // build blurs the field itself on Enter, and keeping the framework's
                          // focus then leaves a field that no longer receives text, so it keeps
                          // the ordinary behaviour.)
                          onEditingComplete: kIsWeb ? null : () {},
                          onSubmitted: _typed,
                          decoration: InputDecoration(
                            labelText: l.intakeScanLabel,
                            prefixIcon: const Icon(Icons.qr_code_2),
                            helperText: l.intakeScanHelp,
                            helperMaxLines: 3,
                          ),
                        ),
                      ),
                      if (scanner.isAvailable) ...[
                        const SizedBox(width: 8),
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: IconButton.filled(
                            key: const ValueKey('intake-camera'),
                            tooltip: l.intakeCameraTooltip,
                            iconSize: 30,
                            constraints: const BoxConstraints(
                              minWidth: 56,
                              minHeight: 56,
                            ),
                            onPressed: _busy ? null : _camera,
                            icon: const Icon(Icons.qr_code_scanner),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (_resumed && !_ctl.isEmpty) ...[
                    const SizedBox(height: 12),
                    SurfaceCard(
                      padding: 12,
                      child: Row(
                        children: [
                          const Icon(Icons.history, color: AppColors.warning),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              l.intakeDraftResumed(_ctl.lineCount),
                              key: const ValueKey('intake-resumed'),
                            ),
                          ),
                          TextButton(
                            key: const ValueKey('intake-start-over'),
                            onPressed: _busy ? null : _startOver,
                            child: Text(l.intakeStartOver),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  if (_ctl.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 28),
                      child: Text(
                        l.intakeEmpty,
                        key: const ValueKey('intake-empty'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: AppColors.muted,
                          height: 1.5,
                        ),
                      ),
                    ),
                  for (final entry in _ctl.entries.reversed)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _EntryCard(
                        key: ValueKey('intake-line-${entry.code}'),
                        entry: entry,
                        canCost: _canCost,
                        busy: _busy,
                        onMinus: () => _ctl.adjust(entry, -1000),
                        onPlus: () => _ctl.adjust(entry, 1000),
                        onEdit: () => _edit(entry),
                        onRemove: () => _ctl.remove(entry),
                        onAdd: () => _addProduct(entry),
                        onRetry: () => _ctl.retryLookup(entry),
                      ),
                    ),
                  if (!_ctl.isEmpty) ...[
                    const SizedBox(height: 10),
                    TextField(
                      key: const ValueKey('intake-note'),
                      controller: _note,
                      enabled: !_busy,
                      decoration: InputDecoration(labelText: l.noteLabel),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      l.intakeSummary(_ctl.lineCount, _unitsText()),
                      key: const ValueKey('intake-summary'),
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    if (_canCost &&
                        _ctl.entries.any((e) => e.costMinor == null))
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          l.intakeCostMissingNote,
                          key: const ValueKey('intake-cost-note'),
                          style: const TextStyle(
                            color: AppColors.muted,
                            fontSize: 12,
                            height: 1.4,
                          ),
                        ),
                      ),
                  ],
                  if (_blocked != null || _error != null) ...[
                    const SizedBox(height: 12),
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        _blocked ?? apiErrorText(l, _error!),
                        key: const ValueKey('intake-error'),
                        style: const TextStyle(color: AppColors.danger),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
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
                          key: const ValueKey('intake-submit'),
                          label: l.intakeSubmit,
                          icon: Icons.inventory_2_outlined,
                          onPressed:
                              _busy || _ctl.isEmpty || !widget.monitor.online
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
    );
  }
}

/// One counted line: what it is, how many, and what to do when the catalog does not know it.
class _EntryCard extends StatelessWidget {
  const _EntryCard({
    super.key,
    required this.entry,
    required this.canCost,
    required this.busy,
    required this.onMinus,
    required this.onPlus,
    required this.onEdit,
    required this.onRemove,
    required this.onAdd,
    required this.onRetry,
  });

  final IntakeEntry entry;
  final bool canCost;
  final bool busy;
  final VoidCallback onMinus;
  final VoidCallback onPlus;
  final VoidCallback onEdit;
  final VoidCallback onRemove;
  final VoidCallback onAdd;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l = strings(context);
    final product = entry.product;
    final unit = product?.unit;
    final unknown = entry.state == IntakeEntryState.notFound;
    return SurfaceCard(
      padding: 14,
      child: Semantics(
        container: true,
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
                        product?.name ?? entry.code,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        product == null
                            ? switch (entry.state) {
                                IntakeEntryState.lookingUp => l.intakeLookingUp,
                                IntakeEntryState.notFound => l.intakeUnknown,
                                _ => l.intakeLookupFailed,
                              }
                            : '${product.sku}${product.sku == entry.code ? '' : ' · ${entry.code}'}',
                        style: TextStyle(
                          color: unknown ? AppColors.warning : AppColors.muted,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  key: ValueKey('intake-remove-${entry.code}'),
                  tooltip: l.removeLine,
                  onPressed: busy ? null : onRemove,
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                IconButton.outlined(
                  key: ValueKey('intake-minus-${entry.code}'),
                  tooltip: l.intakeLess,
                  onPressed: busy ? null : onMinus,
                  icon: const Icon(Icons.remove),
                ),
                InkWell(
                  key: ValueKey('intake-qty-${entry.code}'),
                  onTap: busy ? null : onEdit,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Text(
                      unit == null
                          ? formatQuantity(entry.quantityMilli, 0)
                          : quantityWithUnit(entry.quantityMilli, unit),
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                IconButton.filledTonal(
                  key: ValueKey('intake-plus-${entry.code}'),
                  tooltip: l.intakeMore,
                  onPressed: busy ? null : onPlus,
                  icon: const Icon(Icons.add),
                ),
                if (canCost && entry.costMinor != null)
                  Text(
                    l.intakeCostShown(formatMoney(entry.costMinor!, 'TMT')),
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 13,
                    ),
                  ),
                if (entry.state == IntakeEntryState.lookingUp)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                if (unknown)
                  FilledButton.tonalIcon(
                    key: ValueKey('intake-add-${entry.code}'),
                    onPressed: busy ? null : onAdd,
                    icon: const Icon(Icons.add_box_outlined),
                    label: Text(l.intakeAddProduct),
                  ),
                if (entry.state == IntakeEntryState.lookupFailed)
                  OutlinedButton.icon(
                    key: ValueKey('intake-retry-${entry.code}'),
                    onPressed: busy ? null : onRetry,
                    icon: const Icon(Icons.refresh),
                    label: Text(l.retry),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Edit {
  const _Edit(this.quantityMilli, this.costMinor);
  final int quantityMilli;
  final int? costMinor;
}

/// Types in an exact quantity (and, for roles that may see costs, an optional cost per unit).
class _EditDialog extends StatefulWidget {
  const _EditDialog({required this.entry, required this.canCost});
  final IntakeEntry entry;
  final bool canCost;

  @override
  State<_EditDialog> createState() => _EditDialogState();
}

class _EditDialogState extends State<_EditDialog> {
  late final _quantity = TextEditingController(
    text: formatQuantity(
      widget.entry.quantityMilli,
      widget.entry.product?.unit.decimalPlaces ?? 0,
    ).replaceAll(' ', ''),
  );
  late final _cost = TextEditingController(
    text: widget.entry.costMinor == null
        ? ''
        : formatQuantity(widget.entry.costMinor! * 10, 2).replaceAll(' ', ''),
  );
  bool _submitted = false;

  @override
  void dispose() {
    _quantity.dispose();
    _cost.dispose();
    super.dispose();
  }

  UnitRef get _unit =>
      widget.entry.product?.unit ??
      const UnitRef(id: '', name: '', symbol: '', decimalPlaces: 0);

  int? get _qty => parseQuantity(_quantity.text, _unit);
  int? get _costMinor =>
      _cost.text.trim().isEmpty ? null : parseScaled(_cost.text, 2);
  bool get _costValid => _cost.text.trim().isEmpty || _costMinor != null;

  void _save() {
    setState(() => _submitted = true);
    if (_qty == null || !_costValid) return;
    Navigator.of(context).pop(_Edit(_qty!, _costMinor));
  }

  @override
  Widget build(BuildContext context) {
    final l = strings(context);
    return AlertDialog(
      title: Text(widget.entry.product?.name ?? widget.entry.code),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const ValueKey('intake-edit-qty'),
              controller: _quantity,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9., ]')),
              ],
              onSubmitted: (_) => _save(),
              decoration: InputDecoration(
                labelText: l.quantity,
                suffixText: _unit.symbol,
                errorText: _submitted && _qty == null
                    ? l.fieldQuantityPrecision
                    : null,
                errorMaxLines: 3,
              ),
            ),
            if (widget.canCost && widget.entry.product != null) ...[
              const SizedBox(height: 16),
              TextField(
                key: const ValueKey('intake-edit-cost'),
                controller: _cost,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9., ]')),
                ],
                decoration: InputDecoration(
                  labelText: l.intakeCostLabel,
                  helperText: l.intakeCostHelp,
                  helperMaxLines: 3,
                  errorText: _submitted && !_costValid ? l.validAmount : null,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.cancel),
        ),
        FilledButton(
          key: const ValueKey('intake-edit-save'),
          onPressed: _save,
          child: Text(l.save),
        ),
      ],
    );
  }
}

/// A code the catalog does not know: the minimum to add it (a name, and the article number when
/// the code cannot serve as one), so the box does not have to be interrupted. Everything else
/// (price, brand, warranty) can be filled in later in the catalog.
class _NewProductDialog extends StatefulWidget {
  const _NewProductDialog({
    required this.entry,
    required this.controller,
    required this.catalog,
  });

  final IntakeEntry entry;
  final IntakeController controller;
  final CatalogRepository catalog;

  @override
  State<_NewProductDialog> createState() => _NewProductDialogState();
}

class _NewProductDialogState extends State<_NewProductDialog> {
  final _name = TextEditingController();
  late final _sku = TextEditingController(
    text: codeFitsAsArticle(widget.entry.code) ? widget.entry.code : '',
  );
  List<UnitRef> _units = const [];
  UnitRef? _unit;
  bool _submitted = false;
  bool _busy = false;
  ApiException? _error;

  @override
  void initState() {
    super.initState();
    widget.catalog
        .units()
        .then((units) {
          if (!mounted) return;
          setState(() {
            _units = [
              for (final u in units)
                if (u.isActive) u,
            ];
            _unit = defaultPieceUnit(units);
          });
        })
        .catchError((_) {
          // without units the form says so and cannot be saved
        });
  }

  @override
  void dispose() {
    _name.dispose();
    _sku.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    setState(() {
      _submitted = true;
      _error = null;
    });
    if (_name.text.trim().isEmpty ||
        _sku.text.trim().isEmpty ||
        _unit == null) {
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.controller.addProduct(
        widget.entry,
        name: _name.text,
        sku: _sku.text,
        unit: _unit!,
      );
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e;
        });
      }
    }
  }

  /// What the server said about one field, in words (null when it said nothing).
  String? _fieldError(AppLocalizations l, String field) {
    final e = _error?.fields[field]?.firstOrNull;
    return e == null ? null : fieldErrorText(l, e);
  }

  @override
  Widget build(BuildContext context) {
    final l = strings(context);
    return AlertDialog(
      title: Text(l.intakeNewProductTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l.intakeCodeLine(widget.entry.code),
              style: const TextStyle(color: AppColors.muted),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('intake-new-name'),
              controller: _name,
              autofocus: true,
              enabled: !_busy,
              textCapitalization: TextCapitalization.sentences,
              onSubmitted: (_) => _save(),
              decoration: InputDecoration(
                labelText: l.productName,
                errorText: _submitted && _name.text.trim().isEmpty
                    ? l.fieldRequired
                    : _fieldError(l, 'name'),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('intake-new-sku'),
              controller: _sku,
              enabled: !_busy,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: l.productSku,
                helperText: codeFitsAsArticle(widget.entry.code)
                    ? null
                    : l.intakeCodeTooLong,
                helperMaxLines: 3,
                errorText: _submitted && _sku.text.trim().isEmpty
                    ? l.fieldRequired
                    : _fieldError(l, 'sku') ?? _fieldError(l, 'barcodes'),
                errorMaxLines: 3,
              ),
            ),
            if (_units.length > 1) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: const ValueKey('intake-new-unit'),
                isExpanded: true,
                initialValue: _unit?.id,
                decoration: InputDecoration(labelText: l.unitLabel),
                items: [
                  for (final u in _units)
                    DropdownMenuItem(
                      value: u.id,
                      child: Text('${u.name} (${u.symbol})'),
                    ),
                ],
                onChanged: _busy
                    ? null
                    : (id) => setState(
                        () => _unit = _units.firstWhere((u) => u.id == id),
                      ),
              ),
            ],
            if (_error != null && _error!.fields.isEmpty) ...[
              const SizedBox(height: 12),
              Semantics(
                liveRegion: true,
                child: Text(
                  apiErrorText(l, _error!),
                  key: const ValueKey('intake-new-error'),
                  style: const TextStyle(color: AppColors.danger),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: Text(l.cancel),
        ),
        FilledButton(
          key: const ValueKey('intake-new-save'),
          onPressed: _busy ? null : _save,
          child: Text(l.intakeSaveProduct),
        ),
      ],
    );
  }
}
