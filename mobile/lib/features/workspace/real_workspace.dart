import 'package:flutter/material.dart';
import '../../widgets/app_icons.dart';

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
import '../catalog/to_complete_screen.dart';
import '../inventory/inventory_repository.dart';
import '../inventory/stock_screen.dart';
import '../operations/pending_operations_banner.dart';
import '../reports/dashboard_screen.dart';
import '../reports/reports_repository.dart';
import '../reports/reports_screen.dart';
import '../sales/cart_controller.dart';
import '../../core/session/session_models.dart';
import '../../l10n/app_localizations.dart';
import '../guide/coach_guide.dart';
import '../setup/setup_wizard.dart';
import '../subscription/subscription_widgets.dart';
import '../support/help_screen.dart';
import '../support/support_repository.dart';
import '../support/support_screen.dart';
import '../expenses/expenses_repository.dart';
import '../expenses/expenses_screen.dart';
import '../sales/sales_repository.dart';
import '../sales/sales_screen.dart';
import 'placeholder_screens.dart';
import '../warranties/warranties_repository.dart';
import '../warranties/warranties_screen.dart';
import 'unsaved_work.dart';
import '../../widgets/app_route.dart';

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

  /// The first-sign-in questions are on screen (kept until the owner leaves them, so the last
  /// "done" page is not replaced the moment the answers are saved).
  bool _setupActive = false;
  bool _setupDismissed = false;

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
    AppPage.sales => session.can('sales.create') || session.can('sales.view'),
    AppPage.expenses => session.can('expense.view'),
    AppPage.warranties => session.can('warranty.view'),
    AppPage.reports => session.can('report.view'),
    AppPage.platformOverview ||
    AppPage.platformClients ||
    AppPage.platformSupport ||
    AppPage.platformNotices => false,
    _ => true,
  };

  List<AppPage> get _pages => [
    for (final p in storePages)
      if (_allowed(p)) p,
  ];

  /// Asks before a context switch would throw away unsaved input.
  Future<bool> _confirmSwitch() async {
    if (!widget.unsaved.isDirty) return true;
    final l = strings(context);
    return await confirmAction(context, l.location, l.unsavedChangeConflict) &&
        mounted;
  }

  /// The list of products that still need a price or a cost; the dashboard is read again after.
  Future<void> _openToComplete() async {
    final membership = session.membership!;
    await Navigator.of(context).push<void>(
      appRoute(
        builder: (_) => ToCompleteScreen(
          repository: CatalogRepository(widget.api, membership.businessId),
        ),
      ),
    );
    if (mounted) setState(() => _reloadCounter++);
  }

  /// How-to pages, with a way to write to us for those who may.
  Future<void> _openHelp() => Navigator.of(context).push<void>(
    appRoute(
      builder: (_) => HelpScreen(
        onWriteToUs: session.can('support.write')
            ? () {
                Navigator.of(context).pop();
                _openSupport();
              }
            : null,
      ),
    ),
  );

  /// The conversation with us.
  Future<void> _openSupport() => Navigator.of(context).push<void>(
    appRoute(
      builder: (_) => SupportScreen(
        session: session,
        repository: SupportRepository(
          widget.api,
          session.membership!.businessId,
        ),
        screenName: _page.name,
      ),
    ),
  );

  /// The first-time tips of a page: shown once, with arrows, "Next" and "Skip".
  Widget _guided(String id, List<GuideStep> steps, Widget child) => GuideOnce(
    key: ValueKey('guide-$id'),
    id: id,
    preferences: session.preferences,
    steps: steps,
    child: child,
  );

  Widget _content() {
    final membership = session.membership!;
    final page = _allowed(_page) ? _page : AppPage.dashboard;
    final inner = _page0(membership, page);
    return switch (page) {
      AppPage.dashboard => _guided('dashboard', const [
        GuideStep(['nav-sales', 'tab-sales'], _tipDashSales),
        GuideStep(['nav-products', 'tab-products'], _tipDashProducts),
        GuideStep(['nav-inventory', 'tab-inventory'], _tipDashStock),
        GuideStep(['help-button'], _tipDashHelp),
      ], inner),
      AppPage.products => _guided('products', const [
        GuideStep(['catalog-add'], _tipProdAdd),
        GuideStep(['catalog-search'], _tipProdSearch),
        GuideStep(['catalog-more'], _tipProdMore),
      ], inner),
      AppPage.sales => _guided('sales', const [
        GuideStep(['sales-search'], _tipSalesSearch),
        GuideStep(['cart-checkout'], _tipSalesCheckout),
      ], inner),
      AppPage.inventory => _guided('inventory', const [
        GuideStep(['stock-intake'], _tipStockIntake),
        GuideStep(['stock-more'], _tipStockMore),
        GuideStep(['stock-search'], _tipStockSearch),
      ], inner),
      _ => inner,
    };
  }

  static String _tipDashSales(AppLocalizations l) => l.guDashNavSales;
  static String _tipDashProducts(AppLocalizations l) => l.guDashNavProducts;
  static String _tipDashStock(AppLocalizations l) => l.guDashNavStock;
  static String _tipDashHelp(AppLocalizations l) => l.guDashHelp;
  static String _tipProdAdd(AppLocalizations l) => l.guProdAdd;
  static String _tipProdSearch(AppLocalizations l) => l.guProdSearch;
  static String _tipProdMore(AppLocalizations l) => l.guProdMore;
  static String _tipSalesSearch(AppLocalizations l) => l.guSalesSearch;
  static String _tipSalesCheckout(AppLocalizations l) => l.guSalesCheckout;
  static String _tipStockIntake(AppLocalizations l) => l.guStockIntake;
  static String _tipStockMore(AppLocalizations l) => l.guStockMore;
  static String _tipStockSearch(AppLocalizations l) => l.guStockSearch;

  /// The questions about the shop, opened again from Settings.
  Future<void> _openSetup() => Navigator.of(context).push<void>(
    appRoute(
      builder: (route) => SetupWizard(
        session: session,
        repository: SetupRepository(widget.api, session.membership!.businessId),
        firstRun: false,
        onClose: () => Navigator.of(route).pop(),
      ),
    ),
  );

  Widget _page0(MembershipInfo membership, AppPage page) {
    return switch (page) {
      AppPage.dashboard => DashboardScreen(
        key: ValueKey('dashboard-${session.dashboardScope}-$_reloadCounter'),
        session: session,
        repository: ReportsRepository(
          widget.api,
          membership.businessId,
          session: session,
        ),
        onOpenReports: () => setState(() => _page = AppPage.reports),
        onGo: (page) => setState(() => _page = page),
        onOpenToComplete: session.can('catalog.manage')
            ? _openToComplete
            : null,
      ),
      AppPage.products => CatalogScreen(
        key: ValueKey('catalog-${membership.id}'),
        session: session,
        repository: CatalogRepository(widget.api, membership.businessId),
        unsaved: widget.unsaved,
        onOpenToComplete: _openToComplete,
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
      AppPage.reports => ReportsScreen(
        key: ValueKey('reports-${membership.id}-$_reloadCounter'),
        session: session,
        repository: ReportsRepository(widget.api, membership.businessId),
      ),
      AppPage.platformOverview ||
      AppPage.platformClients ||
      AppPage.platformSupport ||
      AppPage.platformNotices => const SizedBox.shrink(),
      AppPage.administration => RealAdministrationScreen(
        key: ValueKey('admin-${membership.id}-$_reloadCounter'),
        session: session,
        repository: AdminRepository(widget.api, membership.businessId),
        catalog: CatalogRepository(widget.api, membership.businessId),
        languageCode: widget.languageCode,
        onLanguageChanged: widget.onLanguageChanged,
        onOpenHelp: _openHelp,
        onOpenSupport: _openSupport,
        onOpenSetup: session.can('staff.manage') ? _openSetup : null,
      ),
    };
  }

  Widget _selectors(BuildContext context) {
    final l = strings(context);
    final membership = session.membership!;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
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
            child: TopbarControl(
              icon: AppIcons.stock,
              text: membership.businessName,
              chevron: true,
            ),
          ),
        if (membership.locations.isEmpty)
          Text(
            l.noLocationsAvailable,
            style: TextStyle(color: AppColors.muted, fontSize: 13),
          )
        else if (membership.locations.length == 1)
          // One shop: nothing to choose, so just its name (no menu, no arrow). It is the
          // business's name, the one name the owner sets in Settings, so the shop never has
          // two names on screen.
          Semantics(
            label: membership.businessName,
            child: TopbarControl(
              key: const ValueKey('location-label'),
              icon: AppIcons.stock,
              text: membership.businessName,
            ),
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
            child: TopbarControl(
              icon: AppIcons.stock,
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
      // the owner of a shop we set up is asked a few questions first
      if (_setupActive ||
          (!_setupDismissed &&
              membership.role == 'owner' &&
              membership.setupStatus == 'pending')) {
        _setupActive = true;
        return SetupWizard(
          key: const ValueKey('setup-wizard'),
          session: session,
          repository: SetupRepository(widget.api, membership.businessId),
          firstRun: true,
          onClose: () => setState(() {
            _setupActive = false;
            _setupDismissed = true;
          }),
        );
      }
      if (session.subscription?.isSuspended ?? false) {
        // Access was cut off by us: nothing of the shop opens, only how to reach us.
        return SubscriptionBlockedScreen(
          session: session,
          onWriteToUs: session.can('support.write') ? _openSupport : null,
        );
      }
      return AppShell(
        pages: _pages,
        page: _allowed(_page) ? _page : AppPage.dashboard,
        onNavigate: (page) => setState(() => _page = page),
        body: _content(),
        languageCode: widget.languageCode,
        onLanguageChanged: widget.onLanguageChanged,
        locationControl: _selectors(context),
        onHelp: _openHelp,
        banners: [
          AnnouncementBanner(session: session),
          SubscriptionBanner(
            session: session,
            onRenew: () => showRenewDialog(
              context,
              session,
              onWriteToUs: session.can('support.write') ? _openSupport : null,
            ),
          ),
          if (!widget.monitor.online)
            Container(
              key: const ValueKey('offline-banner'),
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              color: AppColors.dangerTint,
              child: Text(
                l.offlineBanner,
                style: TextStyle(fontSize: 12, color: AppColors.danger),
              ),
            ),
          PendingOperationsBanner(
            runner: widget.runner,
            onResolved: () => setState(() => _reloadCounter++),
          ),
        ],
        userName: session.user?.displayName ?? '',
        roleName: roleLabel(l, membership.role),
        onSignOut: session.signOut,
      );
    },
  );
}
