import 'package:flutter/material.dart';

import '../../core/api/api_error_text.dart';
import '../../core/api/api_exception.dart';
import '../../core/files/file_services.dart';
import '../../core/money/decimal_math.dart';
import '../../core/session/session_controller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../inventory/stock_labels.dart';
import '../purchasing/order_labels.dart';
import '../shared/async_section.dart';
import 'activity_view.dart';
import 'reports_models.dart';
import 'reports_repository.dart';

enum ReportTab {
  summary,
  sales,
  stock,
  purchasing,
  returns,
  expenses,
  activity,
}

String _tm(int minor) => formatMoney(minor, 'TMT');
String _qty(int milli) => formatQuantity(milli, 0);

/// The owner's review: the figures of a period (and optionally one location), one tab per
/// subject. Money figures a role may not see are never sent by the server; the page simply has
/// no card for them.
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({
    super.key,
    required this.session,
    required this.repository,
  });

  final SessionController session;
  final ReportsRepository repository;

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  ReportTab _tab = ReportTab.summary;
  ReportPeriod _period = ReportPeriod.month;
  String? _locationId;
  bool _exporting = false;

  SessionController get session => widget.session;

  List<ReportTab> get _tabs => [
    ReportTab.summary,
    ReportTab.sales,
    ReportTab.stock,
    ReportTab.purchasing,
    ReportTab.returns,
    if (session.can('expense.view')) ReportTab.expenses,
    if (session.can('audit.view')) ReportTab.activity,
  ];

  ReportQuery get _query =>
      ReportQuery.forPeriod(_period, locationId: _locationId);

  String _tabLabel(ReportTab tab) {
    final l = strings(context);
    return switch (tab) {
      ReportTab.summary => l.reportTabSummary,
      ReportTab.sales => l.reportTabSales,
      ReportTab.stock => l.reportTabStock,
      ReportTab.purchasing => l.reportTabPurchasing,
      ReportTab.returns => l.reportTabReturns,
      ReportTab.expenses => l.reportTabExpenses,
      ReportTab.activity => l.reportTabActivity,
    };
  }

  String _periodLabel(ReportPeriod p) {
    final l = strings(context);
    return switch (p) {
      ReportPeriod.today => l.reportPeriodToday,
      ReportPeriod.week => l.reportPeriodWeek,
      ReportPeriod.month => l.reportPeriodMonth,
      ReportPeriod.lastMonth => l.reportPeriodLast,
    };
  }

  Future<void> _export(String slug) async {
    if (_exporting) return;
    setState(() => _exporting = true);
    final l = strings(context);
    final q = _query;
    try {
      final bytes = await widget.repository.export(slug, q);
      if (!mounted) return;
      await FilesScope.sharingOf(
        context,
      ).share(bytes, '$slug-${q.from}-${q.to}.csv', 'text/csv');
      if (mounted) showFeedback(context, l.reportExported);
    } on ApiException catch (e) {
      if (mounted) showFeedback(context, apiErrorText(l, e));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = strings(context);
    final places = session.membership?.locations ?? const [];
    final tab = _tabs.contains(_tab) ? _tab : ReportTab.summary;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final t in _tabs)
              ChoiceChip(
                key: ValueKey('reports-tab-${t.name}'),
                label: Text(_tabLabel(t)),
                selected: tab == t,
                onSelected: (_) => setState(() => _tab = t),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final p in ReportPeriod.values)
              ChoiceChip(
                key: ValueKey('reports-period-${p.name}'),
                label: Text(_periodLabel(p)),
                selected: _period == p,
                onSelected: (_) => setState(() => _period = p),
              ),
            if (places.length > 1)
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 240),
                child: DropdownButton<String?>(
                  key: const ValueKey('reports-location'),
                  isExpanded: true,
                  value: places.any((p) => p.id == _locationId)
                      ? _locationId
                      : null,
                  items: [
                    DropdownMenuItem<String?>(
                      value: null,
                      child: Text(l.reportAllLocations),
                    ),
                    for (final p in places)
                      DropdownMenuItem<String?>(
                        value: p.id,
                        child: Text(p.name),
                      ),
                  ],
                  onChanged: (v) => setState(() => _locationId = v),
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),
        // A new key for every tab and filter: the section loads again from scratch.
        KeyedSubtree(
          key: ValueKey('${tab.name}|${_query.hashCode}'),
          child: _content(tab),
        ),
      ],
    );
  }

  Widget _exportButton(String slug) {
    final l = strings(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: OutlinedButton.icon(
        key: const ValueKey('report-export'),
        onPressed: _exporting ? null : () => _export(slug),
        icon: const Icon(Icons.download_outlined),
        label: Text(l.reportExport),
      ),
    );
  }

  Widget _content(ReportTab tab) {
    final q = _query;
    final repo = widget.repository;
    return switch (tab) {
      ReportTab.summary => AsyncSection<ReportSummary>(
        load: () => repo.summary(q),
        builder: (context, s) => _SummaryView(summary: s),
      ),
      ReportTab.sales => AsyncSection<SalesReport>(
        load: () => repo.sales(q),
        builder: (context, r) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _exportButton('sales'),
            const SizedBox(height: 12),
            _SalesView(report: r),
          ],
        ),
      ),
      ReportTab.stock => AsyncSection<StockReport>(
        load: () => repo.stock(q),
        builder: (context, r) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _exportButton('stock'),
            const SizedBox(height: 12),
            _StockView(report: r),
          ],
        ),
      ),
      ReportTab.purchasing => AsyncSection<PurchasingReport>(
        load: () => repo.purchasing(q),
        builder: (context, r) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _exportButton('purchasing'),
            const SizedBox(height: 12),
            _PurchasingView(report: r),
          ],
        ),
      ),
      ReportTab.returns => AsyncSection<ReturnsReport>(
        load: () => repo.returns(q),
        builder: (context, r) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _exportButton('returns'),
            const SizedBox(height: 12),
            _ReturnsView(report: r),
          ],
        ),
      ),
      ReportTab.expenses => AsyncSection<ExpensesReport>(
        load: () => repo.expenses(q),
        builder: (context, r) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _exportButton('expenses'),
            const SizedBox(height: 12),
            _ExpensesView(report: r),
          ],
        ),
      ),
      ReportTab.activity => ActivityView(repository: repo, period: q),
    };
  }
}

