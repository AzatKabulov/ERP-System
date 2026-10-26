import 'dart:async';

import 'package:flutter/material.dart';
import '../../widgets/app_icons.dart';
import '../inventory/quantity_input.dart';

import '../../core/api/api_error_text.dart';
import '../../core/api/api_exception.dart';
import '../../core/files/file_services.dart';
import '../../core/money/decimal_math.dart';
import '../../core/session/session_controller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../scanning/barcode_input.dart';
import '../shared/async_section.dart';
import '../workspace/unsaved_work.dart';
import 'catalog_models.dart';
import 'catalog_repository.dart';
import 'csv_import_screen.dart';
import 'product_detail_screen.dart';
import 'product_photo.dart';
import 'product_stock_info.dart';
import 'product_form_screen.dart';

/// The product catalog: search by name, SKU, brand or barcode (typed or scanned),
/// browse, open, add. Reads only what the server returns for this business.
class CatalogScreen extends StatefulWidget {
  const CatalogScreen({
    super.key,
    required this.session,
    required this.repository,
    required this.unsaved,
    this.onOpenToComplete,
  });

  final SessionController session;
  final CatalogRepository repository;
  final UnsavedWork unsaved;

  /// Opens the list of products that still need a price or a cost.
  final VoidCallback? onOpenToComplete;

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
  String? _expiryFilter;
  String? _categoryId;
  List<NamedRef> _categories = const [];
  int _requestId = 0; // answers to out-of-date searches are ignored
  String? _scannedCode; // the code that produced the current results

  static const _viewKey = 'catalog_view';

  /// Gallery (several products across) or the plain list; remembered on this device.
  late bool _gallery = widget.session.preferences.getString(_viewKey) != 'list';

  bool get _canManage => widget.session.can('catalog.manage');

  void _setGallery(bool value) {
    setState(() => _gallery = value);
    widget.session.preferences.setString(_viewKey, value ? 'gallery' : 'list');
  }

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
        expiry: _expiryFilter,
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

  bool _exporting = false;

