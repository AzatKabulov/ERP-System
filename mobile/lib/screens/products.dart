import 'package:flutter/material.dart';

import '../demo/demo_store.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

class ProductsScreen extends StatefulWidget {
  const ProductsScreen({
    super.key,
    required this.store,
    this.inventory = false,
  });
  final DemoStore store;
  final bool inventory;

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  final _search = TextEditingController();
  ProductCategory? _category;
  bool _onlyLow = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = strings(context);
    final query = _search.text.trim().toLowerCase();
    final products = widget.store.products
        .where(
          (p) =>
              (_category == null || p.category == _category) &&
              (!_onlyLow || widget.store.stock(p) < p.minimum) &&
              '${p.name} ${p.sku} ${p.barcode} ${p.brand}'
                  .toLowerCase()
                  .contains(query),
        )
        .toList();
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 340,
              child: TextField(
                key: const ValueKey('product-search'),
                controller: _search,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: l.searchProducts,
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _search.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: l.clearSearch,
                          icon: const Icon(Icons.close),
                          onPressed: () => setState(_search.clear),
                        ),
                ),
              ),
            ),
            OutlinedButton.icon(
              onPressed: () async {
                final code = await barcodeDialog(context);
                if (code != null && mounted) {
                  setState(() => _search.text = code);
                }
              },
              icon: const Icon(Icons.qr_code_scanner),
              label: Text(l.scan),
            ),
            if (widget.inventory)
              FilterChip(
                label: Text(l.lowStock),
                selected: _onlyLow,
                onSelected: (value) => setState(() => _onlyLow = value),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ChoiceChip(
              label: Text(l.allCategories),
              selected: _category == null,
              onSelected: (_) => setState(() => _category = null),
            ),
            for (final category in ProductCategory.values)
              ChoiceChip(
                label: Text(categoryLabel(l, category)),
                selected: _category == category,
                onSelected: (_) => setState(() => _category = category),
              ),
          ],
        ),
        const SizedBox(height: 24),
        if (widget.inventory) ...[
          Text(
            l.reorderHint,
            style: const TextStyle(color: AppColors.muted, height: 1.5),
          ),
          const SizedBox(height: 20),
        ],
        if (products.isEmpty)
          SurfaceCard(
            child: EmptyState(
              title: l.noResults,
              subtitle: l.noResultsHint,
              icon: Icons.search_off,
            ),
          ),
        for (final product in products)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: SurfaceCard(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final stock = widget.store.stock(product);
                  final details = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${product.sku} · ${product.brand} · ${l.shelf} ${product.shelf}',
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.muted,
                        ),
                      ),
                    ],
                  );
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ProductMark(product: product),
                          const SizedBox(width: 16),
                          Expanded(child: details),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 16,
                        runSpacing: 12,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            money(product.priceMinor),
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          StatusPill(
                            label: '${l.available}: $stock',
                            warning: stock < product.minimum,
                          ),
                          if (widget.inventory && stock < product.minimum)
                            Text(
                              '${l.suggestedOrder}: ${product.target - stock}',
                              style: const TextStyle(color: AppColors.warning),
                            ),
                          TextButton(
                            onPressed: () =>
                                productDetails(context, widget.store, product),
                            child: Text(l.productDetails),
                          ),
                        ],
                      ),
                      if (widget.inventory) ...[
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            OutlinedButton.icon(
                              key: ValueKey('receive-${product.id}'),
                              onPressed: () => stockDialog(
                                context,
                                widget.store,
                                product,
                                StockAction.receive,
                              ),
                              icon: const Icon(
                                Icons.add_box_outlined,
                                size: 18,
                              ),
                              label: Text(l.receive),
                            ),
                            OutlinedButton.icon(
                              onPressed: () => stockDialog(
                                context,
                                widget.store,
                                product,
                                StockAction.transfer,
                              ),
                              icon: const Icon(Icons.swap_horiz, size: 18),
                              label: Text(l.transfer),
                            ),
                            OutlinedButton.icon(
                              onPressed: () => stockDialog(
                                context,
                                widget.store,
                                product,
                                StockAction.count,
                              ),
                              icon: const Icon(
                                Icons.fact_check_outlined,
                                size: 18,
                              ),
                              label: Text(l.countStock),
                            ),
                          ],
                        ),
                      ],
                    ],
                  );
                },
              ),
            ),
          ),
      ],
    );
  }
}

