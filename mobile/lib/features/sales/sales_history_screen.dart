import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/connectivity/connection_monitor.dart';
import '../../core/format/format_stamp.dart';
import '../../core/money/decimal_math.dart';
import '../../core/operations/operation_runner.dart';
import '../../core/session/session_controller.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../returns/return_form_screen.dart';
import '../returns/returns_models.dart';
import '../returns/returns_repository.dart';
import '../shared/async_section.dart';
import '../warranties/warranties_repository.dart';
import '../warranties/warranties_models.dart';
import '../warranties/warranty_new_screen.dart';
import '../workspace/unsaved_work.dart';
import 'document_buttons.dart';
import 'sales_models.dart';
import 'sales_repository.dart';

String _methodText(AppLocalizations l, String method) =>
    method == 'cash' ? l.payCash : l.payCard;

/// Past sales, newest first, searchable by number or customer. Read-only: a completed sale
/// is a historical record; returns and corrections are separate documents.
class SalesHistoryScreen extends StatefulWidget {
  const SalesHistoryScreen({
    super.key,
    required this.session,
    required this.repository,
    required this.runner,
    required this.monitor,
    required this.unsaved,
  });

  final SessionController session;
  final SalesRepository repository;
  final OperationRunner runner;
  final ConnectionMonitor monitor;
  final UnsavedWork unsaved;

  @override
  State<SalesHistoryScreen> createState() => _SalesHistoryScreenState();
}