  Future<void> _import() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => CsvImportScreen(repository: widget.repository),
      ),
    );
    if (mounted) _load(reset: true);
  }

  Future<void> _export() async {
    setState(() => _exporting = true);
    final l = strings(context);
    try {
      final bytes = await widget.repository.exportCsv();
      if (!mounted) return;
      await FilesScope.sharingOf(
        context,
      ).share(bytes, 'products.csv', 'text/csv');
      if (mounted) showFeedback(context, l.catalogExported);
    } on ApiException catch (e) {
      if (mounted) showFeedback(context, apiErrorText(l, e));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
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
    return LayoutBuilder(
      builder: (context, constraints) =>
          _page(context, constraints.maxWidth < 600, constraints.maxWidth),
    );
  }

  Widget _page(BuildContext context, bool compact, double width) {
    final l = strings(context);
    final searching =
        _search.text.trim().isNotEmpty ||
        _categoryId != null ||
        _archived ||
        _expiryFilter != null;
    final search = BarcodeInput(
      fieldKey: const ValueKey('catalog-search'),
      controller: _search,
      label: l.searchProducts,
      onChanged: _onSearchChanged,
      onSubmitted: (_) {
        _debounce?.cancel();
        _load(reset: true);
      },
      onScanned: _onScanned,
    );
    final add = _canManage
        ? PrimaryButton(
            key: const ValueKey('catalog-add'),
            label: l.addProduct,
            icon: AppIcons.plus,
            onPressed: () => _add(),
          )
        : null;
    final hasSecondary =
        (_canManage && widget.onOpenToComplete != null) ||
        widget.session.can('catalog.import') ||
        widget.session.can('catalog.export');
    final secondary = <Widget>[
      if (_canManage && widget.onOpenToComplete != null)
        OutlinedButton.icon(
          key: const ValueKey('catalog-to-complete'),
          onPressed: widget.onOpenToComplete,
          icon: const AppIcon(AppIcons.edit, size: 20),
          label: Text(l.toCompleteTitle),
        ),
      if (widget.session.can('catalog.import'))
        OutlinedButton.icon(
          key: const ValueKey('catalog-import'),
          onPressed: _import,
          icon: const AppIcon(AppIcons.upload, size: 20),
          label: Text(l.catalogImport),
        ),
      if (widget.session.can('catalog.export'))
        OutlinedButton.icon(
          key: const ValueKey('catalog-export'),
          onPressed: _exporting ? null : _export,
          icon: const AppIcon(AppIcons.download, size: 20),
          label: Text(l.catalogExport),
        ),
    ];
    final more = PopupMenuButton<String>(
      key: const ValueKey('catalog-more'),
      tooltip: l.menu,
      icon: const AppIcon(AppIcons.dots),
      onSelected: (value) => switch (value) {
        'complete' => widget.onOpenToComplete?.call(),
        'import' => _import(),
        _ => _exporting ? null : _export(),
      },
      itemBuilder: (context) => [
        if (_canManage && widget.onOpenToComplete != null)
          PopupMenuItem(
            key: const ValueKey('catalog-to-complete'),
            value: 'complete',
            child: Text(l.toCompleteTitle),
          ),
        if (widget.session.can('catalog.import'))
          PopupMenuItem(
            key: const ValueKey('catalog-import'),
            value: 'import',
            child: Text(l.catalogImport),
          ),
        if (widget.session.can('catalog.export'))
          PopupMenuItem(
            key: const ValueKey('catalog-export'),
            value: 'export',
            child: Text(l.catalogExport),
          ),
      ],
    );
    final toggle = AppSegmented<bool>(
      key: const ValueKey('catalog-view-toggle'),
      options: [(true, l.viewGallery), (false, l.viewList)],
      value: _gallery,
      onChanged: _setGallery,
    );
    final chips = _chipRow([
      if (widget.session.can('stock.view')) ...[
        for (final mode in ['soon', 'expired'])
          FilterChip(
            key: ValueKey('catalog-expiry-$mode'),
            label: Text(
              mode == 'soon' ? l.expirySoonFilter : l.expiryExpiredFilter,
            ),
            selected: _expiryFilter == mode,
            onSelected: (selected) {
              _expiryFilter = selected ? mode : null;
              _load(reset: true);
            },
          ),
      ],
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
    ]);
    return ListView(
      padding: EdgeInsets.fromLTRB(
        compact ? 16 : 32,
        compact ? 20 : 32,
        compact ? 16 : 32,
        40,
      ),
      children: [
        PageHead(
          title: l.products,
          actions: compact
              ? [?add, if (hasSecondary) more]
              : [...secondary, ?add],
        ),
        const SizedBox(height: 24),
        if (compact) ...[
          search,
          const SizedBox(height: 12),
          Align(alignment: Alignment.centerLeft, child: toggle),
          const SizedBox(height: 12),
          chips,
        ] else if (width - 64 >= 1000)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 420, child: search),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: chips,
                ),
              ),
              const SizedBox(width: 12),
              toggle,
            ],
          )
        else ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: search),
              const SizedBox(width: 12),
              toggle,
            ],
          ),
          const SizedBox(height: 12),
          chips,
        ],
        const SizedBox(height: 20),
        if (_items.any(
          (p) => p.expiryStatus == 'soon' || p.expiryStatus == 'expired',
        ))
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              l.expiryAttention,
              key: const ValueKey('catalog-expiry-alert'),
              style: const TextStyle(color: AppColors.warning),
            ),
          ),
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
                        icon: AppIcons.qr,
                      ),
                      OutlinedButton.icon(
                        key: const ValueKey('catalog-add-scanned'),
                        onPressed: () => _add(barcode: _scannedCode),
                        icon: const AppIcon(AppIcons.plus),
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
                    icon: AppIcons.overview,
                  ),
          )
        else ...[
          if (_gallery)
            ..._galleryRows(width - (compact ? 32 : 64))
          else if (compact)
            for (final product in _items)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _ProductTile(
                  product: product,
                  repository: widget.repository,
                  onTap: () => _open(product),
                ),
              )
          else
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: _ProductTable(
                products: _items,
                repository: widget.repository,
                onOpen: _open,
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

  // Each row is a separate lazy ListView child. One giant gallery child builds,
  // intrinsically lays out and downloads pictures for every offscreen product.
  Iterable<Widget> _galleryRows(double contentWidth) sync* {
    final columns = ((contentWidth + 16) / 186).floor().clamp(2, 5);
    for (var start = 0; start < _items.length; start += columns) {
      yield Padding(
        key: start == 0 ? const ValueKey('catalog-gallery') : null,
        padding: const EdgeInsets.only(bottom: 16),
        child: _ProductGalleryRow(
          products: _items.skip(start).take(columns).toList(),
          columns: columns,
          onOpen: _open,
          repository: widget.repository,
        ),
      );
    }
  }
}

