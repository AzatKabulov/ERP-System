import 'package:flutter/material.dart';

import '../../core/format/format_stamp.dart';
import '../../core/money/decimal_math.dart';
import '../../core/session/session_controller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../admin/administration_screen.dart';
import '../shared/async_section.dart';
import 'audit_labels.dart';
import 'reports_models.dart';
import 'reports_repository.dart';

String _tm(int minor) => formatMoney(minor, 'TMT');

/// The first page after sign-in: a greeting and today's figures. The server sends only the
/// sections the person's role may see (a keeper gets no sales or costs), so a missing figure
/// simply has no card.
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({
    super.key,
    required this.session,
    required this.repository,
    this.onOpenReports,
  });

  final SessionController session;
  final ReportsRepository repository;

  /// Shown as a button for people who may open the reports page.
  final VoidCallback? onOpenReports;

  @override
  Widget build(BuildContext context) {
    final l = strings(context);
    final user = session.user;
    final membership = session.membership;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          l.welcomeUser(user?.displayName ?? ''),
          key: const ValueKey('welcome'),
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 16),
        if (membership != null)
          SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  membership.businessName,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(roleLabel(l, membership.role)),
                if (session.location != null) Text(session.location!.name),
              ],
            ),
          ),
        const SizedBox(height: 16),
        if (session.can('dashboard.view'))
          AsyncSection<Dashboard>(
            load: repository.dashboard,
            builder: (context, d) => _Figures(
              dashboard: d,
              onOpenReports: session.can('report.view') ? onOpenReports : null,
            ),
          ),
      ],
    );
  }
}

class _Figures extends StatelessWidget {
  const _Figures({required this.dashboard, this.onOpenReports});
  final Dashboard dashboard;
  final VoidCallback? onOpenReports;

  Widget _card(String key, String label, String value, IconData icon) =>
      KeyedSubtree(
        key: ValueKey(key),
        child: Semantics(
          container: true,
          child: MetricCard(label: label, value: value, icon: icon),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final l = strings(context);
    final d = dashboard;
    final recent = d.recentActivity;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!d.hasAnything)
          Text(
            l.dashNothing,
            key: const ValueKey('dash-nothing'),
            style: const TextStyle(color: AppColors.muted),
          ),
        AdaptiveGrid(
          children: [
            if (d.salesTodayTotal != null)
              _card(
                'dash-sales-today',
                l.dashSalesToday(d.salesTodayCount ?? 0),
                _tm(d.salesTodayTotal!),
                Icons.shopping_bag_outlined,
              ),
            if (d.salesMonthTotal != null)
              _card(
                'dash-sales-month',
                l.dashSalesMonth(d.salesMonthCount ?? 0),
                _tm(d.salesMonthTotal!),
                Icons.calendar_month_outlined,
              ),
            if (d.grossProfitMonth != null)
              _card(
                'dash-profit-month',
                l.dashProfitMonth,
                _tm(d.grossProfitMonth!),
                Icons.savings_outlined,
              ),
            if (d.expensesMonth != null)
              _card(
                'dash-expenses-month',
                l.dashExpensesMonth,
                _tm(d.expensesMonth!),
                Icons.account_balance_wallet_outlined,
              ),
            if (d.inventoryValue != null)
              _card(
                'dash-inventory',
                l.dashInventoryValue,
                _tm(d.inventoryValue!),
                Icons.warehouse_outlined,
              ),
            if (d.lowStockCount != null)
              _card(
                'dash-low-stock',
                l.dashLowStock,
                '${d.lowStockCount}',
                Icons.warning_amber_outlined,
              ),
            if (d.reorderCount != null)
              _card(
                'dash-reorder',
                l.dashReorder,
                '${d.reorderCount}',
                Icons.shopping_cart_outlined,
              ),
            if (d.openOrdersCount != null)
              _card(
                'dash-open-orders',
                l.dashOpenOrders,
                '${d.openOrdersCount}',
                Icons.local_shipping_outlined,
              ),
            if (d.openClaimsCount != null)
              _card(
                'dash-open-claims',
                l.dashOpenClaims,
                '${d.openClaimsCount}',
                Icons.verified_user_outlined,
              ),
          ],
        ),
        if (onOpenReports != null) ...[
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              key: const ValueKey('dash-open-reports'),
              onPressed: onOpenReports,
              icon: const Icon(Icons.bar_chart_outlined),
              label: Text(l.dashOpenReports),
            ),
          ),
        ],
        if (recent != null && recent.isNotEmpty) ...[
          const SizedBox(height: 20),
          SectionHeading(l.dashRecent),
          const SizedBox(height: 8),
          SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final e in recent)
                  Semantics(
                    container: true,
                    child: Padding(
                      key: ValueKey('dash-activity-${e.id}'),
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(auditActionLabel(l, e.action)),
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
      ],
    );
  }
}
