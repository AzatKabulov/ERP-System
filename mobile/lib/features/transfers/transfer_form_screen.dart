import 'package:flutter/material.dart';

import '../../core/api/api_error_text.dart';
import '../../core/api/api_exception.dart';
import '../../core/connectivity/connection_monitor.dart';
import '../../core/money/decimal_math.dart';
import '../../core/operations/operation_runner.dart';
import '../../core/session/session_controller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../admin/admin_repository.dart';
import '../catalog/catalog_repository.dart';
import '../catalog/product_picker.dart';
import '../inventory/inventory_models.dart';
import '../inventory/quantity_input.dart';
import '../inventory/stock_entry_screen.dart' show EntryResult;
import '../../l10n/app_localizations.dart';
import '../workspace/unsaved_work.dart';
import 'transfers_repository.dart';

class _Line {
  _Line(this.product);
  final ProductRef product;
  final controller = TextEditingController(text: '1');
}

/// Send goods from one of your locations to another. Sent through the [OperationRunner]: the
/// request and its operation key are saved on the device before sending, so a timeout, crash
/// or restart can never send the same goods twice.
class TransferFormScreen extends StatefulWidget {
  const TransferFormScreen({
    super.key,
    required this.session,
    required this.repository,
    required this.admin,
    required this.catalog,
    required this.runner,
    required this.monitor,
    required this.unsaved,
  });

  final SessionController session;
  final TransfersRepository repository;
  final AdminRepository admin;
  final CatalogRepository catalog;
  final OperationRunner runner;
  final ConnectionMonitor monitor;
  final UnsavedWork unsaved;

  @override
  State<TransferFormScreen> createState() => _TransferFormScreenState();
}

class _TransferFormScreenState extends State<TransferFormScreen> {
  final _lines = <_Line>[];
  final _note = TextEditingController();
  late String? _fromId =
      widget.session.location?.id ??
      widget.session.membership?.locations.firstOrNull?.id;
  String? _toId;
  List<LocationRecord> _all = const [];
  bool _dirty = false;
  bool _submitted = false;
  bool _busy = false;
  ApiException? _error;

  @override
  void initState() {
    super.initState();
    widget.admin
        .locations()
        .then((all) {
          if (mounted) setState(() => _all = all);
        })
        .catchError((_) {
          // the destination list stays empty; the form says so
        });
  }

