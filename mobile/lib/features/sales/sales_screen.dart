import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/connectivity/connection_monitor.dart';
import '../../core/money/decimal_math.dart';
import '../../core/operations/operation_runner.dart';
import '../../core/session/session_controller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../catalog/catalog_models.dart';
import '../catalog/catalog_repository.dart';
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
    if (text.isEmpty) {
      setState(() {
        _results = const [];
        _searchError = null;
        _searching = false;
      });
      return;
    }
    final request = ++_request;
    setState(() {
      _searching = true;
      _searchError = null;
    });
    try {
      final page = await widget.catalog.products(query: text, limit: 12);
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
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), _runSearch);
  }

  /// A scan finds the product for the code and puts it in the cart; it never completes a
  /// sale. An unknown code says so and changes nothing.
  Future<void> _scanned(String code) async {
    _debounce?.cancel();
    final l = strings(context);
    try {
      final product = await widget.catalog.lookup(code);
      if (!mounted) return;
      _search.clear();
      setState(() => _results = const []);
      if (product == null) {
        showFeedback(context, l.cartScannedNotFound(code));
        return;
      }
      await _add(product);
    } catch (_) {
      if (mounted) showFeedback(context, l.loadFailed);
    }
  }

  /// Enter in the search field. A hand scanner types the code of the item and presses Enter: when
  /// the text is exactly a barcode or article number of a product, that product goes into the
  /// cart (like a camera scan) and the field stays ready for the next item. Anything else is an
  /// ordinary search, and a code nobody has also just searches (it says nothing, unlike a camera
  /// scan, because the person may have been typing a name).
  Future<void> _submitted(String text) async {
    _debounce?.cancel();
    final code = text.trim();
    if (code.isNotEmpty && !code.contains(RegExp(r'\s'))) {
      try {
        final product = await widget.catalog.lookup(code);
        if (!mounted) return;
        if (product != null) {
          _search.clear();
          setState(() => _results = const []);
          await _add(product);
          if (mounted && !_searchFocus.hasFocus) _searchFocus.requestFocus();
          return;
        }
      } catch (_) {
        // no answer: fall through to the ordinary search, which reports the problem
      }
    }
    if (mounted) _runSearch();
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
        setState(() {
          _done = sale;
          _results = const [];
        });
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
        final left = _canSell ? _findPanel(context) : const SizedBox.shrink();
        final right = _canSell ? _cartPanel(context) : const SizedBox.shrink();
        return ListView(
          controller: _scroll,
          padding: const EdgeInsets.all(24),
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
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
                    icon: const Icon(Icons.receipt_long_outlined),
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
                    icon: const Icon(Icons.assignment_return_outlined),
                    label: Text(l.returnsTitle),
                  ),
              ],
            ),
            const SizedBox(height: 16),
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
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 5, child: left),
                    const SizedBox(width: 20),
                    Expanded(flex: 5, child: right),
                  ],
                )
              else ...[
                left,
                const SizedBox(height: 16),
                right,
              ],
            ],
          ],
        );
      },
    );
  }

  // ---- the product finder --------------------------------------------------------

  Widget _findPanel(BuildContext context) {
    final l = strings(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BarcodeInput(
          fieldKey: const ValueKey('sales-search'),
          controller: _search,
          label: l.searchProducts,
          onChanged: _typed,
          focusNode: _searchFocus,
          keepFocusOnSubmit: true,
          onSubmitted: _submitted,
          onScanned: _scanned,
        ),
        const SizedBox(height: 12),
        if (_searchError != null)
          ErrorPanel(error: _searchError!, onRetry: _runSearch)
        else if (_searching && _results.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_search.text.trim().isEmpty)
          SurfaceCard(
            child: EmptyState(
              key: const ValueKey('sales-start'),
              title: l.cartEmpty,
              subtitle: l.salesStartHint,
              icon: Icons.qr_code_scanner,
            ),
          )
        else if (_results.isEmpty)
          SurfaceCard(
            child: EmptyState(
              key: const ValueKey('sales-no-match'),
              title: l.noResults,
              subtitle: l.salesNoMatch,
            ),
          )
        else
          for (final product in _results)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _ResultTile(product: product, onAdd: () => _add(product)),
            ),
      ],
    );
  }

  // ---- the cart --------------------------------------------------------------------

  Widget _cartPanel(BuildContext context) {
    final l = strings(context);
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l.cartTitle, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          if (session.can('customer.view'))
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                key: const ValueKey('cart-customer'),
                onPressed: _chooseCustomer,
                icon: const Icon(Icons.person_outline),
                label: Text(cart.customer?.name ?? l.customerChoose),
              ),
            ),
          const SizedBox(height: 12),
          if (cart.isEmpty)
            Text(
              l.cartEmpty,
              key: const ValueKey('cart-empty'),
              style: const TextStyle(color: AppColors.muted),
            )
          else ...[
            if (_lastAdded != null)
              Semantics(
                liveRegion: true,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    _lastAdded!,
                    key: const ValueKey('cart-added'),
                    style: const TextStyle(color: AppColors.success),
                  ),
                ),
              ),
            for (final line in cart.lines)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _CartLineCard(
                  key: ObjectKey(line),
                  cart: cart,
                  line: line,
                  index: cart.lines.indexOf(line),
                ),
              ),
            const Divider(height: 28),
            Text(
              l.saleTotal(formatMoney(cart.totalMinor, 'TMT')),
              key: const ValueKey('cart-total'),
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
            GradientButton(
              key: const ValueKey('cart-checkout'),
              label: l.toPayment,
              icon: Icons.payments_outlined,
              onPressed: cart.isReady ? _checkout : null,
            ),
          ],
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
              const Icon(Icons.check_circle, color: AppColors.success),
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
          GradientButton(
            key: const ValueKey('sale-new'),
            label: l.newSaleAction,
            icon: Icons.add,
            onPressed: () => setState(() => _done = null),
          ),
        ],
      ),
    );
  }
}

