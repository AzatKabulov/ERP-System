import 'package:flutter/material.dart';
import '../../widgets/app_icons.dart';

import '../../core/connectivity/connection_monitor.dart';
import '../../core/format/format_stamp.dart';
import '../../core/operations/operation_runner.dart';
import '../../core/session/session_controller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../sales/sales_models.dart';
import '../sales/sales_repository.dart';
import '../shared/async_section.dart';
import '../workspace/unsaved_work.dart';
import 'warranties_models.dart';
import 'warranties_repository.dart';
import 'warranty_detail_screen.dart';
import 'warranty_new_screen.dart';

/// Warranty claims, newest first, with a status filter. Start a new one from a sale; open one
/// to follow it and, for owners and managers, to close it with an outcome.
class WarrantiesScreen extends StatefulWidget {
  const WarrantiesScreen({
    super.key,
    required this.session,
    required this.repository,
    required this.sales,
    required this.runner,
    required this.monitor,
    required this.unsaved,
  });

  final SessionController session;
  final WarrantiesRepository repository;
  final SalesRepository sales;
  final OperationRunner runner;
  final ConnectionMonitor monitor;
  final UnsavedWork unsaved;

  @override
  State<WarrantiesScreen> createState() => _WarrantiesScreenState();
}

class _WarrantiesScreenState extends State<WarrantiesScreen> {
  static const _pageSize = 30;
  List<WarrantyClaim> _items = const [];
  int _count = 0;
  bool _loading = true;
  Object? _error;
  String? _status;
  int _request = 0;

  SessionController get session => widget.session;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  Future<void> _load({required bool reset}) async {
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = null;
      if (reset) _items = const [];
    });
    try {
      final page = await widget.repository.claims(
        status: _status,
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

  Future<void> _open(WarrantyClaim claim) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => WarrantyDetailScreen(
          claimId: claim.id,
          session: session,
          repository: widget.repository,
          runner: widget.runner,
          monitor: widget.monitor,
        ),
      ),
    );
    if (changed == true && mounted) _load(reset: true);
  }

  Future<void> _new() async {
    final opened = await Navigator.of(context).push<WarrantyClaim>(
      MaterialPageRoute(
        builder: (_) => WarrantyNewScreen(
          session: session,
          repository: widget.repository,
          sales: widget.sales,
          unsaved: widget.unsaved,
        ),
      ),
    );
    if (opened != null && mounted) {
      showFeedback(
        context,
        strings(context).warrantyOpened(warrantyNumber(opened.number)),
      );
      _load(reset: true);
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) =>
        _page(context, constraints.maxWidth < 600),
  );

  Widget _page(BuildContext context, bool compact) {
    final l = strings(context);
    return ListView(
      padding: EdgeInsets.fromLTRB(
        compact ? 16 : 32,
        compact ? 20 : 32,
        compact ? 16 : 32,
        40,
      ),
      children: [
        PageHead(
          title: l.warranties,
          subtitle: session.location?.name,
          actions: [
            if (session.can('warranty.open'))
              PrimaryButton(
                key: const ValueKey('warranty-new'),
                label: l.warrantyNew,
                icon: AppIcons.plus,
                onPressed: _new,
              ),
          ],
        ),
        const SizedBox(height: 24),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ChoiceChip(
              key: const ValueKey('warranty-filter-all'),
              label: Text(l.statusAll),
              selected: _status == null,
              onSelected: (_) {
                _status = null;
                _load(reset: true);
              },
            ),
            for (final (status, label) in [
              ('open', l.warrantyStatusOpen),
              ('closed', l.warrantyStatusClosed),
            ])
              ChoiceChip(
                key: ValueKey('warranty-filter-$status'),
                label: Text(label),
                selected: _status == status,
                onSelected: (_) {
                  _status = status;
                  _load(reset: true);
                },
              ),
          ],
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
              key: const ValueKey('warranties-empty'),
              title: l.warrantiesEmpty,
              subtitle: '',
              icon: AppIcons.shield,
            ),
          )
        else ...[
          SurfaceCard(
            padding: 0,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < _items.length; i++)
                  InkWell(
                    key: ValueKey(
                      'warranty-${warrantyNumber(_items[i].number)}',
                    ),
                    onTap: () => _open(_items[i]),
                    hoverColor: AppColors.surfaceSoft,
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 68),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        border: i == 0
                            ? null
                            : const Border(
                                top: BorderSide(color: AppColors.line),
                              ),
                      ),
                      child: _ClaimRow(claim: _items[i]),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (_items.length < _count)
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton(
                key: const ValueKey('warranties-load-more'),
                onPressed: _loading ? null : () => _load(reset: false),
                child: Text(l.loadMore),
              ),
            ),
        ],
      ],
    );
  }
}

class _ClaimRow extends StatelessWidget {
  const _ClaimRow({required this.claim});
  final WarrantyClaim claim;

  @override
  Widget build(BuildContext context) {
    final l = strings(context);
    final c = claim;
    return Row(
      children: [
        const Glyph(AppIcons.shield),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: warrantyNumber(c.number),
                      style: const TextStyle(
                        fontFamily: AppFonts.mono,
                        letterSpacing: -0.3,
                      ),
                    ),
                    TextSpan(text: ' · ${formatStamp(c.openedAt)}'),
                  ],
                ),
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${c.productName} · ${saleNumber(c.saleNumber)}',
                style: const TextStyle(color: AppColors.muted, fontSize: 13),
              ),
              if (c.customerName.isNotEmpty)
                Text(
                  c.customerName,
                  style: const TextStyle(color: AppColors.muted, fontSize: 12),
                ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 160),
          child: StatusPill(
            label: c.isOpen
                ? l.warrantyStatusOpen
                : warrantyOutcomeLabel(l, c.outcome),
            tone: c.isOpen ? StatusTone.warning : StatusTone.success,
            icon: c.isOpen ? AppIcons.clock : AppIcons.check,
          ),
        ),
      ],
    );
  }
}
