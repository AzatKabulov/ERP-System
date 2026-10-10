import 'package:flutter/material.dart';

import '../../core/api/api_error_text.dart';
import '../../core/api/api_exception.dart';
import '../../core/money/decimal_math.dart';
import '../../core/session/session_controller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../inventory/quantity_input.dart';
import '../shared/async_section.dart';
import 'catalog_models.dart';
import 'catalog_repository.dart';

/// On the product page: the minimum and the target stock at each place (the reorder list is
/// built from them). Owners and managers can change them.
class ReorderLevelsCard extends StatefulWidget {
  const ReorderLevelsCard({
    super.key,
    required this.product,
    required this.repository,
    required this.session,
  });

  final Product product;
  final CatalogRepository repository;
  final SessionController session;

  @override
  State<ReorderLevelsCard> createState() => _ReorderLevelsCardState();
}

class _ReorderLevelsCardState extends State<ReorderLevelsCard> {
  final _section = GlobalKey<AsyncSectionState<List<ReorderLevel>>>();

  Future<void> _edit(List<ReorderLevel> levels) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ReorderLevelsScreen(
          product: widget.product,
          repository: widget.repository,
          session: widget.session,
          levels: levels,
        ),
      ),
    );
    if (saved == true && mounted) {
      showFeedback(context, strings(context).reorderLevelsSaved);
      _section.currentState?.reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = strings(context);
    return SurfaceCard(
      child: AsyncSection<List<ReorderLevel>>(
        key: _section,
        load: () => widget.repository.reorderLevels(widget.product.id),
        builder: (context, levels) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeading(l.reorderLevelsTitle),
            const SizedBox(height: 8),
            if (levels.isEmpty)
              Text(
                l.reorderLevelsNone,
                key: const ValueKey('pd-reorder-none'),
                style: const TextStyle(color: AppColors.muted),
              ),
            for (final r in levels)
              Text(
                '${r.locationName}: ${l.reorderLevelLine(quantityWithUnit(r.minimumMilli, widget.product.unit), quantityWithUnit(r.targetMilli, widget.product.unit))}',
                key: ValueKey('pd-reorder-${r.locationId}'),
              ),
            if (widget.session.can('catalog.manage')) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                key: const ValueKey('pd-reorder-edit'),
                onPressed: () => _edit(levels),
                icon: const Icon(Icons.tune),
                label: Text(l.reorderLevelsEdit),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// One row per location: minimum and target. Leave both empty to have no level there.
class ReorderLevelsScreen extends StatefulWidget {
  const ReorderLevelsScreen({
    super.key,
    required this.product,
    required this.repository,
    required this.session,
    required this.levels,
  });

  final Product product;
  final CatalogRepository repository;
  final SessionController session;
  final List<ReorderLevel> levels;

  @override
  State<ReorderLevelsScreen> createState() => _ReorderLevelsScreenState();
}

class _ReorderLevelsScreenState extends State<ReorderLevelsScreen> {
  late final _places = widget.session.membership!.locations;
  late final Map<String, TextEditingController> _min = {
    for (final p in _places)
      p.id: TextEditingController(text: _text(p.id, true)),
  };
  late final Map<String, TextEditingController> _target = {
    for (final p in _places)
      p.id: TextEditingController(text: _text(p.id, false)),
  };
  bool _saving = false;
  ApiException? _error;

  String _text(String locationId, bool minimum) {
    final found = widget.levels.where((r) => r.locationId == locationId);
    if (found.isEmpty) return '';
    return formatQuantity(
      minimum ? found.first.minimumMilli : found.first.targetMilli,
      widget.product.unit.decimalPlaces,
    );
  }

  @override
  void dispose() {
    for (final c in [..._min.values, ..._target.values]) {
      c.dispose();
    }
    super.dispose();
  }

  int? _milli(TextEditingController c) {
    final text = c.text.trim();
    if (text.isEmpty) return null;
    final milli = parseScaled(text, 3);
    if (milli == null) return -1;
    final decimals = widget.product.unit.decimalPlaces.clamp(0, 3);
    var step = 1;
    for (var i = 0; i < 3 - decimals; i++) {
      step *= 10;
    }
    return milli % step == 0 ? milli : -1;
  }

  /// Both filled and valid, both empty, or a problem to show.
  String? _problem(String id) {
    final l = strings(context);
    final min = _milli(_min[id]!);
    final target = _milli(_target[id]!);
    if (min == -1 || target == -1) return l.fieldInvalid;
    if ((min == null) != (target == null)) return l.fieldRequired;
    if (min != null && target! < min) return l.errorTargetBelowMinimum;
    return null;
  }

  bool get _valid => _places.every((p) => _problem(p.id) == null);

  Future<void> _save() async {
    if (_saving || !_valid) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.repository.saveReorderLevels(widget.product.id, [
        for (final p in _places)
          if (_milli(_min[p.id]!) != null)
            (
              locationId: p.id,
              minimumMilli: _milli(_min[p.id]!)!,
              targetMilli: _milli(_target[p.id]!)!,
            ),
      ]);
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = e;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = strings(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.reorderLevelsTitle)),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '${widget.product.name} · ${widget.product.sku}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  for (final p in _places)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: SurfaceCard(
                        padding: 12,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              p.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 12,
                              runSpacing: 8,
                              children: [
                                for (final entry in [
                                  (_min[p.id]!, l.reorderMinLabel, 'min'),
                                  (
                                    _target[p.id]!,
                                    l.reorderTargetLabel,
                                    'target',
                                  ),
                                ])
                                  Semantics(
                                    container: true,
                                    explicitChildNodes: true,
                                    child: SizedBox(
                                      width: 170,
                                      child: TextField(
                                        key: ValueKey('rl-${entry.$3}-${p.id}'),
                                        controller: entry.$1,
                                        enabled: !_saving,
                                        keyboardType:
                                            const TextInputType.numberWithOptions(
                                              decimal: true,
                                            ),
                                        onChanged: (_) => setState(() {}),
                                        decoration: InputDecoration(
                                          labelText: entry.$2,
                                          suffixText:
                                              widget.product.unit.symbol,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            if (_problem(p.id) != null)
                              Text(
                                _problem(p.id)!,
                                style: const TextStyle(
                                  color: AppColors.danger,
                                  fontSize: 13,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  if (_error != null)
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        apiErrorText(l, _error!),
                        key: const ValueKey('rl-error'),
                        style: const TextStyle(color: AppColors.danger),
                      ),
                    ),
                  const SizedBox(height: 16),
                  GradientButton(
                    key: const ValueKey('rl-save'),
                    label: l.save,
                    icon: Icons.check,
                    onPressed: _saving || !_valid ? null : _save,
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
