import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/connectivity/connection_monitor.dart';
import '../../core/operations/operation_runner.dart';
import '../../core/session/session_controller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/common.dart';
import '../admin/admin_repository.dart';
import '../admin/administration_screen.dart';
import '../catalog/catalog_repository.dart';
import '../catalog/catalog_screen.dart';
import '../inventory/inventory_repository.dart';
import '../inventory/stock_screen.dart';
import '../operations/pending_operations_banner.dart';
import '../purchasing/purchasing_repository.dart';
import '../purchasing/purchasing_screen.dart';
import '../sales/cart_controller.dart';
import '../expenses/expenses_repository.dart';
import '../expenses/expenses_screen.dart';
import '../sales/sales_repository.dart';
import '../sales/sales_screen.dart';
import 'placeholder_screens.dart';
import '../warranties/warranties_repository.dart';
import '../warranties/warranties_screen.dart';
import 'unsaved_work.dart';

/// The signed-in workspace. Navigation shows only what the role may use, the
/// header lets the user switch location (and business, when they have several),
/// and pages that are not connected to the server yet say so honestly.
class RealWorkspace extends StatefulWidget {
  const RealWorkspace({
    super.key,
    required this.session,
    required this.api,
    required this.runner,
    required this.monitor,
    required this.unsaved,
    required this.languageCode,
    required this.onLanguageChanged,
  });

  final SessionController session;
  final ApiClient api;
  final OperationRunner runner;
  final ConnectionMonitor monitor;
  final UnsavedWork unsaved;
  final String languageCode;
  final ValueChanged<String> onLanguageChanged;

  @override
  State<RealWorkspace> createState() => _RealWorkspaceState();
}

class _RealWorkspaceState extends State<RealWorkspace> {
  AppPage _page = AppPage.dashboard;
  int _reloadCounter = 0;

  /// One cart per business, kept here (not in the sales screen) so it survives moving to
  /// another page and switching the language. It is dropped with the workspace on sign-out.
  final Map<String, CartController> _carts = {};

  @override
  void dispose() {
    for (final cart in _carts.values) {
      cart.dispose();
    }
    super.dispose();
  }

  SessionController get session => widget.session;

  bool _allowed(AppPage page) => switch (page) {
    AppPage.products => session.can('catalog.view'),
    AppPage.inventory => session.can('stock.view'),
    AppPage.purchasing => session.can('purchasing.view'),
    AppPage.sales => session.can('sales.create') || session.can('sales.view'),
    AppPage.expenses => session.can('expense.view'),
    AppPage.warranties => session.can('warranty.view'),
    _ => true,
  };

  List<AppPage> get _pages => [
    for (final p in AppPage.values)
      if (_allowed(p)) p,
  ];

  /// Asks before a context switch would throw away unsaved input.
  Future<bool> _confirmSwitch() async {
    if (!widget.unsaved.isDirty) return true;
    final l = strings(context);
    return await confirmAction(context, l.location, l.unsavedChangeConflict) &&
        mounted;
  }

  Widget _content() {
    final membership = session.membership!;
    final page = _allowed(_page) ? _page : AppPage.dashboard;
    return switch (page) {
      AppPage.dashboard => WelcomeScreen(session: session),
      AppPage.products => CatalogScreen(
        key: ValueKey('catalog-${membership.id}'),
        session: session,
        repository: CatalogRepository(widget.api, membership.businessId),
        unsaved: widget.unsaved,
      ),
      AppPage.inventory => StockScreen(
        key: ValueKey('stock-${membership.id}-$_reloadCounter'),
        session: session,
        repository: InventoryRepository(widget.api, membership.businessId),
        catalog: CatalogRepository(widget.api, membership.businessId),
        runner: widget.runner,
        monitor: widget.monitor,
        unsaved: widget.unsaved,
      ),
      AppPage.purchasing => PurchasingScreen(
        key: ValueKey('purchasing-${membership.id}-$_reloadCounter'),
        session: session,
        repository: PurchasingRepository(widget.api, membership.businessId),
        catalog: CatalogRepository(widget.api, membership.businessId),
        runner: widget.runner,
        monitor: widget.monitor,
        unsaved: widget.unsaved,
      ),
      AppPage.sales => SalesScreen(
        // No reload counter in the key: a recovered operation must not empty the cart.
        key: ValueKey('sales-${membership.id}'),
        session: session,
        catalog: CatalogRepository(widget.api, membership.businessId),
        inventory: InventoryRepository(widget.api, membership.businessId),
        repository: SalesRepository(widget.api, membership.businessId),
        runner: widget.runner,
        monitor: widget.monitor,
        unsaved: widget.unsaved,
        cart: _carts.putIfAbsent(membership.id, CartController.new),
      ),
      AppPage.expenses => ExpensesScreen(
        key: ValueKey('expenses-${membership.id}-$_reloadCounter'),
        session: session,
        repository: ExpensesRepository(widget.api, membership.businessId),
        unsaved: widget.unsaved,
      ),
      AppPage.warranties => WarrantiesScreen(
        key: ValueKey('warranties-${membership.id}-$_reloadCounter'),
        session: session,
        repository: WarrantiesRepository(widget.api, membership.businessId),
        sales: SalesRepository(widget.api, membership.businessId),
        runner: widget.runner,
        monitor: widget.monitor,
        unsaved: widget.unsaved,
      ),
      AppPage.administration => RealAdministrationScreen(
        key: ValueKey('admin-${membership.id}-$_reloadCounter'),
        session: session,
        repository: AdminRepository(widget.api, membership.businessId),
        catalog: CatalogRepository(widget.api, membership.businessId),
        languageCode: widget.languageCode,
        onLanguageChanged: widget.onLanguageChanged,
      ),
      _ => const UnavailableScreen(),
    };
  }

