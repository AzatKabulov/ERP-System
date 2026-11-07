import 'package:flutter/material.dart';

import '../../core/format/format_stamp.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_icons.dart';
import '../../widgets/common.dart';
import '../../widgets/glass.dart';
import '../shared/async_section.dart';
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
    Widget count(
      String keyName,
      String label,
      String filter,
      AppIconData icon, {
      Color? accent,
      Color? tint,
    }) => MetricCard(
      key: ValueKey('pf-count-$keyName'),
      label: label,
      value: '${n(keyName)}',
      icon: icon,
      accent: accent,
      accentTint: tint,
      onTap: () => onFilter(filter),
    );
    final income = data.income.isEmpty
        ? l.pfNoIncome
        : data.income.entries.map((e) => '${e.value} ${e.key}').join(' · ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AdaptiveGrid(
          minimumWidth: 200,
          maxColumns: 4,
          children: [
            MetricCard(
              key: const ValueKey('pf-total'),
              label: l.pfTotalClients,
              value: '${data.total}',
              icon: AppIcons.user,
              featured: true,
              onTap: () => onFilter(''),
            ),
            count('active', l.pfCountActive, 'active', AppIcons.checkCircle),
            count('trial', l.pfCountTrial, 'trial', AppIcons.clock),
            count(
              'expiring',
              l.pfCountExpiring,
              'expiring',
              AppIcons.warning,
              accent: AppColors.warning,
              tint: AppColors.warningTint,
            ),
            count(
              'grace',
              l.pfCountGrace,
              'grace',
              AppIcons.warning,
              accent: AppColors.warning,
              tint: AppColors.warningTint,
            ),
            count(
              'read_only',
              l.pfCountReadOnly,
              'read_only',
              AppIcons.lock,
              accent: AppColors.danger,
              tint: AppColors.dangerTint,
            ),
            count(
              'suspended',
              l.pfCountSuspended,
              'suspended',
              AppIcons.block,
              accent: AppColors.danger,
              tint: AppColors.dangerTint,
            ),
            count('free', l.pfCountFree, 'free', AppIcons.tag),
          ],
        ),
        const SizedBox(height: 16),
        AdaptiveGrid(
          minimumWidth: 300,
          maxColumns: 2,
          children: [
            MetricCard(
              key: const ValueKey('pf-income'),
              label: l.pfIncomeMonth,
              value: income,
              icon: AppIcons.receipt,
            ),
            MetricCard(
              key: const ValueKey('pf-new'),
              label: l.pfNewClients30,
              value: '${data.new30}',
              icon: AppIcons.personAdd,
            ),
          ],
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
