import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api/api_error_text.dart';
import '../../core/api/api_exception.dart';
import '../../core/format/format_stamp.dart';
import '../../core/money/decimal_math.dart';
import '../../l10n/app_localizations.dart';
import '../../core/session/session_controller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../returns/returns_models.dart';
import '../sales/sales_models.dart';
import '../sales/sales_repository.dart';
import '../shared/async_section.dart';
import '../workspace/unsaved_work.dart';
import 'warranties_models.dart';
import 'warranties_repository.dart';

/// Open a warranty claim: find the sale (or arrive from it), choose the line, say what is
/// wrong. The warranty period comes from the sale (the product's terms at the time of the sale).
/// An expired or missing warranty can only be accepted by an owner or manager, with a reason.
/// Closes with the new claim.
class WarrantyNewScreen extends StatefulWidget {
  const WarrantyNewScreen({
    super.key,
    required this.session,
    required this.repository,
    required this.sales,
    required this.unsaved,
    this.saleId,
  });

  final SessionController session;
  final WarrantiesRepository repository;
  final SalesRepository sales;
  final UnsavedWork unsaved;

  /// Set when the person comes from a sale: the search step is skipped.
  final String? saleId;

  @override
  State<WarrantyNewScreen> createState() => _WarrantyNewScreenState();
}

class _WarrantyNewScreenState extends State<WarrantyNewScreen> {
  final _search = TextEditingController();
  Timer? _debounce;
  List<SaleSummary> _found = const [];
  bool _searching = false;
  Object? _searchError;
  String? _saleId;
  SaleLineRecord? _line;
  final _qty = TextEditingController();
  final _problem = TextEditingController();
  final _overrideNote = TextEditingController();
  bool _needOverride = false;
  bool _busy = false;
  ApiException? _error;

  @override
  void initState() {
    super.initState();
    _saleId = widget.saleId;
    if (_saleId == null) _find();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    widget.unsaved.mark(this, dirty: false);
    _search.dispose();
    _qty.dispose();
    _problem.dispose();
    _overrideNote.dispose();
    super.dispose();
  }

  Future<void> _find() async {
    setState(() {
      _searching = true;
      _searchError = null;
    });
    try {
      final page = await widget.sales.sales(query: _search.text, limit: 20);
      if (!mounted) return;
      setState(() {
        _found = page.items;
        _searching = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _searchError = e;
        _searching = false;
      });
    }
  }

  bool _expired(SaleLineRecord line) => warrantyExpired(
    warrantyMonths: line.warrantyMonths,
    warrantyUntil: line.warrantyUntil,
  );

  bool get _canOverride => widget.session.can('warranty.override');

  int? get _quantity {
    final line = _line;
    if (line == null) return null;
    final milli = parseReturnQuantity(_qty.text, line.unitDecimals);
    if (milli == null || milli > line.returnableMilli) return null;
    return milli;
  }

  bool get _overriding => _line != null && (_expired(_line!) || _needOverride);

  bool get _canSubmit =>
      _quantity != null &&
      _problem.text.trim().isNotEmpty &&
      (!_overriding || (_canOverride && _overrideNote.text.trim().isNotEmpty));

