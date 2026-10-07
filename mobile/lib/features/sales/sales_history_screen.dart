import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/format/format_stamp.dart';
import '../../core/money/decimal_math.dart';
import '../../core/session/session_controller.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../shared/async_section.dart';
import 'document_buttons.dart';
import 'sales_models.dart';
import 'sales_repository.dart';

String _methodsText(AppLocalizations l, List<String> methods) => methods
    .map(
      (m) => switch (m) {
        'cash' => l.payCash,
        'card' => l.payCard,
        _ => l.payTransfer,
      },
    )
    .join(' + ');

/// Past sales, newest first, searchable by number or customer. Read-only: a completed sale
/// is a historical record; returns and corrections are separate documents.
class SalesHistoryScreen extends StatefulWidget {
  const SalesHistoryScreen({
    super.key,
    required this.session,
    required this.repository,
  });

  final SessionController session;
  final SalesRepository repository;

  @override
  State<SalesHistoryScreen> createState() => _SalesHistoryScreenState();
}

class _SalesHistoryScreenState extends State<SalesHistoryScreen> {
  static const _pageSize = 30;
  final _search = TextEditingController();
  Timer? _debounce;
  List<SaleSummary> _items = const [];
  int _count = 0;
  bool _loading = true;
  Object? _error;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({required bool reset}) async {
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = null;
      if (reset) _items = const [];
    });
    try {
      final page = await widget.repository.sales(
        query: _search.text,
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
      appBar: AppBar(title: Text(l.saleHistoryTitle)),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 860),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                TextField(
                  key: const ValueKey('history-search'),
                  controller: _search,
                  onChanged: (_) {
                    _debounce?.cancel();
                    _debounce = Timer(
                      const Duration(milliseconds: 350),
                      () => _load(reset: true),
                    );
                  },
                  decoration: InputDecoration(
                    labelText: l.saleSearchHint,
                    prefixIcon: const Icon(Icons.search),
                  ),
                ),
                const SizedBox(height: 16),
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
                      key: const ValueKey('sales-history-empty'),
                      title: l.salesHistoryEmpty,
                      subtitle: '',
                      icon: Icons.receipt_long_outlined,
                    ),
                  )
                else ...[
                  for (final sale in _items)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _SaleTile(
                        sale: sale,
                        onTap: () => Navigator.of(context).push<void>(
                          MaterialPageRoute(
                            builder: (_) => SaleDetailScreen(
                              saleId: sale.id,
                              session: widget.session,
                              repository: widget.repository,
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (_items.length < _count)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton(
                        key: const ValueKey('sales-load-more'),
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

class _SaleTile extends StatelessWidget {
  const _SaleTile({required this.sale, required this.onTap});
  final SaleSummary sale;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = strings(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: ValueKey('sale-${saleNumber(sale.number)}'),
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: SurfaceCard(
          padding: 14,
          child: Wrap(
            spacing: 16,
            runSpacing: 6,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 200, maxWidth: 520),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${saleNumber(sale.number)} · ${formatStamp(sale.createdAt)}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      [
                        sale.locationName,
                        sale.cashierName,
                        if (sale.customerName.isNotEmpty) sale.customerName,
                      ].join(' · '),
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    formatMoney(sale.totalMinor, 'TMT'),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    _methodsText(l, sale.methods),
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One past sale in full, with its documents.
class SaleDetailScreen extends StatelessWidget {
  const SaleDetailScreen({
    super.key,
    required this.saleId,
    required this.session,
    required this.repository,
  });

  final String saleId;
  final SessionController session;
  final SalesRepository repository;

  @override
  Widget build(BuildContext context) {
    final l = strings(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.saleHistoryTitle)),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 860),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: AsyncSection<SaleDetail>(
                load: () => repository.sale(saleId),
                builder: (context, sale) => _body(context, sale),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, SaleDetail sale) {
    final l = strings(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l.saleDetailTitle(saleNumber(sale.number)),
                key: const ValueKey('sd-number'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              Text(
                '${formatStamp(sale.createdAt)} · ${sale.locationName}',
                style: const TextStyle(color: AppColors.muted),
              ),
              Text(l.cashierLine(sale.cashierName)),
              if (sale.customerName.isNotEmpty)
                Text('${l.customer}: ${sale.customerName}'),
              if (sale.usdRate != null)
                Text(
                  l.saleRateLine(sale.usdRate!),
                  style: const TextStyle(color: AppColors.muted, fontSize: 13),
                ),
              if (sale.note.isNotEmpty) Text(sale.note),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final line in sale.lines)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              line.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              l.saleUnitsLine(
                                '${formatQuantity(line.quantityMilli, line.unitDecimals)} ${line.unitSymbol}',
                                formatMoney(line.unitPriceMinor, 'TMT'),
                              ),
                              style: const TextStyle(
                                color: AppColors.muted,
                                fontSize: 13,
                              ),
                            ),
                            if (line.discountMinor > 0)
                              Text(
                                l.saleDiscountSum(
                                  formatMoney(line.discountMinor, 'TMT'),
                                ),
                                style: const TextStyle(fontSize: 13),
                              ),
                            if (line.warrantyMonths > 0)
                              Text(
                                l.warrantyMonthsValue(line.warrantyMonths),
                                style: const TextStyle(fontSize: 13),
                              ),
                          ],
                        ),
                      ),
                      Text(
                        formatMoney(line.lineTotalMinor, 'TMT'),
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              const Divider(),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  l.saleTotal(formatMoney(sale.totalMinor, 'TMT')),
                  key: const ValueKey('sd-total'),
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
              ),
              for (final p in sale.payments)
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    '${_methodsText(l, [p.method])}: ${formatMoney(p.amountMinor, 'TMT')}',
                    style: const TextStyle(color: AppColors.muted),
                  ),
                ),
              if (sale.changeMinor > 0)
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    l.changeSum(formatMoney(sale.changeMinor, 'TMT')),
                    style: const TextStyle(color: AppColors.muted),
                  ),
                ),
              if (sale.costTotalMinor != null && sale.profitMinor != null) ...[
                const Divider(),
                Text(
                  l.saleCostLine(formatMoney(sale.costTotalMinor!, 'TMT')),
                  key: const ValueKey('sd-cost'),
                  style: const TextStyle(color: AppColors.muted),
                ),
                Text(
                  l.saleProfitLine(formatMoney(sale.profitMinor!, 'TMT')),
                  key: const ValueKey('sd-profit'),
                  style: const TextStyle(color: AppColors.muted),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        SurfaceCard(
          child: DocumentButtons(
            repository: repository,
            saleId: sale.id,
            saleNumber: sale.number,
          ),
        ),
      ],
    );
  }
}
