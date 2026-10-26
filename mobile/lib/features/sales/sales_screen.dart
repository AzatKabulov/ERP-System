import 'dart:async';

import 'package:flutter/material.dart';
import '../../widgets/app_icons.dart';

import '../../core/connectivity/connection_monitor.dart';
import '../../core/money/decimal_math.dart';
import '../../core/operations/operation_runner.dart';
import '../../core/session/session_controller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../catalog/catalog_models.dart';
import '../catalog/catalog_repository.dart';
import '../catalog/product_photo.dart';
import '../inventory/inventory_repository.dart';
import '../inventory/quantity_input.dart';
import '../returns/returns_repository.dart';
import '../returns/returns_screen.dart';
import '../scanning/barcode_input.dart';
import '../shared/async_section.dart';
import '../workspace/unsaved_work.dart';
import 'cart_controller.dart';
import 'checkout_screen.dart';
import 'customer_picker.dart';
import 'document_buttons.dart';
import 'sales_history_screen.dart';
import 'sales_models.dart';
import 'sales_repository.dart';

/// Recording a sale: find or scan products, build a cart (which reserves no stock), set the
/// quantity and the price of every line (prices are not fixed: the seller charges what they
/// agree with the customer), pick an optional customer, and save. The sale itself is decided
/// by the server; this screen never shows success before the server confirms.
class SalesScreen extends StatefulWidget {
  const SalesScreen({
    super.key,
    required this.session,
    required this.catalog,
    required this.inventory,
    required this.repository,
    required this.runner,
    required this.monitor,
    required this.unsaved,
    required this.cart,
  });

  final SessionController session;
  final CatalogRepository catalog;
  final InventoryRepository inventory;
  final SalesRepository repository;
  final OperationRunner runner;
  final ConnectionMonitor monitor;
  final UnsavedWork unsaved;

  /// Owned by the workspace, so the cart survives switching pages and languages.
  final CartController cart;

  @override
  State<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends State<SalesScreen> {
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  Timer? _debounce;
  List<Product> _results = const [];
  bool _searching = false;
  Object? _searchError;
  int _request = 0;
  SaleDetail? _done;

  /// The last product put in the cart, announced in the cart itself: a snackbar would
  /// cover the checkout button the cashier reaches for next.
  String? _lastAdded;
  final _scroll = ScrollController();
  String? _locationId;

  SessionController get session => widget.session;
  CartController get cart => widget.cart;
  bool get _canSell => session.can('sales.create');

  @override
  void initState() {
    super.initState();
    _locationId = session.location?.id;
    session.addListener(_sessionChanged);
    cart.addListener(_cartChanged);
    _cartChanged();
    // The finder starts with the catalog, like the design's cash desk, not with an empty page.
    if (_canSell) scheduleMicrotask(_runSearch);
  }

  @override
  void dispose() {
    session.removeListener(_sessionChanged);
    cart.removeListener(_cartChanged);
    widget.unsaved.mark(this, dirty: false);
    _debounce?.cancel();
    _search.dispose();
    _searchFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _cartChanged() {
    widget.unsaved.mark(this, dirty: !cart.isEmpty);
    if (mounted) setState(() {});
  }

  /// A cart belongs to one location: after the person switched (and confirmed losing the
  /// cart), start empty rather than selling goods the other location may not have.
  void _sessionChanged() {
    final id = session.location?.id;
    if (id != _locationId) {
      _locationId = id;
      cart.clear();
      _done = null;
      if (_canSell) _runSearch();
    }
  }

  Future<int?> _availability(Product product) async {
    final location = _locationId;
    if (location == null || !session.can('stock.view')) return null;
    try {
      final page = await widget.inventory.stock(
        productId: product.id,
        locationId: location,
        limit: 10,
      );
      return page.items
          .where((r) => r.condition == 'sellable')
          .fold<int>(0, (sum, r) => sum + r.quantityMilli);
    } catch (_) {
      return null; // only a hint; the server decides
    }
  }

  Future<void> _add(Product product) async {
    final l = strings(context);
    final available = await _availability(product);
    if (!mounted) return;
    setState(() {
      _done = null;
      _lastAdded = l.cartAdded(product.name);
    });
    cart.add(product, availableMilli: available);
  }

  Future<void> _runSearch() async {
    final text = _search.text.trim();
    final request = ++_request;
    setState(() {
      _searching = true;
      _searchError = null;
    });
    try {
      final page = await widget.catalog.products(
        query: text,
        limit: 12,
        locationId: _locationId,
      );
      if (!mounted || request != _request) return;
      setState(() {
        _results = page.items;
        _searching = false;
      });
    } catch (e) {
      if (!mounted || request != _request) return;
      setState(() {
        _searchError = e;
        _searching = false;
      });
    }
  }

  void _typed(String _) {
    ++_request; // Ignore an earlier scan while a new search is being typed.
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), _runSearch);
  }

