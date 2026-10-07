import 'package:flutter/material.dart';

import '../../core/format/format_stamp.dart';
import '../../core/money/decimal_math.dart';
import '../../core/session/session_controller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../inventory/quantity_input.dart';
import '../returns/returns_models.dart';
import '../shared/async_section.dart';
import 'purchasing_models.dart';
import 'purchasing_repository.dart';

/// Goods that went back to suppliers, newest first. Read-only: a return is a record; it is
/// made from the delivery it belongs to (the order's page).
class SupplierReturnsScreen extends StatefulWidget {
  const SupplierReturnsScreen({
    super.key,
    required this.session,
    required this.repository,
  });

  final SessionController session;
  final PurchasingRepository repository;

  @override
  State<SupplierReturnsScreen> createState() => _SupplierReturnsScreenState();
}

class _SupplierReturnsScreenState extends State<SupplierReturnsScreen> {
  static const _pageSize = 30;
  List<SupplierReturnRecord> _items = const [];
  int _count = 0;
  bool _loading = true;
  Object? _error;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  Future<void> _load({required bool reset}) async {
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = null;
      if (reset) _items = const [];
    });
    try {
      final page = await widget.repository.supplierReturns(
        offset: reset ? 0 : _items.length,
        limit: _pageSize,
      );
      if (!mounted || request != _request) return;
      setState(() {
        _items = reset ? page.items : [..._items, ...page.items];
        _count = page.count;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || request != _request) return;
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
      appBar: AppBar(title: Text(l.supplierReturnsTitle)),
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
                      key: const ValueKey('supplier-returns-empty'),
                      title: l.supplierReturnsEmpty,
                      subtitle: '',
                      icon: Icons.undo,
                    ),
                  )
                else ...[
                  for (final r in _items)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: SurfaceCard(
                        key: ValueKey(
                          'supplier-return-${supplierReturnNumber(r.number)}',
                        ),
                        padding: 14,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${supplierReturnNumber(r.number)} · ${formatStamp(r.createdAt)}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              '${l.supplierReturnSource(r.supplierName, r.deliveryNumber.toString())} · ${r.locationName}',
                              style: const TextStyle(
                                color: AppColors.muted,
                                fontSize: 13,
                              ),
                            ),
                            Text('${l.returnReasonShort}: ${r.reason}'),
                            for (final line in r.lines)
                              Text(
                                '${line.product.name}: ${quantityWithUnit(line.quantityMilli, line.product.unit)} · ${returnConditionLabel(l, line.condition)}',
                                style: const TextStyle(fontSize: 13),
                              ),
                            if (r.creditMinor != null)
                              Text(
                                l.supplierReturnCredit(
                                  formatMoney(r.creditMinor!, 'TMT'),
                                ),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  if (_items.length < _count)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton(
                        key: const ValueKey('supplier-returns-load-more'),
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