/// A figure with its name, for the plain lists below the cards.
class _Line extends StatelessWidget {
  const _Line(this.text, {super.key, this.muted = false});
  final String text;
  final bool muted;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Text(
      text,
      style: TextStyle(color: muted ? AppColors.muted : null, fontSize: 14),
    ),
  );
}

class _Block extends StatelessWidget {
  const _Block({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    // One node per card: a screen reader reads a card at a time, not the whole page at once.
    child: Semantics(
      container: true,
      child: SurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            ...children,
          ],
        ),
      ),
    ),
  );
}

Widget _metric(String key, String label, String value, IconData icon) =>
    KeyedSubtree(
      key: ValueKey(key),
      child: Semantics(
        container: true,
        child: MetricCard(label: label, value: value, icon: icon),
      ),
    );

class _SummaryView extends StatelessWidget {
  const _SummaryView({required this.summary});
  final ReportSummary summary;

  @override
  Widget build(BuildContext context) {
    final l = strings(context);
    final s = summary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AdaptiveGrid(
          children: [
            _metric(
              'rep-revenue',
              l.reportRevenue,
              _tm(s.revenue),
              Icons.payments_outlined,
            ),
            _metric(
              'rep-refunds',
              l.reportRefunds,
              _tm(s.refunds),
              Icons.assignment_return_outlined,
            ),
            _metric(
              'rep-net',
              l.reportNetSales,
              _tm(s.netSales),
              Icons.trending_up,
            ),
            if (s.costOfGoods != null)
              _metric(
                'rep-cost',
                l.reportCostOfGoods,
                _tm(s.costOfGoods!),
                Icons.inventory_2_outlined,
              ),
            if (s.grossProfit != null)
              _metric(
                'rep-profit',
                l.reportGrossProfit,
                _tm(s.grossProfit!),
                Icons.savings_outlined,
              ),
            if (s.expenses != null)
              _metric(
                'rep-expenses',
                l.reportExpenses,
                _tm(s.expenses!),
                Icons.account_balance_wallet_outlined,
              ),
            if (s.result != null)
              _metric(
                'rep-result',
                l.reportResult,
                _tm(s.result!),
                Icons.balance_outlined,
              ),
            if (s.inventoryValue != null)
              _metric(
                'rep-inventory',
                l.reportInventoryValue,
                _tm(s.inventoryValue!),
                Icons.warehouse_outlined,
              ),
            _metric(
              'rep-low-stock',
              l.reportLowStock,
              '${s.lowStockCount}',
              Icons.warning_amber_outlined,
            ),
            _metric(
              'rep-open-orders',
              l.reportOpenOrders,
              '${s.openOrdersCount}',
              Icons.local_shipping_outlined,
            ),
          ],
        ),
        const SizedBox(height: 12),
        _Line(
          '${l.reportSalesCount(s.salesCount)} · ${l.reportReturnsCount(s.returnsCount)}',
          key: const ValueKey('rep-counts'),
          muted: true,
        ),
        if (s.result != null)
          _Line(
            l.reportResultNote,
            key: const ValueKey('rep-result-note'),
            muted: true,
          ),
        if (s.inventoryValue != null) _Line(l.reportInventoryNote, muted: true),
      ],
    );
  }
}

