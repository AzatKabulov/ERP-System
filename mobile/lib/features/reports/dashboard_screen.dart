import 'package:flutter/material.dart';

import '../../core/format/format_stamp.dart';
import '../../core/money/decimal_math.dart';
import '../../core/session/session_controller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_icons.dart';
import '../../widgets/charts.dart';
import '../../widgets/common.dart';
import '../../widgets/motion.dart';
import '../shared/async_section.dart';
import 'audit_labels.dart';
import 'reports_models.dart';
import 'reports_repository.dart';

String _tm(int minor) => formatMoney(minor, 'TMT');

/// The first page after sign-in: a greeting and today's figures. The server sends only the
/// sections the person's role may see (a keeper gets no sales or costs), so a missing figure
/// simply has no card.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({
    super.key,
    required this.session,
    required this.repository,
    this.onOpenReports,
    this.onOpenToComplete,
  });

  final SessionController session;
  final ReportsRepository repository;

  /// Shown as the link of the recent-activity card for people who may open the reports page.
  final VoidCallback? onOpenReports;

  /// Opens the list of products that still need a price or a cost.
  final VoidCallback? onOpenToComplete;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  /// The last two weeks of sales, for the line and the comparison with yesterday. Quiet: a
  /// failure just leaves the line out.
  late final Future<SalesReport?> _trend = _loadTrend();

  Future<SalesReport?> _loadTrend() async {
    if (!widget.session.can('report.view') ||
        !widget.session.can('dashboard.view')) {
      return null;
    }
    final today = DateTime.now();
    try {
      return await widget.repository.sales(
        ReportQuery(
          from: reportDay(DateTime(today.year, today.month, today.day - 13)),
          to: reportDay(today),
          locationId: widget.session.location?.id,
        ),
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 600;
        final l = strings(context);
        final name = session.user?.displayName ?? '';
        final membership = session.membership;
        final place = [
          ?membership?.businessName,
          ?session.location?.name,
        ].join(' · ');
        return ListView(
          padding: EdgeInsets.fromLTRB(
            compact ? 16 : 32,
            compact ? 20 : 32,
            compact ? 16 : 32,
            40,
          ),
          children: [
            FadeUp(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  PageHead(
                    title: l.welcomeUser(name),
                    titleKey: const ValueKey('welcome'),
                    subtitle: place.isEmpty ? null : place,
                  ),
                  if (session.can('dashboard.view'))
                    AsyncSection<Dashboard>(
                      load: widget.repository.dashboard,
                      builder: (context, d) => FutureBuilder<SalesReport?>(
                        future: _trend,
                        builder: (context, trend) => _Figures(
                          dashboard: d,
                          trend: trend.data,
                          compact: compact,
                          locationName: session.location?.name,
                          onOpenReports: session.can('report.view')
                              ? widget.onOpenReports
                              : null,
                          onOpenToComplete: widget.onOpenToComplete,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Figures extends StatelessWidget {
  const _Figures({
    required this.dashboard,
    required this.trend,
    required this.compact,
    this.locationName,
    this.onOpenReports,
    this.onOpenToComplete,
  });
  final Dashboard dashboard;
  final SalesReport? trend;
  final bool compact;
  final String? locationName;
  final VoidCallback? onOpenReports;
  final VoidCallback? onOpenToComplete;

  /// A figure with its coloured icon. The colour is the kind of figure: blue sales, violet profit
  /// and claims, emerald stock, amber attention, rose money out.
  Widget _card(
    String key,
    String label,
    String value, {
    String? meta,
    required AppIconData icon,
    required Color accent,
    required Color tint,
    int index = 0,
  }) => KeyedSubtree(
    key: ValueKey(key),
    child: Semantics(
      container: true,
      child: FadeUp(
        index: index,
        child: MetricCard(
          label: label,
          value: value,
          meta: meta,
          icon: icon,
          accent: accent,
          accentTint: tint,
        ),
      ),
    ),
  );

  /// The last 14 days, oldest first: the date and the revenue of each (a day with no sale is zero).
  List<(DateTime, int)> _days() {
    final report = trend;
    if (report == null) return const [];
    final byDate = {for (final d in report.byDay) d.date: d.revenue};
    final today = DateTime.now();
    return [
      for (var back = 13; back >= 0; back--)
        () {
          final day = DateTime(today.year, today.month, today.day - back);
          return (day, byDate[reportDay(day)] ?? 0);
        }(),
    ];
  }

  static String _dayLabel(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}';

  /// Today against yesterday in whole percent, or null when there is nothing to compare with.
  int? _percentVersusYesterday(List<int> series) {
    if (series.length < 2) return null;
    final yesterday = series[series.length - 2];
    final today = dashboard.salesTodayTotal ?? series.last;
    if (yesterday <= 0) return null;
    return ((today - yesterday) * 100 / yesterday).round();
  }

  /// The one figure that gets the deep treatment: the amount counting up, today against
  /// yesterday, and the line of the last two weeks, which names a day when touched.
  Widget _spotlight(
    BuildContext context,
    String key,
    String label,
    int total,
    String? note,
    List<(DateTime, int)> days,
    int? percent,
  ) {
    final l = strings(context);
    final series = [for (final d in days) d.$2];
    final showLine = series.where((v) => v > 0).length >= 2;
    final up = (percent ?? 0) >= 0;
    final figure = Column(
      mainAxisAlignment: MainAxisAlignment.end,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppColors.onInverseMuted,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 10),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: CountUp(
            value: total,
            format: (n) => _tm(n.round()),
            style: TextStyle(
              fontFamily: AppFonts.display,
              fontWeight: FontWeight.w700,
              fontSize: compact ? 36 : 50,
              height: 1.1,
              letterSpacing: compact ? -1.1 : -1.6,
              color: AppColors.onInverse,
              fontFeatures: AppFonts.tabular,
            ),
          ),
        ),
        if (percent != null) ...[
          const SizedBox(height: 14),
          DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 5, 12, 5),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppIcon(
                    up ? AppIcons.trendUp : AppIcons.trendDown,
                    size: 16,
                    color: up
                        ? const Color(0xFF7CF0B5)
                        : const Color(0xFFFFA3A8),
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      l.dashVersusYesterday(
                        percent > 0 ? '+$percent%' : '$percent%',
                      ),
                      style: TextStyle(
                        color: up
                            ? const Color(0xFF7CF0B5)
                            : const Color(0xFFFFA3A8),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ] else if (note != null) ...[
          const SizedBox(height: 12),
          Text(
            note,
            style: const TextStyle(
              color: AppColors.onInverseMuted,
              fontSize: 14,
            ),
          ),
        ],
      ],
    );
    final chart = showLine
        ? Semantics(
            label: '${l.dashLast14}: ${_tm(series.fold(0, (a, b) => a + b))}',
            child: AreaChart(
              onDark: true,
              height: compact ? 96 : 132,
              values: series,
              labelFor: (i) => _dayLabel(days[i].$1),
              valueText: (i) => _tm(series[i]),
            ),
          )
        : null;
    return KeyedSubtree(
      key: ValueKey(key),
      child: Semantics(
        container: true,
        child: FadeUp(
          child: SpotlightCard(
            padding: compact ? 22 : 30,
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: compact ? 164 : 172),
              child: compact || chart == null
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        figure,
                        if (chart != null) ...[
                          const SizedBox(height: 20),
                          chart,
                        ],
                      ],
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(flex: 5, child: figure),
                        const SizedBox(width: 32),
                        Expanded(
                          flex: 6,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Align(
                                alignment: Alignment.centerRight,
                                child: Text(
                                  l.dashLast14,
                                  style: const TextStyle(
                                    color: AppColors.onInverseMuted,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 6),
                              chart,
                            ],
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }

  (AppIconData, Color, Color) _activityLook(String action) {
    if (action.startsWith('sale')) {
      return (AppIcons.check, AppColors.success, AppColors.emeraldTint);
    }
    if (action.startsWith('stock') || action.startsWith('transfer')) {
      return (AppIcons.truck, AppColors.blue, AppColors.tint);
    }
    if (action.startsWith('warranty')) {
      return (AppIcons.shield, AppColors.violetText, AppColors.violetTint);
    }
    if (action.startsWith('product') || action.startsWith('catalog')) {
      return (AppIcons.box, AppColors.warning, AppColors.amberTint);
    }
    if (action.startsWith('expense')) {
      return (AppIcons.receipt, AppColors.danger, AppColors.roseTint);
    }
    return (AppIcons.clock, AppColors.neutral, AppColors.surfaceMuted);
  }

  /// The best sellers of the two weeks as bars, and how they were paid for as a ring.
  Widget _charts(BuildContext context, SalesReport report) {
    final l = strings(context);
    final tops = report.topProducts.take(5).toList();
    final pay = report.byPayment.where((p) => p.total > 0).toList();
    final paid = pay.fold<int>(0, (a, p) => a + p.total);
    if (tops.isEmpty && pay.isEmpty) return const SizedBox.shrink();
    Widget cardOf(String key, String title, Widget child) => KeyedSubtree(
      key: ValueKey(key),
      child: SurfaceCard(
        padding: 22,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 20),
            child,
          ],
        ),
      ),
    );
    final best = tops.isEmpty
        ? null
        : cardOf(
            'dash-top-products',
            l.reportTopProducts,
            BarList(
              items: [
                for (final t in tops)
                  BarItem(
                    label: t.name,
                    value: t.revenue,
                    text: _tm(t.revenue),
                  ),
              ],
            ),
          );
    final colors = [AppColors.blue, AppColors.violet];
    final ring = pay.isEmpty
        ? null
        : cardOf(
            'dash-payments',
            l.reportByPayment,
            Column(
              children: [
                Center(
                  child: DonutChart(
                    slices: [
                      for (var i = 0; i < pay.length; i++)
                        DonutSlice(pay[i].total, colors[i % colors.length]),
                    ],
                    center: FittedBox(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${pay.fold<int>(0, (a, p) => a + p.count)}',
                            style: const TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w700,
                              height: 1.1,
                            ),
                          ),
                          Text(
                            l.sales,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                for (var i = 0; i < pay.length; i++)
                  Padding(
                    padding: EdgeInsets.only(top: i == 0 ? 0 : 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 5),
                          child: Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: colors[i % colors.length],
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Wrap(
                            alignment: WrapAlignment.spaceBetween,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 12,
                            runSpacing: 2,
                            children: [
                              Text(
                                pay[i].method == 'cash' ? l.payCash : l.payCard,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                '${l.dashShareOfSales(paid == 0 ? 0 : (pay[i].total * 100 / paid).round())} · ${_tm(pay[i].total)}',
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: AppColors.muted,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          );
    return FadeUp(
      index: 3,
      child: LayoutBuilder(
        builder: (context, box) {
          if (best != null && ring != null && box.maxWidth >= 760) {
            return IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(flex: 3, child: best),
                  const SizedBox(width: 16),
                  Expanded(flex: 2, child: ring),
                ],
              ),
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ?best,
              if (best != null && ring != null) const SizedBox(height: 16),
              ?ring,
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = strings(context);
    final d = dashboard;
    final recent = d.recentActivity;
    final salesHero = d.salesTodayTotal != null;
    final inventoryHero = !salesHero && d.inventoryValue != null;
    final days = _days();
    final series = [for (final day in days) day.$2];
    final margin = d.grossProfitMonth != null && (d.salesMonthTotal ?? 0) > 0
        ? '${(d.grossProfitMonth! * 1000 / d.salesMonthTotal!).round() / 10}%'
              .replaceAll('.', ',')
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 24),
        if (!d.hasAnything)
          Text(
            l.dashNothing,
            key: const ValueKey('dash-nothing'),
            style: const TextStyle(color: AppColors.muted),
          ),
        if (salesHero) ...[
          _spotlight(
            context,
            'dash-sales-today',
            l.dashSalesToday(d.salesTodayCount ?? 0),
            d.salesTodayTotal!,
            locationName,
            days,
            _percentVersusYesterday(series),
          ),
          const SizedBox(height: 16),
        ] else if (inventoryHero) ...[
          _spotlight(
            context,
            'dash-inventory',
            l.dashInventoryValue,
            d.inventoryValue!,
            locationName,
            const [],
            null,
          ),
          const SizedBox(height: 16),
        ],
        AdaptiveGrid(
          minimumWidth: compact ? 150 : 220,
          children: [
            if (d.salesMonthTotal != null)
              _card(
                'dash-sales-month',
                l.dashSalesMonth(d.salesMonthCount ?? 0),
                _tm(d.salesMonthTotal!),
                icon: AppIcons.sale,
                accent: AppColors.blue,
                tint: AppColors.tint,
                index: 1,
              ),
            if (d.grossProfitMonth != null)
              _card(
                'dash-profit-month',
                l.dashProfitMonth,
                _tm(d.grossProfitMonth!),
                meta: margin,
                icon: AppIcons.trendUp,
                accent: AppColors.violet,
                tint: AppColors.violetTint,
                index: 2,
              ),
            if (d.expensesMonth != null)
              _card(
                'dash-expenses-month',
                l.dashExpensesMonth,
                _tm(d.expensesMonth!),
                icon: AppIcons.expense,
                accent: AppColors.rose,
                tint: AppColors.roseTint,
                index: 3,
              ),
            if (salesHero && d.inventoryValue != null)
              _card(
                'dash-inventory',
                l.dashInventoryValue,
                _tm(d.inventoryValue!),
                icon: AppIcons.stock,
                accent: AppColors.emerald,
                tint: AppColors.emeraldTint,
                index: 4,
              ),
            if (d.lowStockCount != null)
              _card(
                'dash-low-stock',
                l.dashLowStock,
                '${d.lowStockCount}',
                icon: AppIcons.warning,
                accent: AppColors.amber,
                tint: AppColors.amberTint,
                index: 5,
              ),
            if ((d.toCompleteCount ?? 0) > 0)
              KeyedSubtree(
                key: const ValueKey('dash-to-complete'),
                child: Semantics(
                  container: true,
                  button: true,
                  child: FadeUp(
                    index: 6,
                    child: MetricCard(
                      label: l.dashToComplete,
                      value: '${d.toCompleteCount}',
                      featured: true,
                      icon: AppIcons.checklist,
                      onTap: onOpenToComplete,
                    ),
                  ),
                ),
              ),
            if (d.openClaimsCount != null)
              _card(
                'dash-open-claims',
                l.dashOpenClaims,
                '${d.openClaimsCount}',
                icon: AppIcons.shield,
                accent: AppColors.violet,
                tint: AppColors.violetTint,
                index: 7,
              ),
          ],
        ),
        if ((d.withoutCostMonth ?? 0) != 0) ...[
          const SizedBox(height: 16),
          NoticeBanner(
            key: const ValueKey('dash-without-cost-note'),
            text: l.dashWithoutCostNote(_tm(d.withoutCostMonth!)),
          ),
        ],
        if (trend != null) ...[
          const SizedBox(height: 16),
          _charts(context, trend!),
        ],
        if (recent != null && recent.isNotEmpty) ...[
          const SizedBox(height: 16),
          FadeUp(
            index: 4,
            child: SurfaceCard(
              padding: 0,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 56),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: Text(
                                l.dashRecent,
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            if (onOpenReports != null)
                              Flexible(
                                flex: 2,
                                child: Align(
                                  alignment: Alignment.centerRight,
                                  child: TextButton(
                                    key: const ValueKey('dash-open-reports'),
                                    style: TextButton.styleFrom(
                                      minimumSize: const Size(48, 40),
                                      foregroundColor: AppColors.blue,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                      ),
                                      textStyle: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    onPressed: onOpenReports,
                                    child: Text(l.dashOpenReports),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    for (final e in recent)
                      Semantics(
                        container: true,
                        child: Container(
                          key: ValueKey('dash-activity-${e.id}'),
                          constraints: const BoxConstraints(minHeight: 68),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 10,
                          ),
                          decoration: const BoxDecoration(
                            border: Border(
                              top: BorderSide(color: AppColors.line),
                            ),
                          ),
                          child: Row(
                            children: [
                              ExcludeSemantics(
                                child: () {
                                  final (icon, strong, tint) = _activityLook(
                                    e.action,
                                  );
                                  return Glyph(
                                    icon,
                                    background: tint,
                                    color: strong,
                                  );
                                }(),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      auditActionLabel(l, e.action),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 15,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      l.activityLine(
                                        e.actorName.isEmpty
                                            ? l.activitySystem
                                            : e.actorName,
                                        formatStamp(e.createdAt),
                                      ),
                                      style: const TextStyle(
                                        color: AppColors.muted,
                                        fontSize: 13,
                                        height: 1.4,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