class _ResultTile extends StatelessWidget {
  const _ResultTile({required this.product, required this.onAdd});
  final Product product;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final l = strings(context);
    final unit = product.priceTmtMinor;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: ValueKey('sell-${product.sku}'),
        borderRadius: BorderRadius.circular(16),
        onTap: onAdd,
        child: SurfaceCard(
          padding: 14,
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      [product.sku, ?product.brand?.name].join(' · '),
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  unit == null ? l.rateMissingNote : formatMoney(unit, 'TMT'),
                  textAlign: TextAlign.end,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: unit == null ? AppColors.warning : null,
                    fontSize: unit == null ? 12 : null,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.add_circle_outline, color: AppColors.blue),
            ],
          ),
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
  });
  final CartController cart;
  final CartLine line;
  final int index;

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
    final step = 1000; // one whole unit
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  line.product.name,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              IconButton(
                key: ValueKey('cart-remove-${widget.index}'),
                tooltip: l.removeLine,
                onPressed: () => cart.remove(line),
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
          Text(
            [
              line.product.sku,
              if (catalogPrice != null)
                l.catalogPriceLine(formatMoney(catalogPrice, 'TMT')),
              if (line.availableMilli != null)
                l.availableHere(
                  quantityWithUnit(line.availableMilli!, line.product.unit),
                ),
            ].join(' · '),
            style: const TextStyle(color: AppColors.muted, fontSize: 12),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.start,
            children: [
              IconButton.outlined(
                key: ValueKey('cart-minus-${widget.index}'),
                onPressed: () => cart.step(line, -step),
                icon: const Icon(Icons.remove),
              ),
              SizedBox(
                width: 130,
                child: TextField(
                  key: ValueKey('cart-qty-${widget.index}'),
                  controller: _quantity,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  onChanged: (v) => cart.setQuantityText(line, v),
                  decoration: InputDecoration(
                    labelText: l.quantity,
                    suffixText: line.product.unit.symbol,
                  ),
                ),
              ),
              IconButton.outlined(
                key: ValueKey('cart-plus-${widget.index}'),
                onPressed: () => cart.step(line, step),
                icon: const Icon(Icons.add),
              ),
              SizedBox(
                width: 190,
                child: TextField(
                  key: ValueKey('cart-price-${widget.index}'),
                  controller: _price,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  onChanged: (v) => cart.setPriceText(line, v),
                  decoration: InputDecoration(labelText: l.priceFieldLabel),
                ),
              ),
            ],
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
          if (lineTotal != null)
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                formatMoney(lineTotal, 'TMT'),
                key: ValueKey('cart-line-total-${widget.index}'),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
        ],
      ),
    );
  }
}