  Widget _selectors(BuildContext context) {
    final l = strings(context);
    final membership = session.membership!;
    return Wrap(
      spacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (session.memberships.length > 1)
          PopupMenuButton<String>(
            key: const ValueKey('business-selector'),
            tooltip: l.business,
            initialValue: membership.id,
            onSelected: (id) async {
              if (await _confirmSwitch()) session.selectMembership(id);
            },
            itemBuilder: (context) => [
              for (final m in session.memberships)
                PopupMenuItem(value: m.id, child: Text(m.businessName)),
            ],
            child: _SelectorLabel(
              icon: Icons.business_outlined,
              text: membership.businessName,
            ),
          ),
        if (membership.locations.isEmpty)
          Text(
            l.noLocationsAvailable,
            style: const TextStyle(color: AppColors.muted, fontSize: 13),
          )
        else
          PopupMenuButton<String>(
            key: const ValueKey('location-selector'),
            tooltip: l.location,
            initialValue: session.location?.id,
            onSelected: (id) async {
              if (await _confirmSwitch()) session.selectLocation(id);
            },
            itemBuilder: (context) => [
              for (final location in membership.locations)
                PopupMenuItem(value: location.id, child: Text(location.name)),
            ],
            child: _SelectorLabel(
              icon: Icons.storefront_outlined,
              text: session.location?.name ?? '',
              chevron: true,
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([session, widget.monitor]),
    builder: (context, _) {
      final l = strings(context);
      final membership = session.membership;
      if (membership == null) return NoBusinessScreen(session: session);
      return AppShell(
        pages: _pages,
        page: _allowed(_page) ? _page : AppPage.dashboard,
        onNavigate: (page) => setState(() => _page = page),
        body: _content(),
        languageCode: widget.languageCode,
        onLanguageChanged: widget.onLanguageChanged,
        locationControl: _selectors(context),
        banners: [
          if (!widget.monitor.online)
            Container(
              key: const ValueKey('offline-banner'),
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              color: const Color(0xFFFEF2F2),
              child: Text(
                l.offlineBanner,
                style: const TextStyle(fontSize: 12, color: AppColors.danger),
              ),
            ),
          PendingOperationsBanner(
            runner: widget.runner,
            onResolved: () => setState(() => _reloadCounter++),
          ),
        ],
        sidebarFooter: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              session.user?.displayName ?? '',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            Text(
              '${roleLabel(l, membership.role)} · ${membership.businessName}',
              style: const TextStyle(fontSize: 13, color: AppColors.muted),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              key: const ValueKey('sidebar-sign-out'),
              onPressed: session.signOut,
              icon: const Icon(Icons.logout, size: 18),
              label: Text(l.signOut),
            ),
          ],
        ),
      );
    },
  );
}

class _SelectorLabel extends StatelessWidget {
  const _SelectorLabel({
    required this.icon,
    required this.text,
    this.chevron = false,
  });
  final IconData icon;
  final String text;
  final bool chevron;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 20, color: AppColors.muted),
        const SizedBox(width: 8),
        Flexible(child: Text(text, style: const TextStyle(fontSize: 14))),
        if (chevron) ...[
          const SizedBox(width: 6),
          const Icon(Icons.expand_more, size: 18),
        ],
      ],
    ),
  );
}
