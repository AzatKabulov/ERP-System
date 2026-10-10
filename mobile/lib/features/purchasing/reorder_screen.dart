import 'package:flutter/material.dart';

import '../../core/money/decimal_math.dart';
import '../../core/session/session_controller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../catalog/catalog_repository.dart';
import '../inventory/quantity_input.dart';
import '../shared/async_section.dart';
import '../workspace/unsaved_work.dart';
import 'order_form_screen.dart';
import 'purchasing_models.dart';
import 'purchasing_repository.dart';

/// What to buy again: the products that are below their minimum at a place (counting what is
/// already ordered), each with a suggested quantity up to its target. Nothing is ordered here:
/// pick what you want and the order form opens with those lines, so a person reviews it and
/// chooses the supplier.
class ReorderScreen extends StatefulWidget {
  const ReorderScreen({
    super.key,
    required this.session,
    required this.repository,
    required this.catalog,
    required this.unsaved,
  });

  final SessionController session;
  final PurchasingRepository repository;
  final CatalogRepository catalog;
  final UnsavedWork unsaved;

  @override
  State<ReorderScreen> createState() => _ReorderScreenState();
}

class _ReorderScreenState extends State<ReorderScreen> {
  String? _locationId;
  final Set<String> _picked = {};

  String _key(ReorderRow r) => '${r.locationId}|${r.product.id}';

  Future<void> _create(List<ReorderRow> rows) async {
    final chosen = [
      for (final r in rows)
        if (_picked.contains(_key(r))) r,
    ];
    if (chosen.isEmpty) return;
    final saved = await Navigator.of(context).push<PurchaseOrder>(
      MaterialPageRoute(
        builder: (_) => OrderFormScreen(
          session: widget.session,
          repository: widget.repository,
          catalog: widget.catalog,
          unsaved: widget.unsaved,
          initialLocationId: chosen.first.locationId,
          initialLines: [
            for (final r in chosen)
              OrderDraftLine(
                product: r.product,
                quantityText: formatQuantity(
                  r.suggestedMilli,
                  r.product.unit.decimalPlaces,
                ),
                costText: r.defaultCostMinor == null
                    ? ''
                    : toServerDecimal(
                        r.defaultCostMinor!,
                        2,
                      ).replaceAll('.', ','),
              ),
          ],
        ),
      ),
    );
    if (saved != null && mounted) {
      showFeedback(context, strings(context).orderSaved);
      Navigator.of(context).pop(saved);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = strings(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.reorderTitle)),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 860),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: AsyncSection<List<ReorderRow>>(
                load: widget.repository.reorderSuggestions,
                builder: (context, all) {
                  if (all.isEmpty) {
                    return SurfaceCard(
                      child: EmptyState(
                        key: const ValueKey('reorder-empty'),
                        title: l.reorderEmpty,
                        subtitle: '',
                        icon: Icons.check_circle_outline,
                      ),
                    );
                  }
                  final places = <String, String>{
                    for (final r in all) r.locationId: r.locationName,
                  };
                  final active = places.containsKey(_locationId)
                      ? _locationId!
                      : places.keys.first;
                  final rows = [
                    for (final r in all)
                      if (r.locationId == active) r,
                  ];
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        l.reorderScreenHint,
                        style: const TextStyle(color: AppColors.muted),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final entry in places.entries)
                            ChoiceChip(
                              key: ValueKey('reorder-place-${entry.key}'),
                              label: Text(entry.value),
                              selected: entry.key == active,
                              onSelected: (_) => setState(() {
                                _locationId = entry.key;
                                _picked.clear();
                              }),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      for (final r in rows)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: SurfaceCard(
                            padding: 12,
                            child: Material(
                              color: Colors.transparent,
                              child: CheckboxListTile(
                                key: ValueKey('reorder-${r.product.sku}'),
                                contentPadding: EdgeInsets.zero,
                                controlAffinity:
                                    ListTileControlAffinity.leading,
                                value: _picked.contains(_key(r)),
                                onChanged: (v) => setState(() {
                                  if (v ?? false) {
                                    _picked.add(_key(r));
                                  } else {
                                    _picked.remove(_key(r));
                                  }
                                }),
                                title: Text(
                                  '${r.product.name} · ${r.product.sku}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                subtitle: Text(
                                  '${l.reorderRowLine(quantityWithUnit(r.onHandMilli, r.product.unit), quantityWithUnit(r.onOrderMilli, r.product.unit), quantityWithUnit(r.minimumMilli, r.product.unit))}\n'
                                  '${l.reorderSuggested(quantityWithUnit(r.suggestedMilli, r.product.unit))}',
                                ),
                                isThreeLine: true,
                              ),
                            ),
                          ),
                        ),
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: GradientButton(
                          key: const ValueKey('reorder-create'),
                          label: l.reorderCreate,
                          icon: Icons.shopping_cart_outlined,
                          onPressed: _picked.isEmpty
                              ? null
                              : () => _create(rows),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