  /// A scan only selects a search result. Adding to the cart is a separate action.
  Future<void> _scanned(String raw) async {
    final code = raw.trim();
    if (code.isEmpty) return;
    _debounce?.cancel();
    _search.text = code;
    final request = ++_request;
    setState(() {
      _searching = true;
      _searchError = null;
      _results = const [];
    });
    try {
      final product = await widget.catalog.lookup(code);
      if (!mounted || request != _request) return;
      setState(() {
        _results = product == null ? const [] : [product];
        _searching = false;
      });
      if (product == null) {
        showFeedback(context, strings(context).cartScannedNotFound(code));
      }
    } catch (e) {
      if (!mounted || request != _request) return;
      setState(() {
        _searchError = e;
        _searching = false;
      });
    }
  }

  /// Keyboard scanners and typed searches also leave the cart unchanged.
  Future<void> _submitted(String text) async {
    _debounce?.cancel();
    await _runSearch();
  }

  Future<void> _chooseCustomer() async {
    final choice = await showCustomerPicker(context, widget.repository);
    if (choice != null) cart.customer = choice.customer;
  }

  Future<void> _checkout() async {
    final locationId = _locationId;
    if (locationId == null || !cart.isReady) return;
    final outcome = await Navigator.of(context).push<CheckoutOutcome>(
      MaterialPageRoute(
        builder: (_) => CheckoutScreen(
          cart: cart,
          session: session,
          repository: widget.repository,
          runner: widget.runner,
          monitor: widget.monitor,
          unsaved: widget.unsaved,
          locationId: locationId,
          locationName: session.location?.name ?? '',
        ),
      ),
    );
    if (!mounted || outcome == null) return;
    final l = strings(context);
    switch (outcome) {
      case SaleCompleted(:final sale):
        cart.clear();
        _search.clear();
        setState(() => _done = sale);
        _runSearch(); // the quantities in stock have just changed
        // the confirmation sits at the top; the cashier may be scrolled far below it
        if (_scroll.hasClients) _scroll.jumpTo(0);
      case SaleUnknown():
        // The saved record now owns this sale (the pending banner lists it): the cart
        // is emptied so the same goods cannot be sold a second time by hand.
        cart.clear();
        showFeedback(context, l.outcomeUnknownNotice);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = strings(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 900;
        final compact = constraints.maxWidth < 600;
        return ListView(
          controller: _scroll,
          padding: EdgeInsets.fromLTRB(
            compact ? 16 : 32,
            compact ? 20 : 32,
            compact ? 16 : 32,
            40,
          ),
          children: [
            PageHead(
              eyebrow: l.sales,
              title: l.salesCashDesk,
              subtitle: session.location?.name,
              actions: [
                if (session.can('sales.view'))
                  OutlinedButton.icon(
                    key: const ValueKey('sales-history'),
                    onPressed: () => Navigator.of(context).push<void>(
                      MaterialPageRoute(
                        builder: (_) => SalesHistoryScreen(
                          session: session,
                          repository: widget.repository,
                          runner: widget.runner,
                          monitor: widget.monitor,
                          unsaved: widget.unsaved,
                        ),
                      ),
                    ),
                    icon: const AppIcon(AppIcons.sale, size: 20),
                    label: Text(l.saleHistoryTitle),
                  ),
                if (session.can('return.view'))
                  OutlinedButton.icon(
                    key: const ValueKey('sales-returns'),
                    onPressed: () => Navigator.of(context).push<void>(
                      MaterialPageRoute(
                        builder: (_) => ReturnsScreen(
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
                    ),
                    icon: const AppIcon(AppIcons.returnArrow, size: 20),
                    label: Text(l.returnsTitle),
                  ),
              ],
            ),
            const SizedBox(height: 24),
            if (!_canSell)
              SurfaceCard(
                child: Text(
                  l.salesNoPermission,
                  key: const ValueKey('sales-no-permission'),
                ),
              )
            else ...[
              if (_done != null) ...[
                _donePanel(context, _done!),
                const SizedBox(height: 16),
              ],
              if (wide)
                SizedBox(
                  height: (constraints.maxHeight - 200).clamp(540.0, 1400.0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        flex: 108,
                        child: _findPanel(context, fixed: true),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        flex: 92,
                        child: _cartPanel(context, fixed: true),
                      ),
                    ],
                  ),
                )
              else ...[
                _findPanel(context, fixed: false),
                const SizedBox(height: 16),
                _cartPanel(context, fixed: false),
              ],
            ],
          ],
        );
      },
    );
  }

