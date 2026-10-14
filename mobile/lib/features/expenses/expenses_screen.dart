import 'package:flutter/material.dart';
import '../../widgets/app_icons.dart';

import '../../core/api/api_exception.dart';
import '../../core/money/decimal_math.dart';
import '../../core/session/session_controller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../shared/async_section.dart';
import '../workspace/unsaved_work.dart';
import 'expense_detail_screen.dart';
import 'expense_form_screen.dart';
import 'expenses_models.dart';
import 'expenses_repository.dart';

String _day(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Money spent on the business (rent, wages, transport...), newest first, with a total and the
/// total per category for the chosen period. Owners and managers only.
class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({
    super.key,
    required this.session,
    required this.repository,
    required this.unsaved,
  });

  final SessionController session;
  final ExpensesRepository repository;
  final UnsavedWork unsaved;

  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

enum _Period { thisMonth, lastMonth, all }

class _ExpensesScreenState extends State<ExpensesScreen> {
  static const _pageSize = 30;
  _Period _period = _Period.thisMonth;
  String? _categoryId;
  List<ExpenseCategory> _categories = const [];
  List<Expense> _items = const [];
  int _count = 0;
  ExpenseSummary? _summary;
  bool _loading = true;
  Object? _error;
  int _request = 0;

  SessionController get session => widget.session;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  ExpenseFilter get _filter {
    final now = DateTime.now();
    switch (_period) {
      case _Period.thisMonth:
        return ExpenseFilter(
          from: _day(DateTime(now.year, now.month, 1)),
          to: _day(DateTime(now.year, now.month + 1, 0)),
          categoryId: _categoryId,
        );
      case _Period.lastMonth:
        return ExpenseFilter(
          from: _day(DateTime(now.year, now.month - 1, 1)),
          to: _day(DateTime(now.year, now.month, 0)),
          categoryId: _categoryId,
        );
      case _Period.all:
        return ExpenseFilter(categoryId: _categoryId);
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
      if (_categories.isEmpty) {
        _categories = await widget.repository.categories();
      }
      final page = await widget.repository.expenses(
        filter: _filter,
        offset: reset ? 0 : _items.length,
        limit: _pageSize,
      );
      final summary = reset
          ? await widget.repository.summary(_filter)
          : _summary;
      if (!mounted || request != _request) return;
      setState(() {
        _items = reset ? page.items : [..._items, ...page.items];
        _count = page.count;
        _summary = summary;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted || request != _request) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _add() async {
    final saved = await Navigator.of(context).push<Expense>(
      MaterialPageRoute(
        builder: (_) => ExpenseFormScreen(
          session: session,
          repository: widget.repository,
          unsaved: widget.unsaved,
        ),
      ),
    );
    if (saved != null && mounted) {
      showFeedback(context, strings(context).expenseSaved);
      _categories = const [];
      _load(reset: true);
    }
  }

  Future<void> _open(Expense e) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ExpenseDetailScreen(
          expenseId: e.id,
          session: session,
          repository: widget.repository,
          unsaved: widget.unsaved,
        ),
      ),
    );
    if (changed == true && mounted) _load(reset: true);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) =>
        _page(context, constraints.maxWidth < 600),
  );

  Widget _page(BuildContext context, bool compact) {
    final l = strings(context);
    final summary = _summary;
    return ListView(
      padding: EdgeInsets.fromLTRB(
        compact ? 16 : 32,
        compact ? 20 : 32,
        compact ? 16 : 32,
        40,
      ),
      children: [
        PageHead(
          title: l.expenses,
          subtitle: session.location?.name,
          actions: [
            if (session.can('expense.manage'))
              PrimaryButton(
                key: const ValueKey('expense-add'),
                label: l.expenseAddButton,
                icon: AppIcons.plus,
                onPressed: _add,
              ),
          ],
        ),
        const SizedBox(height: 24),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final (period, label) in [
              (_Period.thisMonth, l.expensePeriodMonth),
              (_Period.lastMonth, l.expensePeriodLast),
              (_Period.all, l.expensePeriodAll),
            ])
              ChoiceChip(
                key: ValueKey('expense-period-${period.name}'),
                label: Text(label),
                selected: _period == period,
                onSelected: (_) {
                  _period = period;
                  _load(reset: true);
                },
              ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 240),
              child: FilterSelect<String?>(
                fieldKey: const ValueKey('expense-category-filter'),
                value: _categories.any((c) => c.id == _categoryId)
                    ? _categoryId
                    : null,
                hint: Text(l.expenseAllCategories),
                items: [
                  DropdownMenuItem<String?>(
                    value: null,
                    child: Text(l.expenseAllCategories),
                  ),
                  for (final c in _categories)
                    DropdownMenuItem<String?>(value: c.id, child: Text(c.name)),
                ],
                onChanged: (v) {
                  _categoryId = v;
                  _load(reset: true);
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (summary != null && _error == null) ...[
          AdaptiveGrid(
            children: [
              KeyedSubtree(
                key: const ValueKey('expense-total'),
                child: Semantics(
                  container: true,
                  child: MetricCard(
                    label: l.cartTotalLabel,
                    value: formatMoney(summary.totalMinor, 'TMT'),
                    meta: l.expenseOperationsCount(summary.count),
                  ),
                ),
              ),
              for (final c in summary.byCategory)
                KeyedSubtree(
                  key: ValueKey('expense-cat-${c.categoryId}'),
                  child: Semantics(
                    container: true,
                    child: MetricCard(
                      label: c.name,
                      value: formatMoney(c.totalMinor, 'TMT'),
                      meta: l.expenseOperationsCount(c.count),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
        ],
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
              key: const ValueKey('expenses-empty'),
              title: l.expensesEmpty,
              subtitle: '',
              icon: AppIcons.expense,
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
                    key: ValueKey('expense-${_items[i].id}'),
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
                      child: _ExpenseRow(expense: _items[i], index: i),
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
                key: const ValueKey('expenses-load-more'),
                onPressed: _loading ? null : () => _load(reset: false),
                child: Text(l.loadMore),
              ),
            ),
        ],
      ],
    );
  }
}

class _ExpenseRow extends StatelessWidget {
  const _ExpenseRow({required this.expense, required this.index});
  final Expense expense;
  final int index;

  @override
  Widget build(BuildContext context) {
    final l = strings(context);
    final e = expense;
    final title = e.description.isNotEmpty ? e.description : e.categoryName;
    return Row(
      children: [
        Glyph(
          AppIcons.receipt,
          background: e.voided
              ? AppColors.dangerTint
              : index.isOdd
              ? AppColors.warningTint
              : AppColors.surfaceMuted,
          color: e.voided ? AppColors.danger : AppColors.neutral,
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  decoration: e.voided ? TextDecoration.lineThrough : null,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                [e.categoryName, e.locationName].join(' · '),
                style: const TextStyle(
                  color: AppColors.muted,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (e.attachment != null) ...[
                  const AppIcon(
                    AppIcons.attach,
                    size: 16,
                    color: AppColors.muted,
                  ),
                  const SizedBox(width: 6),
                ],
                Text(
                  formatMoney(e.amountMinor, 'TMT'),
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              e.voided ? l.expenseVoidedBadge : e.spentOn,
              style: TextStyle(
                color: e.voided ? AppColors.danger : AppColors.muted,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