class _ProductTile extends StatelessWidget {
  const _ProductTile({
    required this.product,
    required this.repository,
    required this.onTap,
  });
  final Product product;
  final CatalogRepository repository;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = product;
    return SurfaceCard(
      key: ValueKey('product-${p.sku}'),
      onTap: onTap,
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
                ProductPhoto(
                  product: p,
                  repository: repository,
                  width: 56,
                  height: 56,
                ),
                const SizedBox(width: 14),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 2),
                      _SkuLine(product: p),
                    ],
                  ),
                ),
              ],
            ),
          ),
          _PriceInfo(product: p, align: CrossAxisAlignment.end),
        ],
      ),
    );
  }
}

/// The SKU in the monospace face (so similar codes are easy to tell apart), then the brand.
class _SkuLine extends StatelessWidget {
  const _SkuLine({required this.product});
  final Product product;

  @override
  Widget build(BuildContext context) => Text.rich(
    TextSpan(
      children: [
        TextSpan(
          text: product.sku,
          style: const TextStyle(
            fontFamily: AppFonts.mono,
            fontSize: 12,
            letterSpacing: 0.2,
          ),
        ),
        if (product.brand != null) TextSpan(text: ' · ${product.brand!.name}'),
      ],
    ),
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: const TextStyle(color: AppColors.muted, fontSize: 13),
  );
}

/// The price of a product (and, for a USD price, what it is in TMT) with the archived mark.
class _PriceInfo extends StatelessWidget {
  const _PriceInfo({required this.product, required this.align});
  final Product product;
  final CrossAxisAlignment align;

  @override
  Widget build(BuildContext context) {
    final l = strings(context);
    final p = product;
    return Column(
      crossAxisAlignment: align,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (p.onHandMilli != null || p.expiryDate != null) ...[
          const SizedBox(height: 6),
          ProductStockInfo(product: p),
        ],
        Text(
          formatMoney(p.priceMinor, p.priceCurrency),
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 16,
            letterSpacing: -0.2,
            fontFeatures: AppFonts.tabular,
          ),
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
        if (!p.isActive) ...[
          const SizedBox(height: 4),
          StatusPill(label: l.archivedLabel, warning: true),
        ],
      ],
    );
  }
}

/// Products as cards, several across (four or five on a tablet), instead of one long list.
class _ProductGalleryRow extends StatelessWidget {
  const _ProductGalleryRow({
    required this.products,
    required this.columns,
    required this.onOpen,
    required this.repository,
  });
  final List<Product> products;
  final int columns;
  final void Function(Product) onOpen;
  final CatalogRepository repository;

  @override
  Widget build(BuildContext context) => IntrinsicHeight(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var j = 0; j < columns; j++) ...[
          if (j > 0) const SizedBox(width: 16),
          Expanded(
            child: j < products.length
                ? _ProductCard(
                    product: products[j],
                    repository: repository,
                    onTap: () => onOpen(products[j]),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ],
    ),
  );
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({
    required this.product,
    required this.repository,
    required this.onTap,
  });
  final Product product;
  final CatalogRepository repository;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = product;
    return SurfaceCard(
      key: ValueKey('product-${p.sku}'),
      onTap: onTap,
      padding: 12,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ProductPhoto(
            product: p,
            repository: repository,
            aspectRatio: 4 / 3,
            iconSize: 32,
          ),
          const SizedBox(height: 12),
          Text(
            p.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 15,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 4),
          _SkuLine(product: p),
          const Spacer(),
          const SizedBox(height: 10),
          _PriceInfo(product: p, align: CrossAxisAlignment.start),
        ],
      ),
    );
  }
}

/// Filter chips: one row that scrolls sideways, so many categories never push the products
/// down the screen.
Widget _chipRow(List<Widget> chips) => SizedBox(
  height: 48,
  child: SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(
      children: [
        for (final chip in chips)
          Padding(padding: const EdgeInsets.only(right: 8), child: chip),
      ],
    ),
  ),
);