class _SalesHistoryScreenState extends State<SalesHistoryScreen> {
  static const _pageSize = 30;
  final _search = TextEditingController();
  Timer? _debounce;
  List<SaleSummary> _items = const [];
  int _count = 0;
  bool _loading = true;
  Object? _error;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({required bool reset}) async {
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = null;
      if (reset) _items = const [];
    });
    try {
      final page = await widget.repository.sales(
        query: _search.text,
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

  @override
  Widget build(BuildContext context) {
    final l = strings(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.saleHistoryTitle)),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 860),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                TextField(
                  key: const ValueKey('history-search'),
                  controller: _search,
                  onChanged: (_) {
                    _debounce?.cancel();
                    _debounce = Timer(
                      const Duration(milliseconds: 350),
                      () => _load(reset: true),
                    );
                  },
                  decoration: InputDecoration(
                    labelText: l.saleSearchHint,
                    prefixIcon: const Icon(Icons.search),
                  ),
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
                      key: const ValueKey('sales-history-empty'),
                      title: l.salesHistoryEmpty,
                      subtitle: '',
                      icon: Icons.receipt_long_outlined,
                    ),
                  )
                else ...[
                  for (final sale in _items)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _SaleTile(
                        sale: sale,
                        onTap: () => Navigator.of(context).push<void>(
                          MaterialPageRoute(
                            builder: (_) => SaleDetailScreen(
                              saleId: sale.id,
                              session: widget.session,
                              repository: widget.repository,
                              runner: widget.runner,
                              monitor: widget.monitor,
                              unsaved: widget.unsaved,
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (_items.length < _count)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton(
                        key: const ValueKey('sales-load-more'),
                        onPressed: _loading ? null : () => _load(reset: false),
                        child: Text(l.loadMore),
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
}

class _SaleTile extends StatelessWidget {
  const _SaleTile({required this.sale, required this.onTap});
  final SaleSummary sale;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = strings(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: ValueKey('sale-${saleNumber(sale.number)}'),
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: SurfaceCard(
          padding: 14,
          child: Wrap(
            spacing: 16,
            runSpacing: 6,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 200, maxWidth: 520),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${saleNumber(sale.number)} · ${formatStamp(sale.createdAt)}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      [
                        sale.locationName,
                        sale.cashierName,
                        if (sale.customerName.isNotEmpty) sale.customerName,
                      ].join(' · '),
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    formatMoney(sale.totalMinor, 'TMT'),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    _methodText(l, sale.paymentMethod),
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One past sale in full, with its documents and, while something can still come back, the
/// button that starts a return.
class SaleDetailScreen extends StatefulWidget {
  const SaleDetailScreen({
    super.key,
    required this.saleId,
    required this.session,
    required this.repository,
    required this.runner,
    required this.monitor,
    required this.unsaved,
  });

  final String saleId;
  final SessionController session;
  final SalesRepository repository;
  final OperationRunner runner;
  final ConnectionMonitor monitor;
  final UnsavedWork unsaved;

  @override
  State<SaleDetailScreen> createState() => _SaleDetailScreenState();
}

class _SaleDetailScreenState extends State<SaleDetailScreen> {
  final _section = GlobalKey<AsyncSectionState<SaleDetail>>();

  SessionController get session => widget.session;

  bool _mayUse(String locationId) {
    final m = session.membership;
    return m != null && m.locations.any((x) => x.id == locationId);
  }

  Future<void> _startReturn(SaleDetail sale) async {
    final result = await Navigator.of(context).push<ReturnResult>(
      MaterialPageRoute(
        builder: (_) => ReturnFormScreen(
          sale: sale,
          session: session,
          repository: ReturnsRepository(
            widget.repository.api,
            widget.repository.businessId,
          ),
          runner: widget.runner,
          monitor: widget.monitor,
          unsaved: widget.unsaved,
        ),
      ),
    );
    if (result == null || !mounted) return;
    final l = strings(context);
    if (result == ReturnResult.done) {
      showFeedback(context, l.returnDone);
      _section.currentState?.reload();
    } else {
      showFeedback(context, l.outcomeUnknownNotice);
      Navigator.of(context).popUntil((r) => r.isFirst); // where the banner is
    }
  }

  Future<void> _startWarranty(SaleDetail sale) async {
    final opened = await Navigator.of(context).push<WarrantyClaim>(
      MaterialPageRoute(
        builder: (_) => WarrantyNewScreen(
          session: session,
          repository: WarrantiesRepository(
            widget.repository.api,
            widget.repository.businessId,
          ),
          sales: widget.repository,
          unsaved: widget.unsaved,
          saleId: sale.id,
        ),
      ),
    );
    if (opened == null || !mounted) return;
    showFeedback(
      context,
      strings(context).warrantyOpened(warrantyNumber(opened.number)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = strings(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.saleHistoryTitle)),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 860),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: AsyncSection<SaleDetail>(
                key: _section,
                load: () => widget.repository.sale(widget.saleId),
                builder: (context, sale) => _body(context, sale),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _returnInfo(AppLocalizations l, SaleLineRecord line) {
    if (line.returnDays == 0) {
      return Text(
        l.returnNotAccepted,
        style: const TextStyle(color: AppColors.danger, fontSize: 13),
      );
    }
    final until = line.returnUntil;
    return Text(
      until == null ? l.returnNoLimit : l.returnUntilLine(until),
      style: const TextStyle(color: AppColors.muted, fontSize: 13),
    );
  }

  Widget _body(BuildContext context, SaleDetail sale) {
    final l = strings(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l.saleDetailTitle(saleNumber(sale.number)),
                key: const ValueKey('sd-number'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              Text(
                '${formatStamp(sale.createdAt)} · ${sale.locationName}',
                style: const TextStyle(color: AppColors.muted),
              ),
              Text(l.cashierLine(sale.cashierName)),
              if (sale.customerName.isNotEmpty)
                Text('${l.customer}: ${sale.customerName}'),
              if (sale.note.isNotEmpty) Text(sale.note),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final line in sale.lines)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 2,
                        alignment: WrapAlignment.spaceBetween,
                        children: [
                          Text(
                            line.name,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          Text(
                            formatMoney(line.lineTotalMinor, 'TMT'),
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                      Text(
                        l.saleUnitsLine(
                          '${formatQuantity(line.quantityMilli, line.unitDecimals)} ${line.unitSymbol}',
                          formatMoney(line.unitPriceMinor, 'TMT'),
                        ),
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 13,
                        ),
                      ),
                      if (line.warrantyMonths > 0)
                        Text(
                          l.warrantyMonthsValue(line.warrantyMonths),
                          style: const TextStyle(fontSize: 13),
                        ),
                      if (line.returnedMilli > 0)
                        Text(
                          l.returnedSoFar(
                            '${formatQuantity(line.returnedMilli, line.unitDecimals)} ${line.unitSymbol}',
                          ),
                          key: ValueKey('sd-returned-${line.id}'),
                          style: const TextStyle(
                            color: AppColors.warning,
                            fontSize: 13,
                          ),
                        ),
                      if (line.returnableMilli > 0) _returnInfo(l, line),
                    ],
                  ),
                ),
              const Divider(),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  l.saleTotal(formatMoney(sale.totalMinor, 'TMT')),
                  key: const ValueKey('sd-total'),
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  '${l.paidBy}: ${_methodText(l, sale.paymentMethod)}',
                  key: const ValueKey('sd-method'),
                  style: const TextStyle(color: AppColors.muted),
                ),
              ),
              if (sale.costTotalMinor != null && sale.profitMinor != null) ...[
                const Divider(),
                Text(
                  l.saleCostLine(formatMoney(sale.costTotalMinor!, 'TMT')),
                  key: const ValueKey('sd-cost'),
                  style: const TextStyle(color: AppColors.muted),
                ),
                Text(
                  l.saleProfitLine(formatMoney(sale.profitMinor!, 'TMT')),
                  key: const ValueKey('sd-profit'),
                  style: const TextStyle(color: AppColors.muted),
                ),
              ],
            ],
          ),
        ),
        if (sale.returns.isNotEmpty) ...[
          const SizedBox(height: 16),
          SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.saleReturnsTitle,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                for (final r in sale.returns)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      '${returnNumber(r.number)} · ${formatStamp(r.createdAt)} · ${formatMoney(r.refundMinor, 'TMT')}',
                      key: ValueKey('sd-return-${returnNumber(r.number)}'),
                    ),
                  ),
              ],
            ),
          ),
        ],
        if (session.can('return.create') &&
            sale.hasReturnable &&
            _mayUse(sale.locationId)) ...[
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: GradientButton(
              key: const ValueKey('sd-return'),
              label: l.returnButton,
              icon: Icons.assignment_return_outlined,
              onPressed: () => _startReturn(sale),
            ),
          ),
        ],
        if (session.can('warranty.open') &&
            (sale.lines.any((x) => x.warrantyMonths > 0) ||
                session.can('warranty.override'))) ...[
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              key: const ValueKey('sd-warranty'),
              onPressed: () => _startWarranty(sale),
              icon: const Icon(Icons.verified_user_outlined),
              label: Text(l.warrantyFromSale),
            ),
          ),
        ],
        const SizedBox(height: 16),
        SurfaceCard(
          child: DocumentButtons(
            repository: widget.repository,
            saleId: sale.id,
            saleNumber: sale.number,
          ),
        ),
      ],
    );
  }
}