  Future<void> _submit() async {
    if (_busy || !_canSubmit) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    widget.unsaved.mark(this, dirty: true);
    try {
      final claim = await widget.repository.open(
        saleLineId: _line!.id,
        quantityMilli: _quantity!,
        problem: _problem.text.trim(),
        overrideNote: _overriding ? _overrideNote.text.trim() : null,
      );
      if (!mounted) return;
      widget.unsaved.mark(this, dirty: false);
      Navigator.of(context).pop(claim);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e;
        if (e.code == 'no_warranty' || e.code == 'warranty_expired') {
          _needOverride =
              true; // the server's date wins over this tablet's guess
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = strings(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.warrantyNew)),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: _saleId == null ? _searchStep(context) : _saleStep(context),
          ),
        ),
      ),
    );
  }

  Widget _searchStep(BuildContext context) {
    final l = strings(context);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          l.warrantyPickSale,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        TextField(
          key: const ValueKey('wn-search'),
          controller: _search,
          onChanged: (_) {
            _debounce?.cancel();
            _debounce = Timer(const Duration(milliseconds: 350), _find);
          },
          decoration: InputDecoration(
            labelText: l.saleSearchHint,
            prefixIcon: const Icon(Icons.search),
          ),
        ),
        const SizedBox(height: 16),
        if (_searchError != null)
          ErrorPanel(error: _searchError!, onRetry: _find)
        else if (_searching && _found.isEmpty)
          const Center(child: CircularProgressIndicator())
        else if (_found.isEmpty)
          SurfaceCard(
            child: EmptyState(
              key: const ValueKey('wn-empty'),
              title: l.salesHistoryEmpty,
              subtitle: '',
              icon: Icons.receipt_long_outlined,
            ),
          )
        else
          for (final s in _found)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  key: ValueKey('wn-sale-${saleNumber(s.number)}'),
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => setState(() => _saleId = s.id),
                  child: SurfaceCard(
                    padding: 14,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${saleNumber(s.number)} · ${formatStamp(s.createdAt)}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          [
                            s.locationName,
                            if (s.customerName.isNotEmpty) s.customerName,
                          ].join(' · '),
                          style: const TextStyle(
                            color: AppColors.muted,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
      ],
    );
  }

  Widget _saleStep(BuildContext context) {
    final l = strings(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: AsyncSection<SaleDetail>(
        load: () => widget.sales.sale(_saleId!),
        builder: (context, sale) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l.returnFromSale(saleNumber(sale.number)),
              key: const ValueKey('wn-sale'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (sale.customerName.isNotEmpty)
              Text('${l.customer}: ${sale.customerName}'),
            const SizedBox(height: 12),
            Text(l.warrantyPickLine),
            const SizedBox(height: 8),
            for (final line in sale.lines) _lineCard(context, line),
            if (_line != null) ..._form(context, _line!),
          ],
        ),
      ),
    );
  }

  Widget _lineCard(BuildContext context, SaleLineRecord line) {
    final l = strings(context);
    final expired = _expired(line);
    final selected = _line?.id == line.id;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: ValueKey('wn-line-${line.sku}'),
          borderRadius: BorderRadius.circular(16),
          onTap: () => setState(() {
            _line = line;
            _needOverride = false;
            _error = null;
            _qty.text = formatQuantity(line.returnableMilli, line.unitDecimals);
          }),
          child: SurfaceCard(
            padding: 14,
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${line.name} · ${line.sku}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        line.warrantyMonths <= 0
                            ? l.warrantyNone
                            : expired
                            ? l.warrantyExpiredLine(line.warrantyUntil ?? '')
                            : l.warrantyUntilLine(line.warrantyUntil ?? ''),
                        key: ValueKey('wn-warranty-${line.sku}'),
                        style: TextStyle(
                          color: expired ? AppColors.danger : AppColors.muted,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                if (selected)
                  const Icon(Icons.check_circle, color: AppColors.blue),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _form(BuildContext context, SaleLineRecord line) {
    final l = strings(context);
    return [
      const SizedBox(height: 8),
      if (line.returnableMilli <= 0)
        Text(
          l.returnNothingToReturn,
          style: const TextStyle(color: AppColors.danger),
        ),
      Semantics(
        container: true,
        explicitChildNodes: true,
        child: SizedBox(
          width: 190,
          child: TextField(
            key: const ValueKey('wn-qty'),
            controller: _qty,
            enabled: !_busy,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: l.quantity,
              suffixText: line.unitSymbol,
              errorText: _quantity == null ? l.fieldInvalid : null,
            ),
          ),
        ),
      ),
      const SizedBox(height: 12),
      Semantics(
        container: true,
        explicitChildNodes: true,
        child: TextField(
          key: const ValueKey('wn-problem'),
          controller: _problem,
          enabled: !_busy,
          minLines: 2,
          maxLines: 4,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(labelText: l.warrantyProblemLabel),
        ),
      ),
      if (_overriding) ...[
        const SizedBox(height: 12),
        if (_canOverride) ...[
          Text(
            l.warrantyOverrideHint,
            key: const ValueKey('wn-override-hint'),
            style: const TextStyle(color: AppColors.warning),
          ),
          const SizedBox(height: 8),
          Semantics(
            container: true,
            explicitChildNodes: true,
            child: TextField(
              key: const ValueKey('wn-override-note'),
              controller: _overrideNote,
              enabled: !_busy,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(labelText: l.warrantyOverrideNote),
            ),
          ),
        ] else
          Text(
            l.warrantyBlocked,
            key: const ValueKey('wn-blocked'),
            style: const TextStyle(color: AppColors.danger),
          ),
      ],
      if (_error != null) ...[
        const SizedBox(height: 12),
        Semantics(
          liveRegion: true,
          child: Text(
            _errorText(l, _error!),
            key: const ValueKey('wn-error'),
            style: const TextStyle(color: AppColors.danger),
          ),
        ),
      ],
      const SizedBox(height: 20),
      GradientButton(
        key: const ValueKey('wn-open'),
        label: l.warrantyOpenButton,
        icon: Icons.verified_user_outlined,
        onPressed: _busy || !_canSubmit ? null : _submit,
      ),
    ];
  }

  String _errorText(AppLocalizations l, ApiException e) => switch (e.code) {
    'no_warranty' => l.errorNoWarranty,
    'warranty_expired' => l.errorWarrantyExpired('${e.params['until'] ?? ''}'),
    _ => apiErrorText(l, e),
  };
}
