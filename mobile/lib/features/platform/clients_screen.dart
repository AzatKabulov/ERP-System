import 'package:flutter/material.dart';

import '../../widgets/app_icons.dart';
import '../../widgets/common.dart';
import '../../widgets/glass.dart';
import '../shared/async_section.dart';
import '../shared/loading_skeletons.dart';
import 'overview_screen.dart';
import 'platform_models.dart';
import 'platform_repository.dart';

/// Every client: search, a state filter, and a button for a new one.
class ClientsScreen extends StatefulWidget {
  const ClientsScreen({
    super.key,
    required this.repository,
    required this.initialFilter,
    required this.onOpenClient,
    required this.onNewClient,
  });

  final PlatformRepository repository;

  /// '' (all), 'attention', or a state.
  final String initialFilter;
  final ValueChanged<String> onOpenClient;
  final VoidCallback onNewClient;

  @override
  State<ClientsScreen> createState() => _ClientsScreenState();
}

class _ClientsScreenState extends State<ClientsScreen> {
  final _search = TextEditingController();
  late String _filter = widget.initialFilter;
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _setFilter(String value) {
    setState(() => _filter = value);
  }

  @override
  Widget build(BuildContext context) {
    final l = strings(context);
    final narrow = MediaQuery.sizeOf(context).width < 768;
    final filters = <(String, String)>[
      ('', l.pfFilterAll),
      ('attention', l.pfFilterAttention),
      ('active', l.pfStateActive),
      ('trial', l.pfStateTrial),
      ('expiring', l.pfStateExpiring),
      ('grace', l.pfStateGrace),
      ('read_only', l.pfStateReadOnly),
      ('suspended', l.pfStateSuspended),
      ('free', l.pfStateFree),
    ];
    return SingleChildScrollView(
      padding: pagePadding(context, compact: narrow),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 880),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PageHead(
                title: l.pfClients,
                actions: [
                  PrimaryButton(
                    key: const ValueKey('pf-new-client'),
                    label: l.pfNewClient,
                    icon: AppIcons.personAdd,
                    onPressed: widget.onNewClient,
                  ),
                ],
              ),
              const SizedBox(height: 20),
              TextField(
                key: const ValueKey('pf-search'),
                controller: _search,
                textInputAction: TextInputAction.search,
                onSubmitted: (v) => setState(() => _query = v),
                decoration: InputDecoration(
                  hintText: l.pfSearchClients,
                  prefixIcon: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 14),
                    child: AppIcon(AppIcons.search, size: 20),
                  ),
                  prefixIconConstraints: const BoxConstraints(minWidth: 48),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: l.close,
                          icon: const AppIcon(AppIcons.close, size: 18),
                          onPressed: () => setState(() {
                            _search.clear();
                            _query = '';
                          }),
                        ),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final (value, label) in filters)
                    AppPill(
                      key: ValueKey(
                        'pf-filter-${value.isEmpty ? 'all' : value}',
                      ),
                      label: label,
                      selected: _filter == value,
                      onTap: () => _setFilter(value),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              AsyncSection<List<ClientRow>>(
                loadingBuilder: (context) =>
                    const RecordListSkeleton(rows: 4, rowHeight: 112),
                key: ValueKey('clients-$_filter-$_query'),
                load: () =>
                    widget.repository.clients(state: _filter, query: _query),
                builder: (context, rows) {
                  if (rows.isEmpty) {
                    return SurfaceCard(
                      child: EmptyState(
                        key: const ValueKey('pf-no-clients'),
                        title: l.pfNoClients,
                        subtitle: l.pfNoClientsHint,
                        icon: AppIcons.user,
                      ),
                    );
                  }
                  return Column(
                    children: [
                      for (final row in rows)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: ClientTile(
                            row: row,
                            onTap: () => widget.onOpenClient(row.id),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
