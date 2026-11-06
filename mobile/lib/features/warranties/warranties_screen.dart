import 'dart:async';

import 'package:flutter/material.dart';
import '../../widgets/app_icons.dart';

import '../../core/connectivity/connection_monitor.dart';
import '../../core/format/format_stamp.dart';
import '../../core/operations/operation_runner.dart';
import '../../core/session/session_controller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../scanning/barcode_input.dart';
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

  // the register of goods sold with a warranty (the first tab)
  _WarrantyTab _tab = _WarrantyTab.sold;
  final _search = TextEditingController();
  Timer? _debounce;
  List<WarrantyRegisterItem> _sold = const [];
  Map<String, int> _soldCounts = const {};
  bool _soldMore = false;
  bool _soldLoading = true;
  Object? _soldError;
  String? _soldStatus = 'active';
  int _soldRequest = 0;

  SessionController get session => widget.session;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
    _loadSold(reset: true);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadSold({required bool reset}) async {
    final request = ++_soldRequest;
    setState(() {
      _soldLoading = true;
      _soldError = null;
      if (reset) _sold = const [];
    });
    try {
      final page = await widget.repository.register(
        status: _soldStatus,
        query: _search.text,
        offset: reset ? 0 : _sold.length,
      );
      if (!mounted || request != _soldRequest) return;
      setState(() {
        _sold = reset ? page.items : [..._sold, ...page.items];
        if (reset) _soldCounts = page.counts;
        _soldMore = page.hasMore;
        _soldLoading = false;
      });
    } catch (e) {
      if (!mounted || request != _soldRequest) return;
      setState(() {
        _soldError = e;
        _soldLoading = false;
      });
    }
  }

  /// A claim for a sold line: the sale is already known, the person only picks the problem.
  Future<void> _openFor(WarrantyRegisterItem item) async {
    final opened = await Navigator.of(context).push<WarrantyClaim>(
      MaterialPageRoute(
        builder: (_) => WarrantyNewScreen(
          session: session,
          repository: widget.repository,
          sales: widget.sales,
          unsaved: widget.unsaved,
          saleId: item.saleId,
        ),
      ),
    );
    if (opened != null && mounted) {
      showFeedback(
        context,
        strings(context).warrantyOpened(warrantyNumber(opened.number)),
      );
      _load(reset: true);
      _loadSold(reset: true);
    }
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
        AppTabs<_WarrantyTab>(
          keyPrefix: 'warranty-tab',
          keyName: (t) => t.name,
          tabs: [
            (_WarrantyTab.sold, l.warrantyTabSold),
            (_WarrantyTab.claims, l.warrantyTabClaims),
          ],
          value: _tab,
          onChanged: (t) => setState(() => _tab = t),
        ),
        const SizedBox(height: 20),
        if (_tab == _WarrantyTab.sold) ..._soldView(context, compact),
        if (_tab == _WarrantyTab.claims) ..._claimsView(context),
      ],
    );
  }

  /// Everything sold with a warranty, with the dates the server worked out: the thing to open
  /// when a customer comes back and says "I bought this here".
  List<Widget> _soldView(BuildContext context, bool compact) {
    final l = strings(context);
    String label(String text, String? key) {
      final n = key == null
          ? null
          : (_soldCounts[key] ?? (key == 'active' ? null : _soldCounts[key]));
      return n == null ? text : '$text · $n';
    }

    return [
      BarcodeInput(
        fieldKey: const ValueKey('warranty-search'),
        controller: _search,
        label: l.warrantySearchHint,
        onChanged: (_) {
          _debounce?.cancel();
          _debounce = Timer(
            const Duration(milliseconds: 350),
            () => _loadSold(reset: true),
          );
        },
        onSubmitted: (_) {
          _debounce?.cancel();
          _loadSold(reset: true);
        },
        onScanned: (_) {
          _debounce?.cancel();
          _loadSold(reset: true);
        },
      ),
      const SizedBox(height: 14),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final (status, text) in [
            ('active', l.warrantyFilterActive),
            ('soon', l.warrantyFilterSoon),
            ('expired', l.warrantyFilterExpired),
            ('returned', l.warrantyFilterReturned),
            (null, l.statusAll),
          ])
            AppPill(
              key: ValueKey('warranty-sold-${status ?? 'all'}'),
              label: label(text, status),
              selected: _soldStatus == status,
              onTap: () {
                _soldStatus = status;
                _loadSold(reset: true);
              },
            ),
        ],
      ),
      const SizedBox(height: 16),
      if (_soldError != null)
        ErrorPanel(error: _soldError!, onRetry: () => _loadSold(reset: true))
      else if (_soldLoading && _sold.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 32),
          child: Center(child: CircularProgressIndicator()),
        )
      else if (_sold.isEmpty)
        SurfaceCard(
          child: _search.text.trim().isEmpty && _soldStatus == null
              ? EmptyState(
                  key: const ValueKey('warranty-sold-empty'),
                  title: l.warrantyRegisterEmpty,
                  subtitle: l.warrantyRegisterEmptyHint,
                  icon: AppIcons.shield,
                )
              : EmptyState(
                  key: const ValueKey('warranty-sold-nomatch'),
                  title: l.warrantyNoMatch,
                  subtitle: '',
                  icon: AppIcons.search,
                ),
        )
      else ...[
        SurfaceCard(
          padding: 0,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < _sold.length; i++)
                Container(
                  key: ValueKey('warranty-sold-${_sold[i].saleLineId}'),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: i == 0
                        ? null
                        : const Border(top: BorderSide(color: AppColors.line)),
                  ),
                  child: _SoldRow(
                    item: _sold[i],
                    canOpen:
                        session.can('warranty.open') &&
                        _sold[i].status != 'returned' &&
                        (_sold[i].covered || session.can('warranty.override')),
                    onOpen: () => _openFor(_sold[i]),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (_soldMore)
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton(
              key: const ValueKey('warranty-sold-more'),
              onPressed: _soldLoading ? null : () => _loadSold(reset: false),
              child: Text(l.loadMore),
            ),
          ),
      ],
    ];
  }

  List<Widget> _claimsView(BuildContext context) {
    final l = strings(context);
    return [
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          AppPill(
            key: const ValueKey('warranty-filter-all'),
            label: l.statusAll,
            selected: _status == null,
            onTap: () {
              _status = null;
              _load(reset: true);
            },
          ),
          for (final (status, label) in [
            ('open', l.warrantyStatusOpen),
            ('closed', l.warrantyStatusClosed),
          ])
            AppPill(
              key: ValueKey('warranty-filter-$status'),
              label: label,
              selected: _status == status,
              onTap: () {
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
                  key: ValueKey('warranty-${warrantyNumber(_items[i].number)}'),
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
    ];
  }
}

enum _WarrantyTab { sold, claims }

String _day(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

/// One sold item with a warranty: what, to whom, the two dates, where it stands, and the button
/// that takes a claim for it.
class _SoldRow extends StatelessWidget {
  const _SoldRow({
    required this.item,
    required this.canOpen,
    required this.onOpen,
  });
  final WarrantyRegisterItem item;
  final bool canOpen;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final l = strings(context);
    final i = item;
    final (tone, icon, text) = switch (i.status) {
      'active' => (StatusTone.success, AppIcons.shield, l.warrantyFilterActive),
      'soon' => (StatusTone.warning, AppIcons.clock, l.warrantyFilterSoon),
      'expired' => (StatusTone.danger, AppIcons.block, l.warrantyFilterExpired),
      _ => (StatusTone.neutral, AppIcons.returnArrow, l.warrantyFilterReturned),
    };
    final when = switch (i.status) {
      'returned' => l.warrantyReturnedNote,
      'expired' => l.warrantyExpiredDaysAgo(-i.daysLeft),
      _ => i.daysLeft == 0 ? l.warrantyLastDay : l.warrantyDaysLeft(i.daysLeft),
    };
    final qty = i.quantityMilli % 1000 == 0
        ? '${i.quantityMilli ~/ 1000}'
        : (i.quantityMilli / 1000).toString();
    return LayoutBuilder(
      builder: (context, box) {
        final narrow = box.maxWidth < 560;
        final details = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              i.quantityMilli == 1000 ? i.name : '${i.name} × $qty',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            ),
            const SizedBox(height: 4),
            Text(
              [
                saleNumber(i.saleNumber),
                if (i.customerName.isNotEmpty) i.customerName,
                if (i.customerPhone.isNotEmpty) i.customerPhone,
              ].join(' · '),
              style: const TextStyle(color: AppColors.muted, fontSize: 13),
            ),
            const SizedBox(height: 6),
            Text(
              '${l.warrantySoldOn(_day(i.starts))}  →  ${l.warrantyUntil(_day(i.until))}',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            if (i.terms.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  i.terms,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.muted, fontSize: 12),
                ),
              ),
          ],
        );
        final side = Column(
          crossAxisAlignment: narrow
              ? CrossAxisAlignment.start
              : CrossAxisAlignment.end,
          children: [
            StatusPill(label: text, tone: tone, icon: icon),
            const SizedBox(height: 6),
            Text(
              when,
              style: const TextStyle(color: AppColors.muted, fontSize: 12),
            ),
            if (i.openClaims > 0) ...[
              const SizedBox(height: 6),
              StatusPill(
                label: l.warrantyClaimOpenBadge,
                tone: StatusTone.warning,
                icon: AppIcons.clock,
              ),
            ],
            if (canOpen) ...[
              const SizedBox(height: 10),
              OutlinedButton(
                key: ValueKey('warranty-accept-${i.saleLineId}'),
                onPressed: onOpen,
                child: Text(l.warrantyAccept),
              ),
            ],
          ],
        );
        return narrow
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [details, const SizedBox(height: 12), side],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: details),
                  const SizedBox(width: 16),
                  side,
                ],
              );
      },
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