class _SalesView extends StatelessWidget {
  const _SalesView({required this.report});
  final SalesReport report;

  @override
  Widget build(BuildContext context) {
    final l = strings(context);
    final r = report;
    final empty = r.salesCount == 0 && r.returnsCount == 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Block(
          title: l.reportTabSales,
          children: [
            _Line(
              '${l.reportRevenue}: ${_tm(r.revenue)}',
              key: const ValueKey('rep-sales-revenue'),
            ),
            _Line(
              '${l.reportRefunds}: ${_tm(r.refunds)}',
              key: const ValueKey('rep-sales-refunds'),
            ),
            _Line(
              '${l.reportNetSales}: ${_tm(r.netSales)}',
              key: const ValueKey('rep-sales-net'),
            ),
            if (r.costOfGoods != null)
              _Line(
                '${l.reportCostOfGoods}: ${_tm(r.costOfGoods!)}',
                key: const ValueKey('rep-sales-cost'),
              ),
            if (r.grossProfit != null)
              _Line(
                '${l.reportGrossProfit}: ${_tm(r.grossProfit!)}',
                key: const ValueKey('rep-sales-profit'),
              ),
            _Line(
              '${l.reportSalesCount(r.salesCount)} · ${l.reportReturnsCount(r.returnsCount)}',
              muted: true,
            ),
          ],
        ),
        if (empty)
          _Line(l.reportEmpty, key: const ValueKey('rep-empty'), muted: true),
        if (r.byPayment.isNotEmpty)
          _Block(
            title: l.reportByPayment,
            children: [
              for (final p in r.byPayment)
                _Line(
                  l.reportPaymentLine(
                    p.method == 'cash' ? l.payCash : l.payCard,
                    p.count,
                    _tm(p.total),
                  ),
                  key: ValueKey('rep-pay-${p.method}'),
                ),
            ],
          ),
        if (r.byDay.isNotEmpty)
          _Block(
            title: l.reportByDay,
            children: [
              for (final d in r.byDay)
                _Line(
                  l.reportDayLine(
                    d.date,
                    d.count,
                    _tm(d.revenue),
                    _tm(d.refunds),
                  ),
                  key: ValueKey('rep-day-${d.date}'),
                ),
            ],
          ),
        if (r.topProducts.isNotEmpty)
          _Block(
            title: l.reportTopProducts,
            children: [
              for (final p in r.topProducts) ...[
                _Line(
                  '${p.name} · ${p.sku}',
                  key: ValueKey('rep-top-${p.sku}'),
                ),
                _Line(
                  l.reportProductLine(
                    '${formatQuantity(p.quantityMilli, p.unitDecimals)} ${p.unitSymbol}',
                    _tm(p.revenue),
                  ),
                  muted: true,
                ),
              ],
            ],
          ),
      ],
    );
  }
}

