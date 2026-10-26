import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../../widgets/app_icons.dart';

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
import '../inventory/quantity_input.dart';
import '../inventory/stock_entry_screen.dart' show EntryResult;
import '../scanning/barcode_scanner.dart';
import 'intake_controller.dart';
import 'intake_draft_store.dart';
import 'intake_models.dart';
import 'intake_repository.dart';
import 'intake_product_form.dart';

/// Receiving goods: scan one item, then type the total quantity in the box.
/// Keyboard entry and quantity editing remain available as a fallback.
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

  Future<void> _typed(String text) async {
    if (_busy || _formOpen) return;
    final entry = _ctl.scan(text);
    if (entry == null) return;
    _input.clear();
    await _edit(entry);
  }

  bool _formOpen = false;

  Future<void> _camera() async {
    if (_busy || _formOpen) return;
    final code = await ScannerScope.of(context).scan(context);
    if (!mounted || code == null || _busy) return;
    final entry = _ctl.scan(code);
    if (entry != null) await _edit(entry);
  }

  Future<void> _manual() async {
    if (_busy || _formOpen) return;
    await _edit(_ctl.addManual());
  }

  Future<void> _pickExisting() async {
    if (_busy || _formOpen) return;
    final product = await showProductPicker(context, widget.catalog);
    if (mounted && product != null) {
      await _edit(_ctl.addManual(product: product));
    }
  }

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
    if (_formOpen || _busy) return;
    _formOpen = true;
    try {
      await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => IntakeProductForm(
          entry: entry,
          controller: _ctl,
          catalog: widget.catalog,
          canCost: _canCost,
          canManage: session.can('catalog.manage'),
        ),
      );
    } finally {
      _formOpen = false;
    }
  }

  Future<void> _addProduct(IntakeEntry entry) => _edit(entry);
  Future<void> _addFound(IntakeEntry entry) => _edit(entry);

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
                    LabeledField(
                      label: l.intakeLocationLabel,
                      child: DropdownButtonFormField<String>(
                        key: const ValueKey('intake-location'),
                        isExpanded: true,
                        initialValue: mine.any((x) => x.id == _ctl.locationId)
                            ? _ctl.locationId
                            : null,
                        decoration: InputDecoration(),
                        items: [
                          for (final x in mine)
                            DropdownMenuItem(value: x.id, child: Text(x.name)),
                        ],
                        onChanged: _busy ? null : (v) => _ctl.setLocation(v),
                      ),
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
                            prefixIcon: const AppIcon(AppIcons.qr),
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
                            icon: const AppIcon(AppIcons.scan),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      if (session.can('catalog.manage'))
                        OutlinedButton.icon(
                          key: const ValueKey('intake-manual'),
                          onPressed: _busy ? null : _manual,
                          icon: const AppIcon(AppIcons.plus),
                          label: Text(l.intakeAddManually),
                        ),
                      TextButton.icon(
                        key: const ValueKey('intake-pick-existing'),
                        onPressed: _busy ? null : _pickExisting,
                        icon: const AppIcon(AppIcons.search),
                        label: Text(l.pickProductTitle),
                      ),
                    ],
                  ),
                  if (_resumed && !_ctl.isEmpty) ...[
                    const SizedBox(height: 12),
                    SurfaceCard(
                      padding: 12,
                      child: Row(
                        children: [
                          const AppIcon(
                            AppIcons.history,
                            color: AppColors.warning,
                          ),
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
                        onAddFound: () => _addFound(entry),
                        onRetry: () => _ctl.retryLookup(entry),
                      ),
                    ),
                  if (!_ctl.isEmpty) ...[
                    const SizedBox(height: 10),
                    LabeledField(
                      label: l.noteLabel,
                      child: TextField(
                        key: const ValueKey('intake-note'),
                        controller: _note,
                        enabled: !_busy,
                        decoration: InputDecoration(),
                      ),
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
                        PrimaryButton(
                          key: const ValueKey('intake-submit'),
                          label: l.intakeSubmit,
                          icon: AppIcons.box,
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
    required this.onAddFound,
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
  final VoidCallback onAddFound;
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
                        product?.name ??
                            (entry.isManual
                                ? entry.form['name'] ?? l.intakeAddManually
                                : entry.code),
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
                                IntakeEntryState.notFound =>
                                  entry.suggestion == null
                                      ? l.intakeUnknown
                                      : l.intakeFoundOnline(
                                          entry.suggestion!.displayName,
                                        ),
                                _ => l.intakeLookupFailed,
                              }
                            : entry.isManual
                            ? product.sku
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
                  icon: const AppIcon(AppIcons.trash),
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
                  icon: const AppIcon(AppIcons.minus),
                ),
                Semantics(
                  container: true,
                  button: true,
                  label: l.quantity,
                  child: InkWell(
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
                ),
                IconButton.filledTonal(
                  key: ValueKey('intake-plus-${entry.code}'),
                  tooltip: l.intakeMore,
                  onPressed: busy ? null : onPlus,
                  icon: const AppIcon(AppIcons.plus),
                ),
                if (entry.expiryDate != null)
                  Text(l.expiryDateValue(entry.expiryDate!)),
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
                if (unknown && entry.suggestion != null)
                  FilledButton.icon(
                    key: ValueKey('intake-add-found-${entry.code}'),
                    onPressed: busy ? null : onAddFound,
                    icon: const AppIcon(AppIcons.plus),
                    label: Text(l.intakeAddFound),
                  ),
                if (unknown && entry.suggestion == null)
                  FilledButton.tonalIcon(
                    key: ValueKey('intake-add-${entry.code}'),
                    onPressed: busy ? null : onAdd,
                    icon: const AppIcon(AppIcons.plus),
                    label: Text(l.intakeAddProduct),
                  ),
                if (unknown && entry.suggestion != null)
                  OutlinedButton.icon(
                    key: ValueKey('intake-add-${entry.code}'),
                    onPressed: busy ? null : onAdd,
                    icon: const AppIcon(AppIcons.edit),
                    label: Text(l.intakeEditFound),
                  ),
                if (entry.state == IntakeEntryState.lookupFailed)
                  OutlinedButton.icon(
                    key: ValueKey('intake-retry-${entry.code}'),
                    onPressed: busy ? null : onRetry,
                    icon: const AppIcon(AppIcons.retry),
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
