import 'package:flutter/material.dart';
import '../../widgets/app_icons.dart';

import '../../core/api/api_error_text.dart';
import '../../core/api/api_exception.dart';
import '../../core/files/file_services.dart';
import '../../core/money/decimal_math.dart';
import '../../core/session/session_controller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../inventory/stock_labels.dart';
import '../shared/async_section.dart';
import 'activity_view.dart';
import 'reports_models.dart';
import 'reports_repository.dart';

enum ReportTab { summary, sales, stock, returns, expenses, activity }

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
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) =>
        _page(context, constraints.maxWidth < 600),
  );

  Widget _page(BuildContext context, bool compact) {
    final l = strings(context);
    final places = session.membership?.locations ?? const [];
    final tab = _tabs.contains(_tab) ? _tab : ReportTab.summary;
    return ListView(
      padding: EdgeInsets.fromLTRB(
        compact ? 16 : 32,
        compact ? 20 : 32,
        compact ? 16 : 32,
        40,
      ),
      children: [
        PageHead(
          title: l.reports,
          subtitle: [
            if (places.length > 1)
              places
                      .where((p) => p.id == _locationId)
                      .map((p) => p.name)
                      .firstOrNull ??
                  l.reportAllLocations
            else
              ?session.location?.name,
            _periodLabel(_period),
          ].join(' · '),
          actions: [
            if (_exportSlug(tab) != null)
              OutlinedButton.icon(
                key: const ValueKey('report-export'),
                onPressed: _exporting ? null : () => _export(_exportSlug(tab)!),
                icon: const AppIcon(AppIcons.download, size: 20),
                label: Text(l.reportExport),
              ),
          ],
        ),
        const SizedBox(height: 24),
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
                constraints: const BoxConstraints(maxWidth: 220),
                child: FilterSelect<String?>(
                  fieldKey: const ValueKey('reports-location'),
                  leading: AppIcons.stock,
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
        AppTabs<ReportTab>(
          keyPrefix: 'reports-tab',
          keyName: (t) => t.name,
          tabs: [for (final t in _tabs) (t, _tabLabel(t))],
          value: tab,
          onChanged: (t) => setState(() => _tab = t),
        ),
        const SizedBox(height: 24),
        // A new key for every tab and filter: the section loads again from scratch.
        KeyedSubtree(
          key: ValueKey('${tab.name}|${_query.hashCode}'),
          child: _content(tab),
        ),
      ],
    );
  }

  /// The CSV export a tab offers, if any.
  String? _exportSlug(ReportTab tab) => switch (tab) {
    ReportTab.sales => 'sales',
    ReportTab.stock => 'stock',
    ReportTab.returns => 'returns',
    ReportTab.expenses => 'expenses',
    _ => null,
  };

  Widget _content(ReportTab tab) {
    final q = _query;
    final repo = widget.repository;
    return switch (tab) {
      ReportTab.summary => AsyncSection<ReportSummary>(
        load: () => repo.summary(q),
        builder: (context, s) => _SummaryView(
          summary: s,
          sales: widget.session.can('report.view') ? () => repo.sales(q) : null,
        ),
      ),
      ReportTab.sales => AsyncSection<SalesReport>(
        load: () => repo.sales(q),
        builder: (context, r) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [_SalesView(report: r)],
        ),
      ),
      ReportTab.stock => AsyncSection<StockReport>(
        load: () => repo.stock(q),
        builder: (context, r) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [_StockView(report: r)],
        ),
      ),
      ReportTab.returns => AsyncSection<ReturnsReport>(
        load: () => repo.returns(q),
        builder: (context, r) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [_ReturnsView(report: r)],
        ),
      ),
      ReportTab.expenses => AsyncSection<ExpensesReport>(
        load: () => repo.expenses(q),
        builder: (context, r) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [_ExpensesView(report: r)],
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

Widget _metric(String key, String label, String value) => KeyedSubtree(
  key: ValueKey(key),
  child: Semantics(
    container: true,
    child: MetricCard(label: label, value: value),
  ),
);

class _SummaryView extends StatefulWidget {
  const _SummaryView({required this.summary, this.sales});
  final ReportSummary summary;

  /// Loads the sales report of the same period for the charts (null: no chart).
  final Future<SalesReport> Function()? sales;

  @override
  State<_SummaryView> createState() => _SummaryViewState();
}

class _SummaryViewState extends State<_SummaryView> {
  late final Future<SalesReport?>? _sales = widget.sales == null
      ? null
      : widget.sales!().then<SalesReport?>((r) => r).catchError((_) => null);

  @override
  Widget build(BuildContext context) {
    final l = strings(context);
    final s = widget.summary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AdaptiveGrid(
          minimumWidth: 150,
          maxColumns: 7,
          gap: 12,
          children: [
            _metric('rep-revenue', l.reportRevenue, _tm(s.revenue)),
            _metric('rep-refunds', l.reportRefunds, _tm(s.refunds)),
            _metric('rep-net', l.reportNetSales, _tm(s.netSales)),
            if (s.costOfGoods != null)
              _metric('rep-cost', l.reportCostOfGoods, _tm(s.costOfGoods!)),
            if (s.grossProfit != null)
              _metric('rep-profit', l.reportGrossProfit, _tm(s.grossProfit!)),
            if (s.expenses != null)
              _metric('rep-expenses', l.reportExpenses, _tm(s.expenses!)),
            if (s.result != null)
              _metric('rep-result', l.reportResult, _tm(s.result!)),
            if (s.inventoryValue != null)
              _metric(
                'rep-inventory',
                l.reportInventoryValue,
                _tm(s.inventoryValue!),
              ),
            _metric('rep-low-stock', l.reportLowStock, '${s.lowStockCount}'),
          ],
        ),
        if (_sales != null)
          FutureBuilder<SalesReport?>(
            future: _sales,
            builder: (context, snapshot) {
              final report = snapshot.data;
              if (report == null) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(top: 16),
                child: _Charts(report: report),
              );
            },
          ),
        const SizedBox(height: 12),
        _Line(
          '${l.reportSalesCount(s.salesCount)} · ${l.reportReturnsCount(s.returnsCount)}',
          key: const ValueKey('rep-counts'),
          muted: true,
        ),
        if (s.withoutCostLines > 0)
          _Line(
            l.reportWithoutCostNote(
              _tm(s.withoutCost ?? 0),
              s.withoutCostLines,
            ),
            key: const ValueKey('rep-without-cost-note'),
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

/// The two cards under the figures of the summary: revenue by day as a line, and the best
/// selling products as bars. Both are drawn from the sales report of the same period.
class _Charts extends StatelessWidget {
  const _Charts({required this.report});
  final SalesReport report;

  @override
  Widget build(BuildContext context) {
    final line = report.byDay.length > 1
        ? _RevenueChart(days: report.byDay)
        : null;
    final bars = report.topProducts.isNotEmpty
        ? _TopBars(products: report.topProducts)
        : null;
    if (line == null && bars == null) {
      return const SizedBox.shrink();
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 700) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ?line,
              if (line != null && bars != null) const SizedBox(height: 16),
              ?bars,
            ],
          );
        }
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (line != null) Expanded(flex: 3, child: line),
              if (line != null && bars != null) const SizedBox(width: 16),
              if (bars != null) Expanded(flex: 2, child: bars),
              if (line == null && bars != null) const Spacer(flex: 3),
            ],
          ),
        );
      },
    );
  }
}

