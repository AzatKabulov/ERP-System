import 'package:flutter/material.dart';

import '../../core/format/format_stamp.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_icons.dart';
import '../../widgets/common.dart';
import '../../widgets/charts.dart';
import '../../widgets/glass.dart';
import '../shared/async_section.dart';
import '../shared/loading_skeletons.dart';
import 'platform_models.dart';
import 'platform_repository.dart';
import 'platform_widgets.dart';

/// The platform owner's first page: how many clients are in each state, the money this month,
/// who needs a call, and the latest payments.
class PlatformOverviewScreen extends StatelessWidget {
  const PlatformOverviewScreen({
    super.key,
    required this.repository,
    required this.onOpenClient,
    required this.onFilter,
  });

  final PlatformRepository repository;

  /// Opens one client.
  final ValueChanged<String> onOpenClient;

  /// Goes to the client list with one state chosen.
  final ValueChanged<String> onFilter;

  @override
  Widget build(BuildContext context) {
    final l = strings(context);
    final narrow = MediaQuery.sizeOf(context).width < 768;
    return SingleChildScrollView(
      padding: pagePadding(context, compact: narrow),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1040),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PageHead(title: l.pfOverview, subtitle: l.pfPlatform),
              const SizedBox(height: 24),
              AsyncSection<Overview>(
                loadingBuilder: (context) =>
                    const PlatformOverviewLoadingSkeleton(),
                load: repository.overview,
                builder: (context, data) => _Body(
                  data: data,
                  onOpenClient: onOpenClient,
                  onFilter: onFilter,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.data,
    required this.onOpenClient,
    required this.onFilter,
  });
  final Overview data;
  final ValueChanged<String> onOpenClient;
  final ValueChanged<String> onFilter;

  @override
  Widget build(BuildContext context) {
    final l = strings(context);
    int n(String key) => data.counts[key] ?? 0;
    final states = [
      ('active', l.pfCountActive, AppColors.emerald),
      ('trial', l.pfCountTrial, AppColors.blue),
      ('expiring', l.pfCountExpiring, AppColors.amber),
      ('grace', l.pfCountGrace, AppColors.warning),
      ('read_only', l.pfCountReadOnly, AppColors.rose),
      ('suspended', l.pfCountSuspended, AppColors.muted),
      ('free', l.pfCountFree, AppColors.violet),
    ];
    final income = data.income.isEmpty
        ? l.pfNoIncome
        : data.income.entries.map((e) => '${e.value} ${e.key}').join(' · ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SurfaceCard(
          flat: true,
          child: LayoutBuilder(
            builder: (context, box) {
              final chart = Semantics(
                label: '${l.pfTotalClients}: ${data.total}',
                child: DonutChart(
                  slices: [
                    for (final state in states.where(
                      (s) => s.$1 != 'trial' && s.$1 != 'expiring',
                    ))
                      DonutSlice(n(state.$1), state.$3),
                  ],
                  center: InkWell(
                    key: const ValueKey('pf-total'),
                    onTap: () => onFilter(''),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${data.total}',
                          style: const TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          l.pfTotalClients,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  size: 190,
                ),
              );
              final legend = Column(
                children: [
                  Text(
                    l.pfCountExplanation,
                    style: TextStyle(color: AppColors.muted, fontSize: 12),
                  ),
                  for (final state in states)
                    InkWell(
                      key: ValueKey('pf-count-${state.$1}'),
                      onTap: () => onFilter(state.$1),
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 14,
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: state.$3,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(child: Text(state.$2)),
                            const SizedBox(width: 12),
                            Text(
                              '${n(state.$1)}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(width: 8),
                            const AppIcon(AppIcons.chevron, size: 16),
                          ],
                        ),
                      ),
                    ),
                ],
              );
              return box.maxWidth < 560
                  ? Column(
                      children: [chart, const SizedBox(height: 20), legend],
                    )
                  : Row(
                      children: [
                        chart,
                        const SizedBox(width: 40),
                        Expanded(child: legend),
                      ],
                    );
            },
          ),
        ),
        const SizedBox(height: 20),
        SurfaceCard(
          flat: true,
          child: Wrap(
            spacing: 40,
            runSpacing: 24,
            children: [
              Column(
                key: const ValueKey('pf-income'),
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l.pfIncomeMonth,
                    style: TextStyle(color: AppColors.muted),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    income,
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              Column(
                key: const ValueKey('pf-new'),
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l.pfNewClients30,
                    style: TextStyle(color: AppColors.muted),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${data.new30}',
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        SectionHeading(l.pfNeedsAttention),
        const SizedBox(height: 12),
        if (data.attention.isEmpty)
          SurfaceCard(
            child: Text(
              l.pfNothingUrgent,
              key: const ValueKey('pf-nothing-urgent'),
              style: TextStyle(color: AppColors.muted),
            ),
          )
        else
          for (final row in data.attention)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: ClientTile(row: row, onTap: () => onOpenClient(row.id)),
            ),
        const SizedBox(height: 28),
        SectionHeading(l.pfRecentPayments),
        const SizedBox(height: 12),
        if (data.payments.isEmpty)
          SurfaceCard(
            child: Text(
              l.pfNoPayments,
              style: TextStyle(color: AppColors.muted),
            ),
          )
        else
          SurfaceCard(
            flat: true,
            child: Column(
              children: [
                for (final p in data.payments)
                  InkWell(
                    onTap: () => onOpenClient(p.clientId),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  p.storeName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  '${methodLabel(l, p.method)} · '
                                  '${p.at == null ? '' : formatStamp(p.at!)}',
                                  style: TextStyle(
                                    color: AppColors.muted,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            '${p.amount} ${p.currency}',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// One client in a list: name, owner, state and when it ends.
class ClientTile extends StatelessWidget {
  const ClientTile({super.key, required this.row, required this.onTap});
  final ClientRow row;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = strings(context);
    final who = [
      if (row.ownerName.isNotEmpty) row.ownerName,
      if (row.ownerLogin.isNotEmpty) row.ownerLogin,
      if (row.phone.isNotEmpty) row.phone,
    ].join(' · ');
    return SurfaceCard(
      key: ValueKey('client-${row.id}'),
      flat: true,
      onTap: onTap,
      padding: 16,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.storeName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                if (who.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    who,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: AppColors.muted, fontSize: 12),
                  ),
                ],
                const SizedBox(height: 6),
                Text(
                  endsText(l, row),
                  style: TextStyle(color: AppColors.neutral, fontSize: 13),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          StateBadge(row),
        ],
      ),
    );
  }
}
