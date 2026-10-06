import 'package:flutter/material.dart';

import '../demo/demo_store.dart';
import '../theme/app_theme.dart';
import '../widgets/app_shell.dart';
import '../widgets/common.dart';
import 'dashboard.dart';
import 'management.dart';
import 'products.dart';
import 'sales.dart';

export '../widgets/app_shell.dart' show AppPage, pageIcon, pageLabel;

/// The demonstration workspace: every screen runs on in-memory sample data
/// (`DemoStore`) and says so with a visible banner.
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

  void _navigate(AppPage page) => setState(() => _page = page);

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

  Widget _locationSelector(BuildContext context) {
    final l = strings(context);
    return PopupMenuButton<String>(
      key: const ValueKey('location-selector'),
      tooltip: l.location,
      initialValue: widget.store.location,
      onSelected: _location,
      itemBuilder: (context) => DemoStore.locationIds
          .map(
            (id) => PopupMenuItem(value: id, child: Text(locationLabel(l, id))),
          )
          .toList(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
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
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.store,
    builder: (context, _) {
      final l = strings(context);
      return AppShell(
        pages: AppPage.values,
        page: _page,
        onNavigate: _navigate,
        body: _content(),
        languageCode: widget.languageCode,
        onLanguageChanged: widget.onLanguageChanged,
        locationControl: _locationSelector(context),
        banners: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            color: AppColors.tint,
            child: Text(
              l.demoNotice,
              style: const TextStyle(fontSize: 12, color: Color(0xFF1D4ED8)),
            ),
          ),
        ],
        sidebarFooter: Text(
          l.owner,
          style: const TextStyle(fontSize: 13, color: AppColors.muted),
        ),
      );
    },
  );
}