class _StockView extends StatelessWidget {
  const _StockView({required this.report});
  final StockReport report;

  @override
  Widget build(BuildContext context) {
    final l = strings(context);
    final r = report;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (r.valueTotal != null)
          _Block(
            title: l.reportValueTitle,
            children: [
              _Line(
                '${l.reportInventoryValue}: ${_tm(r.valueTotal!)}',
                key: const ValueKey('rep-stock-value'),
              ),
              _Line(l.reportInventoryNote, muted: true),
              for (final v in r.valueByLocation) ...[
                _Line(
                  l.reportValueLine(v.locationName, _tm(v.total)),
                  key: ValueKey('rep-value-${v.locationName}'),
                ),
                for (final c in v.byCondition.entries)
                  if (c.value != 0)
                    _Line(
                      '   ${conditionLabel(l, c.key)}: ${_tm(c.value)}',
                      muted: true,
                    ),
              ],
            ],
          ),
        _Block(
          title: '${l.reportLowStockTitle} (${r.lowStockCount})',
          children: [
            if (r.lowStock.isEmpty)
              _Line(
                l.reportLowStockEmpty,
                key: const ValueKey('rep-low-empty'),
                muted: true,
              ),
            for (final row in r.lowStock) ...[
              _Line(
                '${row.name} · ${row.sku}',
                key: ValueKey('rep-low-${row.sku}-${row.locationName}'),
              ),
              _Line(
                l.reportLowStockRow(
                  row.locationName,
                  '${formatQuantity(row.onHandMilli, row.unitDecimals)} ${row.unitSymbol}',
                  '${formatQuantity(row.minimumMilli, row.unitDecimals)} ${row.unitSymbol}',
                ),
                muted: true,
              ),
            ],
          ],
        ),
        if (r.movements.isNotEmpty)
          _Block(
            title: l.reportMovementsTitle,
            children: [
              for (final m in r.movements)
                _Line(
                  l.reportMovementLine(
                    movementTypeLabel(l, m.type),
                    m.count,
                    _qty(m.inMilli),
                    _qty(m.outMilli),
                  ),
                  key: ValueKey('rep-move-${m.type}'),
                ),
            ],
          ),
      ],
    );
  }
}

class _PurchasingView extends StatelessWidget {
  const _PurchasingView({required this.report});
  final PurchasingReport report;