  // ---- the product finder --------------------------------------------------------

  Widget _findPanel(BuildContext context, {required bool fixed}) {
    final l = strings(context);
    final Widget results;
    if (_searchError != null) {
      results = Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: ErrorPanel(error: _searchError!, onRetry: _runSearch),
      );
    } else if (_searching && _results.isEmpty) {
      results = const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    } else if (_search.text.trim().isEmpty && _results.isEmpty) {
      results = EmptyState(
        key: const ValueKey('sales-start'),
        title: l.noProducts,
        subtitle: l.salesStartHint,
        icon: AppIcons.scan,
      );
    } else if (_results.isEmpty) {
      results = EmptyState(
        key: const ValueKey('sales-no-match'),
        title: l.noResults,
        subtitle: l.salesNoMatch,
      );
    } else {
      results = Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          children: [
            for (final product in _results)
              _ResultTile(
                product: product,
                repository: widget.catalog,
                onAdd: () => _add(product),
              ),
          ],
        ),
      );
    }
    return SurfaceCard(
      padding: 0,
      child: Column(
        mainAxisSize: fixed ? MainAxisSize.max : MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: BarcodeInput(
              fieldKey: const ValueKey('sales-search'),
              controller: _search,
              label: l.searchProducts,
              onChanged: _typed,
              focusNode: _searchFocus,
              keepFocusOnSubmit: true,
              onSubmitted: _submitted,
              onScanned: _scanned,
            ),
          ),
          if (fixed)
            Expanded(child: SingleChildScrollView(child: results))
          else
            results,
        ],
      ),
    );
  }

  // ---- the cart --------------------------------------------------------------------

  Widget _cartPanel(BuildContext context, {required bool fixed}) {
    final l = strings(context);
    final pieces = cart.lines.length;
    final lines = <Widget>[
      if (_lastAdded != null && !cart.isEmpty)
        Semantics(
          liveRegion: true,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              _lastAdded!,
              key: const ValueKey('cart-added'),
              style: const TextStyle(color: AppColors.success, fontSize: 13),
            ),
          ),
        ),
      for (var i = 0; i < cart.lines.length; i++)
        _CartLineCard(
          key: ObjectKey(cart.lines[i]),
          cart: cart,
          line: cart.lines[i],
          index: i,
          first: i == 0 && _lastAdded == null,
        ),
    ];
    final head = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 16, 0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    l.cartTitle,
                    style: const TextStyle(
                      fontSize: 16,
                      fontVariations: [FontVariation.weight(650)],
                    ),
                  ),
                ),
                if (pieces > 0)
                  StatusPill(
                    key: const ValueKey('cart-count'),
                    label: l.cartBadge(pieces),
                    tone: StatusTone.neutral,
                  ),
              ],
            ),
          ),
        ),
        if (session.can('customer.view'))
          Padding(
            padding: const EdgeInsets.only(left: 10, right: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 260),
                child: TextButton.icon(
                  key: const ValueKey('cart-customer'),
                  onPressed: _chooseCustomer,
                  style: TextButton.styleFrom(
                    minimumSize: const Size(48, 40),
                    textStyle: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  icon: const AppIcon(AppIcons.user, size: 16),
                  label: Text(
                    cart.customer?.name ?? l.customerChoose,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
    final Widget body;
    if (cart.isEmpty) {
      body = EmptyState(
        key: const ValueKey('cart-empty'),
        title: l.cartEmpty,
        subtitle: l.salesStartHint,
        icon: AppIcons.cart,
      );
    } else {
      body = Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(children: lines),
      );
    }
    final summary = cart.isEmpty
        ? null
        : Container(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: AppColors.line)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Expanded(
                      child: Text(
                        l.cartTotalLabel,
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Flexible(
                      child: Text(
                        formatMoney(cart.totalMinor, 'TMT'),
                        key: const ValueKey('cart-total'),
                        textAlign: TextAlign.end,
                        style: const TextStyle(
                          fontFamily: AppFonts.display,
                          fontWeight: FontWeight.w600,
                          fontSize: 32,
                          letterSpacing: -1.28,
                          color: AppColors.ink,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                LayoutBuilder(
                  builder: (context, box) {
                    // side by side only when both fit at the reader's text size
                    final stacked =
                        box.maxWidth <
                        MediaQuery.textScalerOf(context).scale(420);
                    final method = AppSegmented<String>(
                      keyPrefix: 'cart-pay',
                      expand: stacked,
                      value: cart.paymentMethod,
                      onChanged: (m) => cart.paymentMethod = m,
                      options: [
                        for (final m in paymentMethods)
                          (m, m == 'cash' ? l.payCash : l.payCard),
                      ],
                    );
                    final button = PrimaryButton(
                      key: const ValueKey('cart-checkout'),
                      label: l.toPayment,
                      onPressed: cart.isReady ? _checkout : null,
                    );
                    if (stacked) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [method, const SizedBox(height: 12), button],
                      );
                    }
                    return Row(
                      children: [
                        method,
                        const SizedBox(width: 12),
                        Expanded(child: button),
                      ],
                    );
                  },
                ),
              ],
            ),
          );
    return SurfaceCard(
      padding: 0,
      child: Column(
        mainAxisSize: fixed ? MainAxisSize.max : MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          head,
          if (fixed)
            Expanded(child: SingleChildScrollView(child: body))
          else
            body,
          ?summary,
        ],
      ),
    );
  }

  // ---- after a confirmed sale ------------------------------------------------------------

  Widget _donePanel(BuildContext context, SaleDetail sale) {
    final l = strings(context);
    return SurfaceCard(
      key: const ValueKey('sale-done'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const AppIcon(AppIcons.checkCircle, color: AppColors.success),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l.saleDoneTitle(saleNumber(sale.number)),
                  key: const ValueKey('sale-done-number'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(l.saleTotal(formatMoney(sale.totalMinor, 'TMT'))),
          const SizedBox(height: 16),
          DocumentButtons(
            repository: widget.repository,
            saleId: sale.id,
            saleNumber: sale.number,
          ),
          const SizedBox(height: 16),
          PrimaryButton(
            key: const ValueKey('sale-new'),
            label: l.newSaleAction,
            icon: AppIcons.plus,
            onPressed: () => setState(() => _done = null),
          ),
        ],
      ),
    );
  }
}

