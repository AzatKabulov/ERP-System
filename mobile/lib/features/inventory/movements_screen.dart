import 'package:flutter/material.dart';

import '../../core/format/format_stamp.dart';
import '../../core/money/decimal_math.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../shared/async_section.dart';
import 'inventory_models.dart';
import 'inventory_repository.dart';
import 'quantity_input.dart';
import 'stock_labels.dart';

/// The stock ledger, newest first, optionally for one product. Read-only: history
/// is never edited, a correction is a new movement.
class MovementsScreen extends StatefulWidget {
  const MovementsScreen({
    super.key,
    required this.repository,
    required this.canSeeCost,
    this.product,
  });

  final InventoryRepository repository;
  final bool canSeeCost;
  final ProductRef? product;

  @override
  State<MovementsScreen> createState() => _MovementsScreenState();
}

class _MovementsScreenState extends State<MovementsScreen> {
  static const _pageSize = 30;
  List<MovementRow> _items = const [];
  int _count = 0;
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  Future<void> _load({required bool reset}) async {
    setState(() {
      _loading = true;
      _error = null;
      if (reset) _items = const [];
    });
    try {
      final page = await widget.repository.movements(
        productId: widget.product?.id,
        offset: reset ? 0 : _items.length,
        limit: _pageSize,
      );
      if (!mounted) return;
      setState(() {
        _items = reset ? page.items : [..._items, ...page.items];
        _count = page.count;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = strings(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.product == null
              ? l.movementHistory
              : '${l.movementHistory}: ${widget.product!.name}',
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 860),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                if (_error != null)
                  ErrorPanel(error: _error!, onRetry: () => _load(reset: true))
                else if (_loading && _items.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_items.isEmpty)
                  SurfaceCard(
                    child: EmptyState(
                      key: const ValueKey('history-empty'),
                      title: l.historyEmpty,
                      subtitle: '',
                      icon: Icons.history,
                    ),
                  )
                else ...[
                  for (final m in _items)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _MovementTile(
                        movement: m,
                        canSeeCost: widget.canSeeCost,
                      ),
                    ),
                  if (_items.length < _count)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton(
                        key: const ValueKey('history-load-more'),
                        onPressed: _loading ? null : () => _load(reset: false),
                        child: Text(l.loadMore),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MovementTile extends StatelessWidget {
  const _MovementTile({required this.movement, required this.canSeeCost});
  final MovementRow movement;
  final bool canSeeCost;

  @override
  Widget build(BuildContext context) {
    final l = strings(context);
    final m = movement;
    final incoming = m.quantityMilli > 0;
    final sign = incoming ? '+' : '';
    return SurfaceCard(
      padding: 14,
      child: Wrap(
        spacing: 16,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        alignment: WrapAlignment.spaceBetween,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 200, maxWidth: 520),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  m.product.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  '${movementTypeLabel(l, m.type)} · ${m.locationName}'
                  '${m.condition == 'sellable' ? '' : ' · ${conditionLabel(l, m.condition)}'}',
                  style: const TextStyle(color: AppColors.muted, fontSize: 13),
                ),
                Text(
                  '${formatStamp(m.createdAt)} · ${m.actorName}',
                  style: const TextStyle(color: AppColors.muted, fontSize: 12),
                ),
                if (m.reason.isNotEmpty)
                  Text(m.reason, style: const TextStyle(fontSize: 13)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$sign${quantityWithUnit(m.quantityMilli, m.product.unit)}',
                key: ValueKey('movement-qty-${m.id}'),
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  color: incoming ? AppColors.success : AppColors.danger,
                ),
              ),
              if (canSeeCost && m.unitCostMinor != null)
                Text(
                  '@ ${formatMoney(m.unitCostMinor!, 'TMT')}',
                  style: const TextStyle(color: AppColors.muted, fontSize: 12),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
