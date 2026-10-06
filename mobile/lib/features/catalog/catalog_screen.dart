import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/money/decimal_math.dart';
import '../../core/session/session_controller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../scanning/barcode_input.dart';
import '../shared/async_section.dart';
import '../workspace/unsaved_work.dart';
import 'catalog_models.dart';
import 'catalog_repository.dart';
import 'product_detail_screen.dart';
import 'product_form_screen.dart';

/// The product catalog: search by name, SKU, brand or barcode (typed or scanned),
/// browse, open, add. Reads only what the server returns for this business.
class CatalogScreen extends StatefulWidget {
  const CatalogScreen({
    super.key,
    required this.session,
    required this.repository,
    required this.unsaved,
  });

  final SessionController session;
  final CatalogRepository repository;
  final UnsavedWork unsaved;

  @override
  State<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends State<CatalogScreen> {
  static const _pageSize = 30;

  final _search = TextEditingController();
  Timer? _debounce;
  List<Product> _items = const [];
  int _count = 0;
  bool _loading = true;
  Object? _error;
  bool _archived = false;
  String? _categoryId;
  List<NamedRef> _categories = const [];
  int _requestId = 0; // answers to out-of-date searches are ignored
  String? _scannedCode; // the code that produced the current results

  bool get _canManage => widget.session.can('catalog.manage');

  @override
  void initState() {
    super.initState();
    _load(reset: true);
    widget.repository.categories().then((items) {
      if (mounted) setState(() => _categories = items);
    }, onError: (_) {});
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({required bool reset}) async {
    final request = ++_requestId;
    setState(() {
      _loading = true;
      _error = null;
      if (reset) _items = const [];
    });
    try {
      final page = await widget.repository.products(
        query: _search.text,
        categoryId: _categoryId,
        archived: _archived,
        offset: reset ? 0 : _items.length,
        limit: _pageSize,
      );
      if (!mounted || request != _requestId) return;
      setState(() {
        _items = reset ? page.items : [..._items, ...page.items];
        _count = page.count;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || request != _requestId) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  void _onSearchChanged(String _) {
    _scannedCode = null;
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 350),
      () => _load(reset: true),
    );
  }

  void _onScanned(String code) {
    _debounce?.cancel();
    _scannedCode = code;
    _load(reset: true);
  }

  Future<void> _open(Product product) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ProductDetailScreen(
          product: product,
          repository: widget.repository,
          session: widget.session,
          unsaved: widget.unsaved,
        ),
      ),
    );
    if (changed == true && mounted) _load(reset: true);
  }

  Future<void> _add({String? barcode}) async {
    final saved = await Navigator.of(context).push<Product>(
      MaterialPageRoute(
        builder: (_) => ProductFormScreen(
          repository: widget.repository,
          session: widget.session,
          unsaved: widget.unsaved,
          initialBarcode: barcode,
        ),
      ),
    );
    if (saved != null && mounted) {
      showFeedback(context, strings(context).productSaved);
      _load(reset: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = strings(context);
    final searching =
        _search.text.trim().isNotEmpty || _categoryId != null || _archived;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.start,
          children: [
            SizedBox(
              width: 440,
              child: BarcodeInput(
                fieldKey: const ValueKey('catalog-search'),
                controller: _search,
                label: l.searchProducts,
                onChanged: _onSearchChanged,
                onSubmitted: (_) {
                  _debounce?.cancel();
                  _load(reset: true);
                },
                onScanned: _onScanned,
              ),
            ),
            if (_canManage)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: GradientButton(
                  key: const ValueKey('catalog-add'),
                  label: l.addProduct,
                  icon: Icons.add,
                  onPressed: () => _add(),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ChoiceChip(
              label: Text(l.allCategories),
              selected: _categoryId == null,
              onSelected: (_) {
                _categoryId = null;
                _load(reset: true);
              },
            ),
            for (final category in _categories)
              ChoiceChip(
                key: ValueKey('catalog-category-${category.name}'),
                label: Text(category.name),
                selected: _categoryId == category.id,
                onSelected: (_) {
                  _categoryId = category.id;
                  _load(reset: true);
                },
              ),
            FilterChip(
              key: const ValueKey('catalog-archived-toggle'),
              label: Text(l.showArchived),
              selected: _archived,
              onSelected: (value) {
                _archived = value;
                _load(reset: true);
              },
            ),
          ],
        ),
        const SizedBox(height: 20),
        if (_error != null)
          ErrorPanel(error: _error!, onRetry: () => _load(reset: true))
        else if (_loading && _items.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_items.isEmpty)
          SurfaceCard(
            child: _scannedCode != null && _canManage
                ? Column(
                    children: [
                      EmptyState(
                        title: l.errorBarcodeNotFound,
                        subtitle: l.scannedCode(_scannedCode!),
                        icon: Icons.qr_code_2,
                      ),
                      OutlinedButton.icon(
                        key: const ValueKey('catalog-add-scanned'),
                        onPressed: () => _add(barcode: _scannedCode),
                        icon: const Icon(Icons.add),
                        label: Text(l.addProduct),
                      ),
                    ],
                  )
                : searching
                ? EmptyState(title: l.noResults, subtitle: l.noResultsHint)
                : EmptyState(
                    key: const ValueKey('catalog-empty'),
                    title: l.noProducts,
                    subtitle: l.noProductsHint,
                    icon: Icons.category_outlined,
                  ),
          )
        else ...[
          for (final product in _items)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _ProductTile(
                product: product,
                onTap: () => _open(product),
              ),
            ),
          if (_items.length < _count)
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton(
                key: const ValueKey('catalog-load-more'),
                onPressed: _loading ? null : () => _load(reset: false),
                child: Text(l.loadMore),
              ),
            ),
        ],
      ],
    );
  }
}

class _ProductTile extends StatelessWidget {
  const _ProductTile({required this.product, required this.onTap});
  final Product product;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = strings(context);
    final p = product;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: ValueKey('product-${p.sku}'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: SurfaceCard(
          padding: 16,
          child: Wrap(
            spacing: 16,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            alignment: WrapAlignment.spaceBetween,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 200, maxWidth: 560),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: AppColors.tint,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.inventory_2_outlined,
                        color: AppColors.blue,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            p.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            [p.sku, ?p.brand?.name].join(' · '),
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
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    formatMoney(p.priceMinor, p.priceCurrency),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  if (p.priceCurrency != 'TMT')
                    Text(
                      p.priceTmtMinor != null
                          ? l.priceInTmt(formatMoney(p.priceTmtMinor!, 'TMT'))
                          : l.rateMissingNote,
                      style: TextStyle(
                        fontSize: 12,
                        color: p.priceTmtMinor != null
                            ? AppColors.muted
                            : AppColors.warning,
                      ),
                    ),
                  if (!p.isActive)
                    StatusPill(label: l.archivedLabel, warning: true),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