  @override
  Widget build(BuildContext context) {
    final l = strings(context);
    final r = report;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Block(
          title: l.reportTabPurchasing,
          children: [
            _Line(
              l.reportOrdersCount(r.ordersCount),
              key: const ValueKey('rep-orders'),
            ),
            _Line(
              l.reportDeliveriesCount(r.deliveriesCount),
              key: const ValueKey('rep-deliveries'),
            ),
            if (r.orderedTotal != null)
              _Line(
                l.reportOrderedTotal(_tm(r.orderedTotal!)),
                key: const ValueKey('rep-ordered-total'),
              ),
            if (r.receivedValue != null)
              _Line(
                l.reportReceivedValue(_tm(r.receivedValue!)),
                key: const ValueKey('rep-received-value'),
              ),
            _Line(
              r.supplierReturnsCredit == null
                  ? l.reportSupplierReturns(r.supplierReturnsCount)
                  : l.reportSupplierReturnsCredit(
                      r.supplierReturnsCount,
                      _tm(r.supplierReturnsCredit!),
                    ),
              key: const ValueKey('rep-supplier-returns'),
            ),
          ],
        ),
        if (r.byStatus.isNotEmpty)
          _Block(
            title: l.reportByStatus,
            children: [
              for (final (status, count) in r.byStatus)
                _Line(
                  '${orderStatusLabel(l, status)}: $count',
                  key: ValueKey('rep-status-$status'),
                ),
            ],
          ),
        if (r.bySupplier.isNotEmpty)
          _Block(
            title: l.reportBySupplier,
            children: [
              for (final s in r.bySupplier)
                _Line(
                  s.receivedValue == null
                      ? l.reportSupplierLine(s.name, s.orders)
                      : l.reportSupplierLineValue(
                          s.name,
                          s.orders,
                          _tm(s.receivedValue!),
                        ),
                  key: ValueKey('rep-supplier-${s.name}'),
                ),
            ],
          ),
      ],
    );
  }
}

class _ReturnsView extends StatelessWidget {
  const _ReturnsView({required this.report});
  final ReturnsReport report;

  @override
  Widget build(BuildContext context) {
    final l = strings(context);
    final r = report;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Block(
          title: l.reportTabReturns,
          children: [
            _Line(
              l.reportReturnsCount(r.returnsCount),
              key: const ValueKey('rep-returns-count'),
            ),
            _Line(
              l.reportRefundTotal(_tm(r.refundTotal)),
              key: const ValueKey('rep-refund-total'),
            ),
            _Line(
              r.supplierReturnsCredit == null
                  ? l.reportSupplierReturns(r.supplierReturnsCount)
                  : l.reportSupplierReturnsCredit(
                      r.supplierReturnsCount,
                      _tm(r.supplierReturnsCredit!),
                    ),
              key: const ValueKey('rep-returns-supplier'),
            ),
          ],
        ),
        if (r.byCondition.isNotEmpty)
          _Block(
            title: l.reportByCondition,
            children: [
              for (final c in r.byCondition)
                _Line(
                  l.reportConditionLine(
                    conditionLabel(l, c.condition),
                    _qty(c.quantityMilli),
                    _tm(c.refund),
                  ),
                  key: ValueKey('rep-cond-${c.condition}'),
                ),
            ],
          ),
        if (r.byReason.isNotEmpty)
          _Block(
            title: l.reportByReason,
            children: [
              for (final c in r.byReason)
                _Line(
                  l.reportReasonLine(c.reason, c.count, _tm(c.refund)),
                  key: ValueKey('rep-reason-${c.reason}'),
                ),
            ],
          ),
      ],
    );
  }
}

class _ExpensesView extends StatelessWidget {
  const _ExpensesView({required this.report});
  final ExpensesReport report;

  @override
  Widget build(BuildContext context) {
    final l = strings(context);
    final r = report;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Block(
          title: l.reportTabExpenses,
          children: [
            _Line(
              l.reportTotalLine(_tm(r.total)),
              key: const ValueKey('rep-exp-total'),
            ),
            if (r.count == 0)
              _Line(
                l.reportEmpty,
                key: const ValueKey('rep-empty'),
                muted: true,
              ),
          ],
        ),
        if (r.byCategory.isNotEmpty)
          _Block(
            title: l.reportByCategory,
            children: [
              for (final c in r.byCategory)
                _Line(
                  l.reportRowLine(c.name, _tm(c.total), c.count),
                  key: ValueKey('rep-cat-${c.name}'),
                ),
            ],
          ),
        if (r.byLocation.length > 1)
          _Block(
            title: l.reportByLocation,
            children: [
              for (final c in r.byLocation)
                _Line(
                  l.reportRowLine(c.name, _tm(c.total), c.count),
                  key: ValueKey('rep-loc-${c.name}'),
                ),
            ],
          ),
      ],
    );
  }
}
