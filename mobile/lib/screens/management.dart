import 'package:flutter/material.dart';

import '../demo/demo_store.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import 'dashboard.dart';
import 'workspace.dart';

class ManagementScreen extends StatelessWidget {
  const ManagementScreen({
    super.key,
    required this.page,
    required this.store,
    required this.languageCode,
    required this.onLanguageChanged,
  });
  final AppPage page;
  final DemoStore store;
  final String languageCode;
  final ValueChanged<String> onLanguageChanged;

  List<Widget> _purchasing(BuildContext context) {
    final l = strings(context);
    final orders = [
      ('PO-001', 'brake', 20, 'Brembo'),
      ('PO-002', 'oil', 24, 'Shell'),
      ('PO-003', 'battery', 6, 'Varta'),
    ];
    return [
      Text(
        l.purchasingHint,
        style: const TextStyle(color: AppColors.muted, height: 1.5),
      ),
      const SizedBox(height: 24),
      for (final (id, productId, quantity, supplier) in orders)
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 16,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(id, style: Theme.of(context).textTheme.titleMedium),
                    StatusPill(
                      label: store.orderReceived(id) ? l.received : l.expected,
                      warning: !store.orderReceived(id),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  store.product(productId).name,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 8),
                Text(
                  '${l.supplier}: $supplier · ${l.quantity}: $quantity',
                  style: const TextStyle(color: AppColors.muted),
                ),
                const SizedBox(height: 16),
                GradientButton(
                  label: l.receiveGoods,
                  icon: Icons.download_outlined,
                  onPressed: store.orderReceived(id)
                      ? null
                      : () async {
                          if (!await confirmAction(
                                context,
                                l.receiveGoods,
                                '${l.stockActionNotice}\n\n${locationLabel(l, store.location)}\n${store.product(productId).name} · $quantity',
                              ) ||
                              !context.mounted) {
                            return;
                          }
                          if (store.receive(
                            store.product(productId),
                            quantity,
                            orderId: id,
                          )) {
                            showFeedback(context, l.operationSaved);
                          }
                        },
                ),
              ],
            ),
          ),
        ),
    ];
  }

  List<Widget> _expenses(BuildContext context) {
    final l = strings(context);
    return [
      Wrap(
        spacing: 24,
        runSpacing: 16,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            money(store.expenseTotal),
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          GradientButton(
            label: l.newExpense,
            icon: Icons.add,
            onPressed: () => showDialog<void>(
              context: context,
              builder: (context) => ExpenseDialog(store: store),
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      Text(l.expenseHint, style: const TextStyle(color: AppColors.muted)),
      const SizedBox(height: 24),
      if (store.expenses.isEmpty)
        SurfaceCard(
          child: EmptyState(
            title: l.noExpenses,
            icon: Icons.account_balance_wallet_outlined,
          ),
        ),
      for (final expense in store.expenses)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: SurfaceCard(
            child: Wrap(
              spacing: 24,
              runSpacing: 8,
              children: [
                Text(
                  expense.label,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                Text(
                  money(expense.amountMinor),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
    ];
  }

  List<Widget> _warranties(BuildContext context) {
    final l = strings(context);
    return [
      Text(
        l.warrantyHint,
        style: const TextStyle(color: AppColors.muted, height: 1.5),
      ),
      const SizedBox(height: 24),
      for (final (id, productId, resolved) in [
        ('DEMO-W01', 'battery', false),
        ('DEMO-W02', 'brake', false),
        ('DEMO-W03', 'plug', true),
      ])
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 16,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(id, style: Theme.of(context).textTheme.titleMedium),
                    StatusPill(
                      label: resolved ? l.resolved : l.underReview,
                      warning: !resolved,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(store.product(productId).name),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: Text('$id · ${l.claimDetails}'),
                      content: SingleChildScrollView(
                        child: Text(l.warrantyExample),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: Text(l.close),
                        ),
                      ],
                    ),
                  ),
                  child: Text(l.claimDetails),
                ),
              ],
            ),
          ),
        ),
    ];
  }

  List<Widget> _reports(BuildContext context) {
    final l = strings(context);
    return [
      Text(
        l.reportHint,
        style: const TextStyle(color: AppColors.muted, height: 1.5),
      ),
      const SizedBox(height: 8),
      Text(
        l.reportScope,
        style: const TextStyle(color: AppColors.muted, fontSize: 13),
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
            label: l.refundTotal,
            value: money(store.refundTotal),
            icon: Icons.assignment_return_outlined,
          ),
          MetricCard(
            label: l.expenseTotal,
            value: money(store.expenseTotal),
            icon: Icons.account_balance_wallet_outlined,
          ),
          MetricCard(
            label: l.stockValue,
            value: money(store.inventoryValue),
            icon: Icons.inventory_2_outlined,
          ),
        ],
      ),
      const SizedBox(height: 24),
      SurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeading(l.stockByCategory),
            const SizedBox(height: 20),
            for (final category in ProductCategory.values)
              Padding(
                padding: const EdgeInsets.only(bottom: 20),
                child: Builder(
                  builder: (context) {
                    final quantity = store.products
                        .where((p) => p.category == category)
                        .fold(0, (sum, p) => sum + store.stock(p));
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${categoryLabel(l, category)} · $quantity'),
                        const SizedBox(height: 8),
                        LinearProgressIndicator(
                          value: store.unitCount == 0
                              ? 0
                              : quantity / store.unitCount,
                          minHeight: 8,
                          borderRadius: BorderRadius.circular(4),
                          color: AppColors.blue,
                          backgroundColor: AppColors.tint,
                        ),
                      ],
                    );
                  },
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 24),
      ActivityPanel(store: store),
    ];
  }

  List<Widget> _administration(BuildContext context) {
    final l = strings(context);
    return [
      SurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeading(l.preferences),
            const SizedBox(height: 20),
            Text(
              l.language,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: Text(l.languageRussian),
                  selected: languageCode == 'ru',
                  onSelected: (_) => onLanguageChanged('ru'),
                ),
                ChoiceChip(
                  label: Text(l.languageTurkmen),
                  selected: languageCode == 'tk',
                  onSelected: (_) => onLanguageChanged('tk'),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              l.translationsPending,
              style: const TextStyle(color: AppColors.muted, height: 1.5),
            ),
            const SizedBox(height: 12),
            Text(
              l.sampleCurrency,
              style: const TextStyle(color: AppColors.muted, fontSize: 13),
            ),
          ],
        ),
      ),
      const SizedBox(height: 24),
      SurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeading(l.locations),
            const SizedBox(height: 12),
            for (final id in DemoStore.locationIds)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(
                  Icons.storefront_outlined,
                  color: AppColors.blue,
                ),
                title: Text(locationLabel(l, id)),
                subtitle: Text(
                  '${l.stockUnits}: ${store.products.fold(0, (sum, p) => sum + store.stock(p, id))}',
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 24),
      SurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeading(l.prototypeScope),
            const SizedBox(height: 16),
            Text(l.demoDetails, style: const TextStyle(height: 1.5)),
            const SizedBox(height: 16),
            Text(
              l.demoRoleNotice,
              style: const TextStyle(color: AppColors.muted, height: 1.5),
            ),
            const SizedBox(height: 16),
            for (final label in [
              l.importExport,
              l.backup,
              l.permissions,
              l.documentLanguage,
            ])
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.lock_outline, color: AppColors.muted),
                title: Text(label),
                subtitle: Text(l.backendPending),
              ),
          ],
        ),
      ),
      const SizedBox(height: 24),
      ActivityPanel(store: store),
    ];
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(24),
    children: switch (page) {
      AppPage.purchasing => _purchasing(context),
      AppPage.expenses => _expenses(context),
      AppPage.warranties => _warranties(context),
      AppPage.reports => _reports(context),
      _ => _administration(context),
    },
  );
}