/// Best sellers of the period as thin cobalt bars; the highest one is ink.
class _TopBars extends StatelessWidget {
  const _TopBars({required this.products});
  final List<TopProduct> products;

  @override
  Widget build(BuildContext context) {
    final l = strings(context);
    final shown = products.take(6).toList();
    final top = shown.map((p) => p.revenue).reduce((a, b) => a > b ? a : b);
    final topIndex = shown.indexWhere((p) => p.revenue == top);
    return SurfaceCard(
      key: const ValueKey('rep-top-bars'),
      padding: 20,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Eyebrow(l.products),
          const SizedBox(height: 8),
          Text(
            l.reportTopProducts,
            style: const TextStyle(
              fontSize: 16,
              fontVariations: [FontVariation.weight(650)],
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 190,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < shown.length; i++)
                  Expanded(
                    child: Tooltip(
                      message: '${shown[i].name}: ${_tm(shown[i].revenue)}',
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Container(
                            width: 30,
                            height: top <= 0
                                ? 4
                                : (4 + 138 * shown[i].revenue / top),
                            decoration: BoxDecoration(
                              color: i == topIndex
                                  ? AppColors.ink
                                  : AppColors.blue,
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(4),
                                bottom: Radius.circular(1),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            shown[i].name.split(' ').first,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.muted,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
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
        if (r.withoutCostLines > 0)
          _Line(
            l.reportWithoutCostNote(
              _tm(r.withoutCost ?? 0),
              r.withoutCostLines,
            ),
            key: const ValueKey('rep-sales-without-cost-note'),
            muted: true,
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
        if (r.byDay.length > 1)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: _RevenueChart(days: r.byDay),
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

/// Revenue by day as one thin cobalt line with a point per day, the highest value labelled and
/// the first and last dates under the axis. Drawn from the report's own rows.
class _RevenueChart extends StatelessWidget {
  const _RevenueChart({required this.days});
  final List<DayRow> days;

  @override
  Widget build(BuildContext context) {
    final l = strings(context);
    final top = days.map((d) => d.revenue).reduce((a, b) => a > b ? a : b);
    return Semantics(
      container: true,
      label: '${l.reportByDay}: ${days.first.date} - ${days.last.date}',
      child: SurfaceCard(
        key: const ValueKey('rep-chart'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Eyebrow(l.reportTabSales),
            const SizedBox(height: 8),
            Text(l.reportByDay, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            SizedBox(
              height: 190,
              child: ExcludeSemantics(
                child: CustomPaint(
                  size: Size.infinite,
                  painter: _LinePainter(
                    values: [for (final d in days) d.revenue],
                    first: days.first.date,
                    last: days.last.date,
                    topLabel: _tm(top),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LinePainter extends CustomPainter {
  _LinePainter({
    required this.values,
    required this.first,
    required this.last,
    required this.topLabel,
  });
  final List<int> values;
  final String first;
  final String last;
  final String topLabel;

  void _label(
    Canvas canvas,
    String text,
    Offset at, {
    TextAlign align = TextAlign.left,
    FontWeight weight = FontWeight.w500,
    Color color = AppColors.muted,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: AppFonts.ui,
          fontSize: 11,
          fontWeight: weight,
          color: color,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final x = switch (align) {
      TextAlign.right => at.dx - painter.width,
      TextAlign.center => at.dx - painter.width / 2,
      _ => at.dx,
    };
    painter.paint(canvas, Offset(x, at.dy));
  }

  @override
  void paint(Canvas canvas, Size size) {
    const labelBand = 22.0;
    const topPad = 20.0;
    final plot = Rect.fromLTRB(
      8,
      topPad,
      size.width - 8,
      size.height - labelBand,
    );
    final maxV = values.reduce((a, b) => a > b ? a : b);
    final minV = values.reduce((a, b) => a < b ? a : b);
    final span = (maxV - minV) == 0 ? 1 : (maxV - minV);
    Offset point(int i) => Offset(
      plot.left + plot.width * i / (values.length - 1),
      plot.bottom - plot.height * (values[i] - minV) / span,
    );
    final path = Path()..moveTo(point(0).dx, point(0).dy);
    for (var i = 1; i < values.length; i++) {
      // A gentle curve between points: no sharp corners, no invented values beyond the rows.
      final a = point(i - 1);
      final b = point(i);
      final mid = (a.dx + b.dx) / 2;
      path.cubicTo(mid, a.dy, mid, b.dy, b.dx, b.dy);
    }
    canvas
      ..drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 12
          ..strokeCap = StrokeCap.round
          ..color = AppColors.blue.withValues(alpha: 0.1),
      )
      ..drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round
          ..color = AppColors.blue,
      );
    for (var i = 0; i < values.length; i++) {
      canvas
        ..drawCircle(point(i), 4, Paint()..color = Colors.white)
        ..drawCircle(
          point(i),
          4,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = AppColors.blue,
        );
    }
    _label(
      canvas,
      topLabel,
      Offset(size.width, 0),
      align: TextAlign.right,
      weight: FontWeight.w600,
      color: AppColors.ink,
    );
    _label(canvas, first, Offset(plot.left, size.height - 14));
    _label(
      canvas,
      last,
      Offset(plot.right, size.height - 14),
      align: TextAlign.right,
    );
  }

  @override
  bool shouldRepaint(_LinePainter old) =>
      old.values != values ||
      old.first != first ||
      old.last != last ||
      old.topLabel != topLabel;
}
