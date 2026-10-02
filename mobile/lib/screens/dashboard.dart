import 'package:flutter/material.dart';

import '../demo/demo_store.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import 'workspace.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({
    super.key,
    required this.store,
    required this.onNavigate,
  });
  final DemoStore store;
  final ValueChanged<AppPage> onNavigate;

  @override
  Widget build(BuildContext context) {
    final l = strings(context);
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          l.session,
          style: const TextStyle(
            fontSize: 13,
            color: AppColors.blue,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 12),
        Text(l.welcome, style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 10),
        Text(
          l.welcomeSubtitle,
          style: const TextStyle(
            color: AppColors.muted,
            fontSize: 16,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 24),
        AdaptiveGrid(
          children: [
            MetricCard(
              label: l.salesTotal,
              value: money(store.salesTotal),
              icon: Icons.shopping_bag_outlined,
            ),
            MetricCard(
              label: l.stockValue,
              value: money(store.inventoryValue),
              icon: Icons.inventory_2_outlined,
            ),
            MetricCard(
              label: l.stockUnits,
              value: '${store.unitCount}',
              icon: Icons.layers_outlined,
            ),
            MetricCard(
              label: l.lowStock,
              value: '${store.lowStock.length}',
              icon: Icons.warning_amber_outlined,
            ),
          ],
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: AppColors.ink,
            borderRadius: BorderRadius.circular(16),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) => Wrap(
              spacing: 32,
              runSpacing: 20,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: constraints.maxWidth > 700
                      ? constraints.maxWidth - 270
                      : constraints.maxWidth,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l.stockHealth,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        l.stockHealthSubtitle,
                        style: const TextStyle(
                          color: Color(0xFFCBD5E1),
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
                GradientButton(
                  label: l.viewInventory,
                  icon: Icons.arrow_forward,
                  onPressed: () => onNavigate(AppPage.inventory),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        SectionHeading(l.quickActions),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            GradientButton(
              label: l.newSale,
              icon: Icons.add,
              onPressed: () => onNavigate(AppPage.sales),
            ),
            OutlinedButton.icon(
              onPressed: () => onNavigate(AppPage.purchasing),
              icon: const Icon(Icons.local_shipping_outlined),
              label: Text(l.receiveGoods),
            ),
            OutlinedButton.icon(
              onPressed: () => onNavigate(AppPage.expenses),
              icon: const Icon(Icons.account_balance_wallet_outlined),
              label: Text(l.newExpense),
            ),
          ],
        ),
        const SizedBox(height: 28),
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionHeading(
                l.lowStockSubtitle,
                action: TextButton(
                  onPressed: () => onNavigate(AppPage.inventory),
                  child: Text(l.allProducts),
                ),
              ),
              const SizedBox(height: 12),
              if (store.lowStock.isEmpty)
                EmptyState(title: l.healthy, icon: Icons.check_circle_outline),
              for (final p in store.lowStock)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(
                    children: [
                      ProductMark(product: p),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              p.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${p.sku} · ${p.brand}',
                              style: const TextStyle(
                                color: AppColors.muted,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        '${store.stock(p)} / ${p.minimum}',
                        style: const TextStyle(
                          color: AppColors.warning,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        ActivityPanel(store: store),
        const SizedBox(height: 24),
      ],
    );
  }
}

class ActivityPanel extends StatelessWidget {
  const ActivityPanel({super.key, required this.store});
  final DemoStore store;

  @override
  Widget build(BuildContext context) {
    final l = strings(context);
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeading(l.recentActivity),
          const SizedBox(height: 12),
          if (store.activities.isEmpty)
            EmptyState(title: l.noActivity, icon: Icons.history),
          for (final activity in store.activities.take(12))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(switch (activity.kind) {
                    ActivityKind.sale => l.activitySale,
                    ActivityKind.receipt => l.activityReceipt,
                    ActivityKind.transfer => l.activityTransfer,
                    ActivityKind.count => l.activityCount,
                    ActivityKind.expense => l.activityExpense,
                    ActivityKind.refund => l.activityRefund,
                  }),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 16,
                    runSpacing: 8,
                    children: [
                      Text(
                        activity.reference,
                        style: const TextStyle(color: AppColors.muted),
                      ),
                      Text(
                        activity.amountMinor > 0
                            ? money(activity.amountMinor)
                            : '${activity.quantity}',
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