class ExpenseDialog extends StatefulWidget {
  const ExpenseDialog({super.key, required this.store});
  final DemoStore store;
  @override
  State<ExpenseDialog> createState() => _ExpenseDialogState();
}

class _ExpenseDialogState extends State<ExpenseDialog> {
  final _label = TextEditingController();
  final _amount = TextEditingController();
  final _form = GlobalKey<FormState>();

  @override
  void dispose() {
    _label.dispose();
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = strings(context);
    return AlertDialog(
      title: Text(l.newExpense),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  key: const ValueKey('expense-description'),
                  controller: _label,
                  decoration: InputDecoration(labelText: l.expenseDescription),
                  validator: (s) =>
                      s == null || s.trim().isEmpty ? l.requiredField : null,
                ),
                const SizedBox(height: 20),
                TextFormField(
                  key: const ValueKey('expense-amount'),
                  controller: _amount,
                  decoration: InputDecoration(labelText: '${l.amount} · TMT'),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  validator: (s) =>
                      (parseMinor(s ?? '') ?? 0) <= 0 ? l.validAmount : null,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.cancel),
        ),
        FilledButton(
          onPressed: () {
            if (!_form.currentState!.validate()) return;
            widget.store.addExpense(_label.text, parseMinor(_amount.text)!);
            Navigator.pop(context);
            showFeedback(context, l.operationSaved);
          },
          child: Text(l.save),
        ),
      ],
    );
  }
}