  @override
  void dispose() {
    widget.unsaved.mark(this, dirty: false);
    _note.dispose();
    for (final line in _lines) {
      line.controller.dispose();
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

  Future<void> _addProduct() async {
    final product = await showProductPicker(context, widget.catalog);
    if (product == null || !mounted) return;
    if (_lines.any((l) => l.product.id == product.id)) {
      showFeedback(context, strings(context).fieldDuplicateProduct);
      return;
    }
    _lines.add(_Line(ProductRef.fromProduct(product)));
    _touch();
  }

  int? _milli(_Line line) =>
      parseQuantity(line.controller.text, line.product.unit);

  bool get _valid =>
      _fromId != null &&
      _toId != null &&
      _fromId != _toId &&
      _lines.isNotEmpty &&
      _lines.every((l) => _milli(l) != null);

  Future<void> _submit() async {
    if (_busy) return;
    setState(() {
      _submitted = true;
      _error = null;
    });
    if (!_valid) return;
    final repo = widget.repository;
    setState(() => _busy = true);
    final outcome = await widget.runner.submit(
      action: 'transfer_dispatch',
      businessId: widget.session.membership!.businessId,
      path: repo.dispatchPath,
      body: repo.dispatchBody(
        fromId: _fromId!,
        toId: _toId!,
        note: _note.text.trim(),
        lines: [
          for (final l in _lines)
            (productId: l.product.id, quantityMilli: _milli(l)!),
        ],
      ),
      subject: _all.where((x) => x.id == _toId).firstOrNull?.name ?? '',
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

  String? _insufficientText(AppLocalizations l) {
    final e = _error;
    if (e == null || e.code != 'insufficient_stock') return null;
    final line = _lines
        .where((x) => x.product.id == e.params['product'])
        .firstOrNull;
    if (line == null) return null;
    final available = parseServerDecimal('${e.params['available']}', 3) ?? 0;
    return l.errorInsufficientNamed(
      line.product.name,
      quantityWithUnit(available, line.product.unit),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = strings(context);
    final mine = widget.session.membership?.locations ?? const [];
    final destinations = [
      for (final x in _all)
        if (x.isActive && x.id != _fromId) x,
    ];
    return PopScope(
      canPop: !_dirty || _busy,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final leave = await confirmAction(
          context,
          l.transferNew,
          l.unsavedChangeConflict,
        );
        if (leave && context.mounted) {
          _dirty = false;
          widget.unsaved.mark(this, dirty: false);
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(title: Text(l.transferNew)),
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
                      key: const ValueKey('transfer-from'),
                      isExpanded: true,
                      initialValue: mine.any((x) => x.id == _fromId)
                          ? _fromId
                          : null,
                      decoration: InputDecoration(
                        labelText: l.transferFromLabel,
                      ),
                      items: [
                        for (final x in mine)
                          DropdownMenuItem(value: x.id, child: Text(x.name)),
                      ],
                      onChanged: _busy
                          ? null
                          : (v) {
                              _fromId = v;
                              if (_toId == v) _toId = null;
                              _touch();
                            },
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      key: const ValueKey('transfer-to'),
                      isExpanded: true,
                      initialValue: destinations.any((x) => x.id == _toId)
                          ? _toId
                          : null,
                      decoration: InputDecoration(
                        labelText: l.transferToLabel,
                        errorText: _submitted && _toId == null
                            ? l.fieldRequired
                            : null,
                      ),
                      items: [
                        for (final x in destinations)
                          DropdownMenuItem(value: x.id, child: Text(x.name)),
                      ],
                      onChanged: _busy
                          ? null
                          : (v) {
                              _toId = v;
                              _touch();
                            },
                    ),
                    const SizedBox(height: 20),
                    for (var i = 0; i < _lines.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: SurfaceCard(
                          padding: 12,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${_lines[i].product.name} · ${_lines[i].product.sku}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                crossAxisAlignment: WrapCrossAlignment.start,
                                children: [
                                  SizedBox(
                                    width: 160,
                                    child: TextField(
                                      key: ValueKey('transfer-qty-$i'),
                                      controller: _lines[i].controller,
                                      enabled: !_busy,
                                      keyboardType:
                                          const TextInputType.numberWithOptions(
                                            decimal: true,
                                          ),
                                      onChanged: (_) => _touch(),
                                      decoration: InputDecoration(
                                        labelText: l.quantity,
                                        suffixText:
                                            _lines[i].product.unit.symbol,
                                        errorText:
                                            _submitted &&
                                                _milli(_lines[i]) == null
                                            ? l.fieldQuantityPrecision
                                            : null,
                                        errorMaxLines: 3,
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    key: ValueKey('transfer-remove-$i'),
                                    tooltip: l.removeLine,
                                    onPressed: _busy
                                        ? null
                                        : () {
                                            _lines
                                                .removeAt(i)
                                                .controller
                                                .dispose();
                                            _touch();
                                          },
                                    icon: const Icon(Icons.delete_outline),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (_submitted && _lines.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          l.entryNeedsLines,
                          key: const ValueKey('transfer-needs-lines'),
                          style: const TextStyle(color: AppColors.danger),
                        ),
                      ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                        key: const ValueKey('transfer-add-line'),
                        onPressed: _busy ? null : _addProduct,
                        icon: const Icon(Icons.add),
                        label: Text(l.addLineProduct),
                      ),
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      key: const ValueKey('transfer-note'),
                      controller: _note,
                      enabled: !_busy,
                      onChanged: (_) => _touch(),
                      decoration: InputDecoration(labelText: l.noteLabel),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          _insufficientText(l) ?? apiErrorText(l, _error!),
                          key: const ValueKey('transfer-error'),
                          style: const TextStyle(color: AppColors.danger),
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
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
                            key: const ValueKey('transfer-submit'),
                            label: l.transferSend,
                            icon: Icons.local_shipping_outlined,
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
