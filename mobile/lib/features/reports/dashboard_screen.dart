import 'package:flutter/material.dart';

import '../../core/format/format_stamp.dart';
import '../../core/money/decimal_math.dart';
import '../../core/session/session_controller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_icons.dart';
import '../../widgets/common.dart';
import '../../l10n/app_localizations.dart';
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

  Widget _card(String key, String label, String value, {String? meta}) =>
      KeyedSubtree(
        key: ValueKey(key),
        child: Semantics(
          container: true,
          child: MetricCard(label: label, value: value, meta: meta),
        ),
      );

  /// Revenue of each of the last 14 days (days with no sale are zero), oldest first.
  List<int> _series() {
    final report = trend;
    if (report == null) return const [];
    final byDate = {for (final d in report.byDay) d.date: d.revenue};
    final today = DateTime.now();
    return [
      for (var back = 13; back >= 0; back--)
        byDate[reportDay(
              DateTime(today.year, today.month, today.day - back),
            )] ??
            0,
    ];
  }

  /// "+12% ко вчера", or null when there is nothing to compare with.
  String? _versusYesterday(AppLocalizations l, List<int> series) {
    if (series.length < 2) return null;
    final yesterday = series[series.length - 2];
    final today = dashboard.salesTodayTotal ?? series.last;
    if (yesterday <= 0) return null;
    final percent = ((today - yesterday) * 100 / yesterday).round();
    return l.dashVersusYesterday(percent > 0 ? '+$percent%' : '$percent%');
  }

  /// The one figure that gets the ink treatment, with the line of recent days beside it.
  Widget _spotlight(
    String key,
    String label,
    String value,
    String? note,
    List<int> series,
  ) {
    final showLine = !compact && series.where((v) => v > 0).length >= 2;
    return KeyedSubtree(
      key: ValueKey(key),
      child: Semantics(
        container: true,
        child: SpotlightCard(
          padding: compact ? 24 : 28,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: compact ? 164 : 172),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: const TextStyle(
                          color: AppColors.onInverseMuted,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        value,
                        style: TextStyle(
                          fontFamily: AppFonts.display,
                          fontWeight: FontWeight.w600,
                          fontSize: compact ? 34 : 52,
                          height: 1.1,
                          letterSpacing: compact ? -1.4 : -2.1,
                          color: AppColors.onInverse,
                          fontFeatures: AppFonts.tabular,
                        ),
                      ),
                      if (note != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          note,
                          style: const TextStyle(
                            color: AppColors.onInverseMuted,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (showLine) ...[
                  const SizedBox(width: 24),
                  SizedBox(
                    width: 260,
                    height: 100,
                    child: ExcludeSemantics(
                      child: CustomPaint(painter: _SparklinePainter(series)),
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

  AppIconData _activityIcon(String action) {
    if (action.startsWith('sale')) return AppIcons.check;
    if (action.startsWith('stock') || action.startsWith('transfer')) {
      return AppIcons.truck;
    }
    if (action.startsWith('warranty')) return AppIcons.shield;
    if (action.startsWith('product') || action.startsWith('catalog')) {
      return AppIcons.box;
    }
    if (action.startsWith('expense')) return AppIcons.receipt;
    return AppIcons.clock;
  }

  @override
  Widget build(BuildContext context) {
    final l = strings(context);
    final d = dashboard;
    final recent = d.recentActivity;
    final salesHero = d.salesTodayTotal != null;
    final inventoryHero = !salesHero && d.inventoryValue != null;
    final series = _series();
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
            'dash-sales-today',
            l.dashSalesToday(d.salesTodayCount ?? 0),
            _tm(d.salesTodayTotal!),
            _versusYesterday(l, series) ?? locationName,
            series,
          ),
          const SizedBox(height: 16),
        ] else if (inventoryHero) ...[
          _spotlight(
            'dash-inventory',
            l.dashInventoryValue,
            _tm(d.inventoryValue!),
            locationName,
            const [],
          ),
          const SizedBox(height: 16),
        ],
        AdaptiveGrid(
          children: [
            if (d.salesMonthTotal != null)
              _card(
                'dash-sales-month',
                l.dashSalesMonth(d.salesMonthCount ?? 0),
                _tm(d.salesMonthTotal!),
              ),
            if (d.grossProfitMonth != null)
              _card(
                'dash-profit-month',
                l.dashProfitMonth,
                _tm(d.grossProfitMonth!),
                meta: margin,
              ),
            if (d.expensesMonth != null)
              _card(
                'dash-expenses-month',
                l.dashExpensesMonth,
                _tm(d.expensesMonth!),
              ),
            if (salesHero && d.inventoryValue != null)
              _card(
                'dash-inventory',
                l.dashInventoryValue,
                _tm(d.inventoryValue!),
              ),
            if (d.lowStockCount != null)
              _card('dash-low-stock', l.dashLowStock, '${d.lowStockCount}'),
            if ((d.toCompleteCount ?? 0) > 0)
              KeyedSubtree(
                key: const ValueKey('dash-to-complete'),
                child: Semantics(
                  container: true,
                  button: true,
                  child: MetricCard(
                    label: l.dashToComplete,
                    value: '${d.toCompleteCount}',
                    featured: true,
                    onTap: onOpenToComplete,
                  ),
                ),
              ),
            if (d.openClaimsCount != null)
              _card(
                'dash-open-claims',
                l.dashOpenClaims,
                '${d.openClaimsCount}',
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
        if (recent != null && recent.isNotEmpty) ...[
          const SizedBox(height: 16),
          SurfaceCard(
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
                                fontSize: 16,
                                fontVariations: [FontVariation.weight(650)],
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
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                    ),
                                    textStyle: const TextStyle(
                                      fontSize: 13,
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
                              child: Glyph(_activityIcon(e.action)),
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
                                      fontSize: 14,
                                    ),
                                  ),
                                  const SizedBox(height: 5),
                                  Text(
                                    l.activityLine(
                                      e.actorName.isEmpty
                                          ? l.activitySystem
                                          : e.actorName,
                                      formatStamp(e.createdAt),
                                    ),
                                    style: const TextStyle(
                                      color: AppColors.muted,
                                      fontSize: 12,
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
        ],
      ],
    );
  }
}

/// The thin cobalt line of the last days, with a brass dot on the latest one.
class _SparklinePainter extends CustomPainter {
  _SparklinePainter(this.values);
  final List<int> values;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    final sx = size.width / 260;
    final sy = size.height / 100;
    final maxV = values.reduce((a, b) => a > b ? a : b);
    final minV = values.reduce((a, b) => a < b ? a : b);
    final span = (maxV - minV) == 0 ? 1 : (maxV - minV);
    Offset point(int i) => Offset(
      (4 + 252 * i / (values.length - 1)) * sx,
      (84 - 56 * (values[i] - minV) / span) * sy,
    );
    final path = Path()..moveTo(point(0).dx, point(0).dy);
    for (var i = 1; i < values.length; i++) {
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
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round
          ..color = AppColors.blue,
      )
      ..drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..strokeCap = StrokeCap.round
          ..color = Colors.white.withValues(alpha: 0.22),
      )
      ..drawCircle(
        point(values.length - 1),
        3.5,
        Paint()..color = AppColors.brass,
      );
  }

  @override
  bool shouldRepaint(_SparklinePainter old) => old.values != values;
}