Future<String?> barcodeDialog(BuildContext context) async {
  final l = strings(context);
  return showDialog<String>(
    context: context,
    builder: (context) => DialogInput(
      builder: (context, controller) => AlertDialog(
        title: Text(l.scan),
        content: SizedBox(
          width: 380,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(l.scanHint),
                const SizedBox(height: 20),
                TextField(
                  key: const ValueKey('barcode-input'),
                  autofocus: true,
                  controller: controller,
                  decoration: InputDecoration(labelText: l.barcode),
                  onSubmitted: (value) => Navigator.pop(context, value.trim()),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: Text(l.find),
          ),
        ],
      ),
    ),
  );
}

Future<void> productDetails(
  BuildContext context,
  DemoStore store,
  Product p,
) async {
  final l = strings(context);
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(p.name),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${l.sku}: ${p.sku}'),
              Text('${l.barcode}: ${p.barcode}'),
              Text('${l.brand}: ${p.brand}'),
              Text('${l.category}: ${categoryLabel(l, p.category)}'),
              Text('${l.price}: ${money(p.priceMinor)}'),
              const SizedBox(height: 20),
              for (final id in DemoStore.locationIds)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text('${locationLabel(l, id)}: ${store.stock(p, id)}'),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.close),
        ),
      ],
    ),
  );
}

enum StockAction { receive, transfer, count }

Future<void> stockDialog(
  BuildContext context,
  DemoStore store,
  Product p,
  StockAction action,
) async {
  final l = strings(context);
  final title = switch (action) {
    StockAction.receive => l.receive,
    StockAction.transfer => l.transfer,
    StockAction.count => l.countStock,
  };
  final key = GlobalKey<FormState>();
  var destination = DemoStore.locationIds.firstWhere(
    (id) => id != store.location,
  );
  String? error;
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => DialogInput(
      initialText: action == StockAction.count ? '${store.stock(p)}' : '1',
      builder: (context, controller) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
              child: Form(
                key: key,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.name,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    Text('${l.currentQuantity}: ${store.stock(p)}'),
                    const SizedBox(height: 20),
                    TextFormField(
                      key: const ValueKey('stock-quantity'),
                      controller: controller,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: action == StockAction.count
                            ? l.actualQuantity
                            : l.quantity,
                      ),
                      validator: (value) {
                        final number = int.tryParse(value?.trim() ?? '');
                        return number == null ||
                                number <
                                    (action == StockAction.count ? 0 : 1) ||
                                number > 999999
                            ? l.validQuantity
                            : null;
                      },
                    ),
                    if (action == StockAction.transfer) ...[
                      const SizedBox(height: 20),
                      DropdownButtonFormField<String>(
                        initialValue: destination,
                        isExpanded: true,
                        decoration: InputDecoration(labelText: l.destination),
                        items: DemoStore.locationIds
                            .where((id) => id != store.location)
                            .map(
                              (id) => DropdownMenuItem(
                                value: id,
                                child: Text(locationLabel(l, id)),
                              ),
                            )
                            .toList(),
                        onChanged: (id) => setState(() => destination = id!),
                      ),
                    ],
                    const SizedBox(height: 20),
                    Text(
                      l.stockActionNotice,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.muted,
                      ),
                    ),
                    if (error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        error!,
                        style: const TextStyle(color: AppColors.danger),
                      ),
                    ],
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
              key: const ValueKey('confirm-stock'),
              onPressed: () {
                if (!key.currentState!.validate()) return;
                final quantity = int.parse(controller.text.trim());
                final saved = switch (action) {
                  StockAction.receive => store.receive(p, quantity),
                  StockAction.transfer => store.transfer(
                    p,
                    quantity,
                    destination,
                  ),
                  StockAction.count => store.count(p, quantity),
                };
                if (!saved) {
                  setState(() => error = l.notEnoughStock);
                  return;
                }
                Navigator.pop(context);
                showFeedback(dialogContext, l.operationSaved);
              },
              child: Text(l.confirm),
            ),
          ],
        ),
      ),
    ),
  );
}