/// The list view of the catalog on a wide screen: a header row and one row per product.
class _ProductTable extends StatelessWidget {
  const _ProductTable({
    required this.products,
    required this.repository,
    required this.onOpen,
  });
  final List<Product> products;
  final CatalogRepository repository;
  final void Function(Product) onOpen;

  static const _header = TextStyle(
    color: AppColors.muted,
    fontSize: 11,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.7,
  );

  @override
  Widget build(BuildContext context) {
    final l = strings(context);
    final showStock = products.any((p) => p.onHandMilli != null);
    Widget cell(
      int flex,
      Widget child, {
      Alignment align = Alignment.centerLeft,
    }) => Expanded(
      flex: flex,
      child: Align(alignment: align, child: child),
    );
    return SurfaceCard(
      padding: 0,
      child: Column(
        key: const ValueKey('catalog-table'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            color: AppColors.surfaceSoft,
            child: Row(
              children: [
                cell(60, Text(l.sku.toUpperCase(), style: _header)),
                cell(128, Text(l.productName.toUpperCase(), style: _header)),
                cell(53, Text(l.category.toUpperCase(), style: _header)),
                cell(
                  53,
                  Text(l.price.toUpperCase(), style: _header),
                  align: Alignment.centerRight,
                ),
                if (showStock) ...[
                  cell(
                    53,
                    Text(l.productColumnStock.toUpperCase(), style: _header),
                    align: Alignment.centerRight,
                  ),
                  cell(
                    53,
                    Padding(
                      padding: const EdgeInsets.only(left: 16),
                      child: Text(
                        l.productColumnStatus.toUpperCase(),
                        style: _header,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          for (final p in products)
            InkWell(
              key: ValueKey('product-${p.sku}'),
              onTap: () => onOpen(p),
              hoverColor: AppColors.surfaceSoft,
              child: Container(
                constraints: const BoxConstraints(minHeight: 64),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: AppColors.line)),
                ),
                child: Row(
                  children: [
                    cell(
                      60,
                      Text(
                        p.sku,
                        style: const TextStyle(
                          fontFamily: AppFonts.mono,
                          fontSize: 13,
                          letterSpacing: -0.3,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 128,
                      child: Row(
                        children: [
                          ProductPhoto(
                            product: p,
                            repository: repository,
                            width: 44,
                            height: 44,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  p.name,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                  ),
                                ),
                                ProductStockInfo(
                                  product: p,
                                  showQuantity: false,
                                ),
                                if (p.barcodes.isNotEmpty)
                                  Text(
                                    p.barcodes.first,
                                    style: const TextStyle(
                                      fontFamily: AppFonts.mono,
                                      fontSize: 12,
                                      color: AppColors.muted,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    cell(
                      53,
                      Text(
                        [?p.category?.name, ?p.brand?.name].join(' · '),
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    cell(
                      53,
                      _PriceInfo(product: p, align: CrossAxisAlignment.end),
                      align: Alignment.centerRight,
                    ),
                    if (showStock) ...[
                      cell(
                        53,
                        Text(
                          p.onHandMilli == null
                              ? ''
                              : quantityWithUnit(p.onHandMilli!, p.unit),
                          style: const TextStyle(fontSize: 13),
                        ),
                        align: Alignment.centerRight,
                      ),
                      cell(
                        53,
                        Padding(
                          padding: const EdgeInsets.only(left: 16),
                          child: _StockBadge(product: p),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// In stock, low (under the minimum) or out of stock, with an icon and a word.
class _StockBadge extends StatelessWidget {
  const _StockBadge({required this.product});
  final Product product;

  @override
  Widget build(BuildContext context) {
    final l = strings(context);
    final onHand = product.onHandMilli;
    if (onHand == null) return const SizedBox.shrink();
    if (onHand <= 0) {
      return StatusPill(
        label: l.productOut,
        tone: StatusTone.danger,
        icon: AppIcons.warning,
      );
    }
    if ((product.minimumMilli ?? 0) > 0 && onHand < product.minimumMilli!) {
      return StatusPill(
        label: l.productLow,
        tone: StatusTone.warning,
        icon: AppIcons.warning,
      );
    }
    return StatusPill(
      label: l.productInStock,
      tone: StatusTone.success,
      icon: AppIcons.check,
    );
  }
}
