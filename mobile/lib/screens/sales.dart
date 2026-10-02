import 'package:flutter/material.dart';

import '../demo/demo_store.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import 'products.dart';

class SalesScreen extends StatefulWidget {
  const SalesScreen({super.key, required this.store});
  final DemoStore store;

  @override
  State<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends State<SalesScreen> {
  final _search = TextEditingController();
  bool _showReturns = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _add(Product p) {
    if (!widget.store.addToCart(p)) {
      showFeedback(context, strings(context).notEnoughStock);
    }
  }

  Future<void> _checkout() async {
    final l = strings(context);
    if (!await confirmAction(
          context,
          l.checkoutTitle,
          '${l.checkoutNotice}\n\n${l.subtotal}: ${money(widget.store.cartTotal)}',
        ) ||
        !mounted) {
      return;
    }
    final sale = widget.store.checkout();
    showFeedback(
      context,
      sale == null ? l.notEnoughStock : '${l.saleCompleted} · ${sale.id}',
    );
  }

  Widget _catalog() {
    final l = strings(context);
    final query = _search.text.trim().toLowerCase();
    final products = widget.store.products
        .where(
          (p) => '${p.name} ${p.sku} ${p.barcode} ${p.brand}'
              .toLowerCase()
              .contains(query),
        )
        .toList();
    return Column(
      children: [
        TextField(
          key: const ValueKey('sales-search'),
          controller: _search,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: l.searchProducts,
            prefixIcon: const Icon(Icons.search),
          ),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: () async {
              final code = await barcodeDialog(context);
              if (code == null || !mounted) return;
              final matches = widget.store.products
                  .where((p) => p.barcode == code)
                  .toList();
              if (matches.isEmpty) {
                showFeedback(context, l.notFound);
                return;
              }
              _add(matches.first);
            },
            icon: const Icon(Icons.qr_code_scanner),
            label: Text(l.scan),
          ),
        ),
        const SizedBox(height: 16),
        if (products.isEmpty)
          EmptyState(title: l.noResults, subtitle: l.noResultsHint),
        for (final p in products)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: SurfaceCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
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
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              '${p.brand} · ${p.sku}',
                              style: const TextStyle(
                                color: AppColors.muted,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 16,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        money(p.priceMinor),
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        '${l.available}: ${widget.store.stock(p) - (widget.store.cart[p.id] ?? 0)}',
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 13,
                        ),
                      ),
                      FilledButton.icon(
                        key: ValueKey('add-${p.id}'),
                        onPressed:
                            widget.store.stock(p) >
                                (widget.store.cart[p.id] ?? 0)
                            ? () => _add(p)
                            : null,
                        icon: const Icon(Icons.add, size: 18),
                        label: Text(l.add),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _cart() {
    final l = strings(context);
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeading('${l.cart} · ${widget.store.cartCount}'),
          const SizedBox(height: 8),
          Text(
            locationLabel(l, widget.store.location),
            style: const TextStyle(color: AppColors.muted, fontSize: 13),
          ),
          const SizedBox(height: 20),
          if (widget.store.cart.isEmpty)
            EmptyState(
              title: l.emptyCart,
              subtitle: l.emptyCartHint,
              icon: Icons.shopping_bag_outlined,
            ),
          for (final entry in widget.store.cart.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.store.product(entry.key).name,
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      IconButton(
                        tooltip: l.remove,
                        onPressed: () => widget.store.removeFromCart(
                          widget.store.product(entry.key),
                        ),
                        icon: const Icon(Icons.remove_circle_outline),
                      ),
                      Text(
                        '${entry.value}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      IconButton(
                        tooltip: l.increase,
                        onPressed: () => _add(widget.store.product(entry.key)),
                        icon: const Icon(Icons.add_circle_outline),
                      ),
                      Text(
                        money(
                          widget.store.product(entry.key).priceMinor *
                              entry.value,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          const Divider(),
          const SizedBox(height: 20),
          Text(l.subtotal, style: const TextStyle(color: AppColors.muted)),
          const SizedBox(height: 8),
          Text(
            money(widget.store.cartTotal),
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: GradientButton(
              key: const ValueKey('checkout'),
              label: l.checkout,
              icon: Icons.check,
              onPressed: widget.store.cart.isEmpty ? null : _checkout,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            l.checkoutNotice,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.muted,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _returns() {
    final l = strings(context);
    if (widget.store.sales.isEmpty) {
      return SurfaceCard(
        child: EmptyState(
          title: l.noSales,
          icon: Icons.assignment_return_outlined,
        ),
      );
    }
    return Column(
      children: [
        for (final sale in widget.store.sales)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: SurfaceCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(sale.id, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text(
                    '${locationLabel(l, sale.location)} · ${money(sale.totalMinor)}',
                    style: const TextStyle(color: AppColors.muted),
                  ),
                  const SizedBox(height: 16),
                  for (final entry in sale.items.entries)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(widget.store.product(entry.key).name),
                          const SizedBox(height: 8),
                          OutlinedButton(
                            onPressed:
                                widget.store.returnable(sale, entry.key) > 0
                                ? () => refundDialog(
                                    context,
                                    widget.store,
                                    sale,
                                    entry.key,
                                  )
                                : null,
                            child: Text(
                              '${l.refund} · ${widget.store.returnable(sale, entry.key)}',
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = strings(context);
    return LayoutBuilder(
      builder: (context, constraints) => ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: Text(l.newSale),
                selected: !_showReturns,
                onSelected: (_) => setState(() => _showReturns = false),
              ),
              ChoiceChip(
                label: Text(l.returns),
                selected: _showReturns,
                onSelected: (_) => setState(() => _showReturns = true),
              ),
            ],
          ),
          const SizedBox(height: 24),
          if (_showReturns)
            _returns()
          else if (constraints.maxWidth >= 850 &&
              MediaQuery.textScalerOf(context).scale(1) < 1.7)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 3, child: _catalog()),
                const SizedBox(width: 24),
                Expanded(flex: 2, child: _cart()),
              ],
            )
          else ...[
            _cart(),
            const SizedBox(height: 24),
            _catalog(),
          ],
        ],
      ),
    );
  }
}

Future<void> refundDialog(
  BuildContext context,
  DemoStore store,
  DemoSale sale,
  String productId,
) async {
  final l = strings(context);
  final form = GlobalKey<FormState>();
  var sellable = true;
  String? error;
  await showDialog<void>(
    context: context,
    builder: (context) => DialogInput(
      initialText: '1',
      builder: (context, controller) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(l.refund),
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
              child: Form(
                key: form,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(store.product(productId).name),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: controller,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(labelText: l.quantity),
                      validator: (text) {
                        final n = int.tryParse(text ?? '');
                        return n == null ||
                                n <= 0 ||
                                n > store.returnable(sale, productId)
                            ? l.validQuantity
                            : null;
                      },
                    ),
                    const SizedBox(height: 12),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: sellable,
                      title: Text(l.sellable),
                      onChanged: (value) => setState(() => sellable = value!),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      l.refundNotice,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.muted,
                      ),
                    ),
                    if (error != null)
                      Text(
                        error!,
                        style: const TextStyle(color: AppColors.danger),
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
                if (!form.currentState!.validate()) return;
                if (!store.refund(
                  sale,
                  productId,
                  int.parse(controller.text),
                  sellable: sellable,
                )) {
                  setState(() => error = l.validQuantity);
                  return;
                }
                Navigator.pop(context);
                showFeedback(context, l.operationSaved);
              },
              child: Text(l.confirm),
            ),
          ],
        ),
      ),
    ),
  );
}
