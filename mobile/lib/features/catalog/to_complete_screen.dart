import 'package:flutter/material.dart';
import '../../widgets/app_icons.dart';
import 'package:flutter/services.dart';

import '../../core/api/api_error_text.dart';
import '../../core/api/api_exception.dart';
import '../../core/money/decimal_math.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../shared/async_section.dart';
import 'catalog_models.dart';
import 'catalog_repository.dart';

/// Products can be added without a price, but profit needs the cost of the goods. This page
/// lists what is still missing and lets the owner or a manager fill it in, a row at a time.
/// Entering a cost also corrects the goods already sold, so past profit becomes right.
class ToCompleteScreen extends StatefulWidget {
  const ToCompleteScreen({super.key, required this.repository});

  final CatalogRepository repository;

  @override
  State<ToCompleteScreen> createState() => _ToCompleteScreenState();
}

class _ToCompleteScreenState extends State<ToCompleteScreen> {
  final _section = GlobalKey<AsyncSectionState<List<ToCompleteItem>>>();

  @override
  Widget build(BuildContext context) {
    final l = strings(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.toCompleteTitle)),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            l.toCompleteHint,
            style: const TextStyle(color: AppColors.muted, height: 1.5),
          ),
          const SizedBox(height: 16),
          AsyncSection<List<ToCompleteItem>>(
            key: _section,
            load: widget.repository.toComplete,
            builder: (context, items) {
              if (items.isEmpty) {
                return SurfaceCard(
                  child: EmptyState(
                    key: const ValueKey('complete-none'),
                    title: l.toCompleteNone,
                    icon: AppIcons.checkCircle,
                  ),
                );
              }
              return Column(
                children: [
                  for (final item in items)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _CompleteRow(
                        key: ValueKey('complete-${item.sku}'),
                        item: item,
                        repository: widget.repository,
                        onSaved: () => _section.currentState?.reload(),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _CompleteRow extends StatefulWidget {
  const _CompleteRow({
    super.key,
    required this.item,
    required this.repository,
    required this.onSaved,
  });

  final ToCompleteItem item;
  final CatalogRepository repository;
  final VoidCallback onSaved;

  @override
  State<_CompleteRow> createState() => _CompleteRowState();
}

class _CompleteRowState extends State<_CompleteRow> {
  final _price = TextEditingController();
  final _cost = TextEditingController();
  bool _saving = false;
  String? _priceError;
  String? _costError;
  String? _error;

  @override
  void dispose() {
    _price.dispose();
    _cost.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final l = strings(context);
    final item = widget.item;
    int? price;
    int? cost;
    String? priceError;
    String? costError;
    if (item.missingPrice && _price.text.trim().isNotEmpty) {
      price = parseScaled(_price.text, 2);
      if (price == null || price <= 0) priceError = l.fieldInvalid;
    }
    if (item.missingCost && _cost.text.trim().isNotEmpty) {
      cost = parseScaled(
        _cost.text,
        2,
      ); // zero is allowed: the goods really were free
      if (cost == null) costError = l.fieldInvalid;
    }
    setState(() {
      _priceError = priceError;
      _costError = costError;
      _error = null;
    });
    if (priceError != null || costError != null) return;
    if (price == null && cost == null) {
      setState(() => _error = l.toCompleteNothingTyped);
      return;
    }
    setState(() => _saving = true);
    try {
      if (price != null) {
        await widget.repository.setPrice(item.id, price, item.priceCurrency);
      }
      if (cost != null) await widget.repository.setCost(item.id, cost);
      if (!mounted) return;
      showFeedback(context, l.toCompleteSaved);
      widget.onSaved();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = apiErrorText(l, e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _pieces(int milli) =>
      '${formatQuantity(milli, widget.item.unitDecimals)} ${widget.item.unitSymbol}';

  Widget _field({
    required Key key,
    required TextEditingController controller,
    required String label,
    required String suffix,
    String? error,
  }) => SizedBox(
    width: 220,
    child: LabeledField(
      label: label,
      child: TextField(
        key: key,
        controller: controller,
        enabled: !_saving,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[0-9.,  ]')),
        ],
        decoration: InputDecoration(
          suffixText: suffix,
          errorText: error,
          errorMaxLines: 3,
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final l = strings(context);
    final item = widget.item;
    return SurfaceCard(
      padding: 16,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            item.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 2),
          Text(
            item.sku,
            style: const TextStyle(color: AppColors.muted, fontSize: 13),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              if (item.missingPrice)
                StatusPill(label: l.toCompleteNoPrice, warning: true),
              if (item.missingCost)
                StatusPill(label: l.toCompleteNoCost, warning: true),
            ],
          ),
          if (item.stockWithoutCostMilli > 0) ...[
            const SizedBox(height: 6),
            Text(
              l.toCompleteStock(_pieces(item.stockWithoutCostMilli)),
              style: const TextStyle(fontSize: 13),
            ),
          ],
          if (item.soldWithoutCostMilli > 0) ...[
            const SizedBox(height: 2),
            Text(
              l.toCompleteSold(_pieces(item.soldWithoutCostMilli)),
              style: const TextStyle(fontSize: 13),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.start,
            children: [
              if (item.missingPrice)
                _field(
                  key: ValueKey('complete-price-${item.sku}'),
                  controller: _price,
                  label: l.toCompletePriceLabel,
                  suffix: item.priceCurrency,
                  error: _priceError,
                ),
              if (item.missingCost)
                _field(
                  key: ValueKey('complete-cost-${item.sku}'),
                  controller: _cost,
                  label: l.toCompleteCostLabel,
                  suffix: 'TMT',
                  error: _costError,
                ),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: PrimaryButton(
                  key: ValueKey('complete-save-${item.sku}'),
                  label: l.save,
                  icon: AppIcons.check,
                  onPressed: _saving ? null : _save,
                ),
              ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              key: ValueKey('complete-error-${item.sku}'),
              style: const TextStyle(color: AppColors.danger, fontSize: 13),
            ),
          ],
        ],
      ),
    );
  }
}