class _ResultTile extends StatelessWidget {
  const _ResultTile({
    required this.product,
    required this.repository,
    required this.onAdd,
  });
  final Product product;
  final CatalogRepository repository;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final l = strings(context);
    final unit = product.priceTmtMinor;
    return InkWell(
      key: ValueKey('sell-${product.sku}'),
      onTap: onAdd,
      hoverColor: AppColors.surfaceSoft,
      child: Container(
        constraints: const BoxConstraints(minHeight: 80),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.line)),
        ),
        child: Row(
          children: [
            ProductPhoto(
              product: product,
              repository: repository,
              width: 48,
              height: 48,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    [
                      product.sku,
                      ?product.brand?.name,
                      if (product.onHandMilli != null)
                        l.inStockHere(
                          quantityWithUnit(product.onHandMilli!, product.unit),
                        ),
                    ].join(' · '),
                    key: ValueKey('sell-meta-${product.sku}'),
                    style: const TextStyle(
                      fontFamily: AppFonts.mono,
                      color: AppColors.muted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    unit == null ? l.rateMissingNote : formatMoney(unit, 'TMT'),
                    textAlign: TextAlign.end,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: unit == null ? AppColors.warning : null,
                      fontSize: unit == null ? 12 : 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  const AppIcon(AppIcons.plus, size: 20),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CartLineCard extends StatefulWidget {
  const _CartLineCard({
    super.key,
    required this.cart,
    required this.line,
    required this.index,
    this.first = false,
  });
  final CartController cart;
  final CartLine line;
  final int index;

  /// The first row has no line above it.
  final bool first;

  @override
  State<_CartLineCard> createState() => _CartLineCardState();
}

class _CartLineCardState extends State<_CartLineCard> {
  late final _quantity = TextEditingController(text: widget.line.quantityText);
  late final _price = TextEditingController(text: widget.line.priceText);

  @override
  void initState() {
    super.initState();
    widget.cart.addListener(_sync);
  }

  @override
  void dispose() {
    widget.cart.removeListener(_sync);
    _quantity.dispose();
    _price.dispose();
    super.dispose();
  }

  /// Keeps the text fields in step when the cart itself changes them (a step button). Runs
  /// when the cart notifies, never during a build.
  void _sync() {
    if (_quantity.text != widget.line.quantityText) {
      _quantity.text = widget.line.quantityText;
    }
    if (_price.text != widget.line.priceText) {
      _price.text = widget.line.priceText;
    }
  }

  String? _problemText(String? problem) {
    final l = strings(context);
    final line = widget.line;
    return switch (problem) {
      'required' || 'price_required' => l.fieldRequired,
      'price_invalid' => l.fieldInvalid,
      'quantity' => l.fieldQuantityPrecision,
      'exceeds_available' => l.exceedsAvailable(
        quantityWithUnit(line.availableMilli ?? 0, line.product.unit),
      ),
      _ => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l = strings(context);
    final cart = widget.cart;
    final line = widget.line;
    final problem = cart.problem(line);
    final catalogPrice = line.product.priceTmtMinor;
    final lineTotal = cart.lineTotalMinor(line);
    const step = 1000; // one whole unit
    final meta = [
      line.product.sku,
      line.product.unit.symbol,
      if (line.availableMilli != null)
        l.availableHere(
          quantityWithUnit(line.availableMilli!, line.product.unit),
        ),
    ].join(' · ');
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        border: widget.first
            ? null
            : const Border(top: BorderSide(color: AppColors.line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final left = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    line.product.name,
                    style: const TextStyle(
                      fontSize: 14,
                      fontVariations: [FontVariation.weight(650)],
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    meta,
                    style: const TextStyle(
                      fontFamily: AppFonts.mono,
                      letterSpacing: -0.24,
                      color: AppColors.muted,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _Stepper(
                        index: widget.index,
                        controller: _quantity,
                        label: l.quantity,
                        onMinus: () => cart.step(line, -step),
                        onPlus: () => cart.step(line, step),
                        onChanged: (v) => cart.setQuantityText(line, v),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        key: ValueKey('cart-remove-${widget.index}'),
                        tooltip: l.removeLine,
                        style: IconButton.styleFrom(
                          minimumSize: const Size(40, 40),
                          foregroundColor: AppColors.muted,
                        ),
                        onPressed: () => cart.remove(line),
                        icon: const AppIcon(AppIcons.trash, size: 20),
                      ),
                    ],
                  ),
                ],
              );
              final right = Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  SizedBox(
                    height: 42,
                    child: Semantics(
                      label: l.priceFieldLabel,
                      child: TextField(
                        key: ValueKey('cart-price-${widget.index}'),
                        controller: _price,
                        textAlign: TextAlign.end,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        onChanged: (v) => cart.setPriceText(line, v),
                        style: const TextStyle(
                          fontSize: 14,
                          fontVariations: [FontVariation.weight(650)],
                        ),
                        decoration: InputDecoration(
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(color: AppColors.line),
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(
                              color: AppColors.blue,
                              width: 1.5,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (catalogPrice != null) ...[
                    const SizedBox(height: 5),
                    Text(
                      l.catalogPriceLine(formatMoney(catalogPrice, 'TMT')),
                      textAlign: TextAlign.end,
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                  if (lineTotal != null) ...[
                    const SizedBox(height: 5),
                    Text(
                      formatMoney(lineTotal, 'TMT'),
                      key: ValueKey('cart-line-total-${widget.index}'),
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ],
              );
              // On a narrow line (a phone, or large text) the price block goes under the name.
              if (constraints.maxWidth < 380) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [left, const SizedBox(height: 12), right],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: left),
                  const SizedBox(width: 12),
                  SizedBox(width: 126, child: right),
                ],
              );
            },
          ),
          if (problem != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                _problemText(problem) ?? '',
                key: ValueKey('cart-problem-${widget.index}'),
                style: const TextStyle(color: AppColors.danger, fontSize: 13),
              ),
            ),
        ],
      ),
    );
  }
}

/// The quantity control of the design: minus, the number, plus, in one bordered box.
class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.index,
    required this.controller,
    required this.label,
    required this.onMinus,
    required this.onPlus,
    required this.onChanged,
  });
  final int index;
  final TextEditingController controller;
  final String label;
  final VoidCallback onMinus;
  final VoidCallback onPlus;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget button(Key key, AppIconData icon, VoidCallback onTap) => InkWell(
      key: key,
      onTap: onTap,
      child: SizedBox(
        width: 40,
        height: 40,
        child: Center(child: AppIcon(icon, size: 16)),
      ),
    );
    return Container(
      height: 40,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          button(ValueKey('cart-minus-$index'), AppIcons.minus, onMinus),
          SizedBox(
            width: 52,
            child: Semantics(
              label: label,
              child: TextField(
                key: ValueKey('cart-qty-$index'),
                controller: controller,
                textAlign: TextAlign.center,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                onChanged: onChanged,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
                decoration: const InputDecoration(
                  filled: false,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  errorBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                ),
              ),
            ),
          ),
          button(ValueKey('cart-plus-$index'), AppIcons.plus, onPlus),
        ],
      ),
    );
  }
}
