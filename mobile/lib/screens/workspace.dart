import 'package:flutter/material.dart';

import '../demo/demo_store.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import 'dashboard.dart';
import 'management.dart';
import 'products.dart';
import 'sales.dart';

enum AppPage {
  dashboard,
  products,
  inventory,
  purchasing,
  sales,
  expenses,
  warranties,
  reports,
  administration,
}

String pageLabel(AppLocalizations l, AppPage page) => switch (page) {
  AppPage.dashboard => l.dashboard,
  AppPage.products => l.products,
  AppPage.inventory => l.inventory,
  AppPage.purchasing => l.purchasing,
  AppPage.sales => l.sales,
  AppPage.expenses => l.expenses,
  AppPage.warranties => l.warranties,
  AppPage.reports => l.reports,
  AppPage.administration => l.administration,
};

IconData pageIcon(AppPage page) => switch (page) {
  AppPage.dashboard => Icons.space_dashboard_outlined,
  AppPage.products => Icons.category_outlined,
  AppPage.inventory => Icons.inventory_2_outlined,
  AppPage.purchasing => Icons.local_shipping_outlined,
  AppPage.sales => Icons.shopping_bag_outlined,
  AppPage.expenses => Icons.account_balance_wallet_outlined,
  AppPage.warranties => Icons.verified_user_outlined,
  AppPage.reports => Icons.bar_chart_outlined,
  AppPage.administration => Icons.tune_outlined,
};

class Workspace extends StatefulWidget {
  const Workspace({
    super.key,
    required this.store,
    required this.languageCode,
    required this.onLanguageChanged,
  });
  final DemoStore store;
  final String languageCode;
  final ValueChanged<String> onLanguageChanged;

  @override
  State<Workspace> createState() => _WorkspaceState();
}

class _WorkspaceState extends State<Workspace> {
  AppPage _page = AppPage.dashboard;
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  void _navigate(AppPage page) {
    setState(() => _page = page);
    _scaffoldKey.currentState?.closeDrawer();
  }

  Future<void> _location(String location) async {
    if (widget.store.changeLocation(location)) return;
    final l = strings(context);
    if (await confirmAction(context, l.location, l.cartConflict) && mounted) {
      widget.store.changeLocation(location, discardCart: true);
    }
  }

  Widget _content() => switch (_page) {
    AppPage.dashboard => DashboardScreen(
      store: widget.store,
      onNavigate: _navigate,
    ),
    AppPage.products => ProductsScreen(store: widget.store),
    AppPage.inventory => ProductsScreen(store: widget.store, inventory: true),
    AppPage.sales => SalesScreen(store: widget.store),
    _ => ManagementScreen(
      page: _page,
      store: widget.store,
      languageCode: widget.languageCode,
      onLanguageChanged: widget.onLanguageChanged,
    ),
  };

  Widget _navigation({required bool expanded}) {
    final l = strings(context);
    return Container(
      width: expanded ? 236 : 80,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(right: BorderSide(color: AppColors.line)),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
              child: Row(
                mainAxisAlignment: expanded
                    ? MainAxisAlignment.start
                    : MainAxisAlignment.center,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.blue,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.layers_outlined,
                      color: Colors.white,
                    ),
                  ),
                  if (expanded) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        l.appName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 18,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (expanded)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    l.workspace,
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  for (final page in AppPage.values)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Tooltip(
                        message: pageLabel(l, page),
                        excludeFromSemantics: expanded,
                        child: Material(
                          color: _page == page
                              ? AppColors.tint
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                          child: InkWell(
                            key: ValueKey('nav-${page.name}'),
                            onTap: () => _navigate(page),
                            borderRadius: BorderRadius.circular(12),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 14,
                              ),
                              child: Row(
                                mainAxisAlignment: expanded
                                    ? MainAxisAlignment.start
                                    : MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    pageIcon(page),
                                    color: _page == page
                                        ? AppColors.blue
                                        : AppColors.muted,
                                  ),
                                  if (expanded) ...[
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        pageLabel(l, page),
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: _page == page
                                              ? FontWeight.w600
                                              : FontWeight.w400,
                                          color: _page == page
                                              ? AppColors.blue
                                              : AppColors.ink,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (expanded)
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Divider(),
                    const SizedBox(height: 16),
                    Text(
                      l.owner,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.store,
    builder: (context, _) => LayoutBuilder(
      builder: (context, constraints) {
        final l = strings(context);
        final compact = constraints.maxWidth < 600;
        final expanded =
            constraints.maxWidth >= 1080 &&
            MediaQuery.textScalerOf(context).scale(1) < 1.7;
        return Scaffold(
          key: _scaffoldKey,
          drawer: compact ? Drawer(child: _navigation(expanded: true)) : null,
          body: Row(
            children: [
              if (!compact) _navigation(expanded: expanded),
              Expanded(
                child: SafeArea(
                  child: Column(
                    children: [
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: compact ? 12 : 24,
                          vertical: 12,
                        ),
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          border: Border(
                            bottom: BorderSide(color: AppColors.line),
                          ),
                        ),
                        child: Wrap(
                          spacing: 12,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            if (compact)
                              IconButton(
                                tooltip: l.menu,
                                icon: const Icon(Icons.menu),
                                onPressed: () =>
                                    _scaffoldKey.currentState?.openDrawer(),
                              ),
                            Text(
                              pageLabel(l, _page),
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            PopupMenuButton<String>(
                              key: const ValueKey('location-selector'),
                              tooltip: l.location,
                              initialValue: widget.store.location,
                              onSelected: _location,
                              itemBuilder: (context) => DemoStore.locationIds
                                  .map(
                                    (id) => PopupMenuItem(
                                      value: id,
                                      child: Text(locationLabel(l, id)),
                                    ),
                                  )
                                  .toList(),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 12,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.storefront_outlined,
                                      size: 20,
                                      color: AppColors.muted,
                                    ),
                                    const SizedBox(width: 8),
                                    Flexible(
                                      child: Text(
                                        locationLabel(l, widget.store.location),
                                        style: const TextStyle(fontSize: 14),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    const Icon(Icons.expand_more, size: 18),
                                  ],
                                ),
                              ),
                            ),
                            PopupMenuButton<String>(
                              key: const ValueKey('language-selector'),
                              tooltip: l.language,
                              initialValue: widget.languageCode,
                              onSelected: widget.onLanguageChanged,
                              itemBuilder: (context) => [
                                PopupMenuItem(
                                  value: 'ru',
                                  child: Text(l.languageRussian),
                                ),
                                PopupMenuItem(
                                  value: 'tk',
                                  child: Text(l.languageTurkmen),
                                ),
                              ],
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 12,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.translate,
                                      size: 20,
                                      color: AppColors.blue,
                                    ),
                                    const SizedBox(width: 8),
                                    Flexible(
                                      child: Text(
                                        widget.languageCode == 'ru'
                                            ? l.languageRussian
                                            : l.languageTurkmen,
                                        style: const TextStyle(fontSize: 14),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 10,
                        ),
                        color: AppColors.tint,
                        child: Text(
                          l.demoNotice,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF1D4ED8),
                          ),
                        ),
                      ),
                      Expanded(child: _content()),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    ),
  );
}
