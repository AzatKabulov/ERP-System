import 'package:flutter/material.dart';
import 'app_icons.dart';

import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import 'common.dart';

enum AppPage {
  dashboard,
  products,
  inventory,
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
  AppPage.sales => l.sales,
  AppPage.expenses => l.expenses,
  AppPage.warranties => l.warranties,
  AppPage.reports => l.reports,
  AppPage.administration => l.administration,
};

AppIconData pageIcon(AppPage page) => switch (page) {
  AppPage.dashboard => AppIcons.overview,
  AppPage.products => AppIcons.box,
  AppPage.inventory => AppIcons.stock,
  AppPage.sales => AppIcons.sale,
  AppPage.expenses => AppIcons.expense,
  AppPage.warranties => AppIcons.shield,
  AppPage.reports => AppIcons.chart,
  AppPage.administration => AppIcons.settings,
};

/// The four modules of the phone's bottom bar; every other module is behind the menu button.
const _phoneTabs = [
  AppPage.dashboard,
  AppPage.products,
  AppPage.sales,
  AppPage.inventory,
];

/// Width below which the layout is a phone's: no side navigation, a bottom bar and a menu.
const _phoneBreakpoint = 768.0;

/// The application frame shared by the demonstration workspace and the real one: a white side
/// navigation (a bottom bar and a menu drawer on phones), the top bar with the page name, the
/// location, the language switch and the role, optional banners, and the page body.
class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.pages,
    required this.page,
    required this.onNavigate,
    required this.body,
    required this.languageCode,
    required this.onLanguageChanged,
    required this.locationControl,
    this.banners = const [],
    this.userName = '',
    this.roleName,
    this.onSignOut,
  });

  /// Destinations to offer, in order.
  final List<AppPage> pages;
  final AppPage page;
  final ValueChanged<AppPage> onNavigate;
  final Widget body;
  final String languageCode;
  final ValueChanged<String> onLanguageChanged;

  /// The location (or other context) selector shown in the top bar.
  final Widget locationControl;

  /// Full-width notices between the top bar and the page (demo notice, offline...).
  final List<Widget> banners;

  /// Who is signed in, shown at the bottom of the navigation.
  final String userName;
  final String? roleName;

  /// Offered under the person's name when given.
  final VoidCallback? onSignOut;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  void _navigate(AppPage page) {
    widget.onNavigate(page);
    _scaffoldKey.currentState?.closeDrawer();
  }

  String get _initials {
    final words = widget.userName
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.isEmpty) return '';
    return words.take(2).map((w) => w.characters.first.toUpperCase()).join();
  }

  Widget _brand(AppLocalizations l) => SizedBox(
    height: 48,
    child: Row(
      children: [
        const SizedBox(width: 10),
        BrandMark(l.appName.characters.first.toUpperCase()),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            l.appName,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 16,
              letterSpacing: -0.32,
              height: 1.2,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _navItem(AppLocalizations l, AppPage page) {
    final selected = widget.page == page;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: selected ? AppColors.surfaceMuted : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          key: ValueKey('nav-${page.name}'),
          onTap: () => _navigate(page),
          borderRadius: BorderRadius.circular(10),
          hoverColor: AppColors.surfaceSoft,
          child: Stack(
            children: [
              if (selected)
                Positioned(
                  left: 0,
                  top: 13,
                  bottom: 13,
                  child: ExcludeSemantics(
                    child: Container(
                      width: 2,
                      decoration: BoxDecoration(
                        color: AppColors.brass,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      AppIcon(
                        pageIcon(page),
                        size: 20,
                        color: selected ? AppColors.ink : AppColors.muted,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          pageLabel(l, page),
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: selected
                                ? FontWeight.w600
                                : FontWeight.w500,
                            color: selected ? AppColors.ink : AppColors.muted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _user(AppLocalizations l) => Container(
    decoration: const BoxDecoration(
      border: Border(top: BorderSide(color: AppColors.line)),
    ),
    padding: const EdgeInsets.only(top: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: AppColors.ink,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  _initials,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.userName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    if (widget.roleName != null)
                      Text(
                        widget.roleName!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
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
        if (widget.onSignOut != null) ...[
          const SizedBox(height: 8),
          Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              key: const ValueKey('sidebar-sign-out'),
              onTap: widget.onSignOut,
              borderRadius: BorderRadius.circular(10),
              hoverColor: AppColors.surfaceSoft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      const AppIcon(
                        AppIcons.logout,
                        size: 20,
                        color: AppColors.muted,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          l.signOut,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: AppColors.muted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    ),
  );

  /// The navigation column, shared by the side navigation and the phone's drawer.
  Widget _navigation(double width, {VoidCallback? onClose}) {
    final l = strings(context);
    return Container(
      width: width,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(right: BorderSide(color: AppColors.line)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: _brand(l)),
                if (onClose != null)
                  IconButton(
                    tooltip: l.menu,
                    icon: const AppIcon(AppIcons.close),
                    onPressed: onClose,
                  ),
              ],
            ),
            const SizedBox(height: 28),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    for (final page in widget.pages) _navItem(l, page),
                  ],
                ),
              ),
            ),
            _user(l),
          ],
        ),
      ),
    );
  }

  Widget _languageSwitch() => AppSegmented<String>(
    key: const ValueKey('language-selector'),
    keyPrefix: 'language',
    options: const [('ru', 'RU'), ('tk', 'TM')],
    value: widget.languageCode,
    onChanged: widget.onLanguageChanged,
  );

  Widget _topbar(
    AppLocalizations l, {
    required bool phone,
    required bool showRole,
  }) {
    final title = Text(
      pageLabel(l, widget.page),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    );
    final role = widget.roleName == null || !showRole
        ? null
        : TopbarControl(
            key: const ValueKey('role-control'),
            icon: AppIcons.user,
            text: widget.roleName!,
          );
    return Container(
      padding: EdgeInsets.fromLTRB(phone ? 8 : 32, 12, phone ? 12 : 32, 12),
      decoration: const BoxDecoration(
        color: Color(0xFFF6F3EE),
        border: Border(bottom: BorderSide(color: AppColors.line)),
      ),
      child: phone
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    IconButton(
                      tooltip: l.menu,
                      icon: const AppIcon(AppIcons.menu),
                      onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                    ),
                    const SizedBox(width: 4),
                    Expanded(child: title),
                    const SizedBox(width: 8),
                    _languageSwitch(),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 8, top: 4),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: widget.locationControl,
                  ),
                ),
              ],
            )
          : ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Row(
                children: [
                  Expanded(flex: 2, child: title),
                  const SizedBox(width: 16),
                  Flexible(
                    flex: 4,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        alignment: WrapAlignment.end,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          widget.locationControl,
                          _languageSwitch(),
                          ?role,
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _bottomBar(AppLocalizations l) {
    final tabs = [
      for (final p in _phoneTabs)
        if (widget.pages.contains(p)) p,
    ];
    return Container(
      key: const ValueKey('phone-navigation'),
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.line)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 60,
          child: Row(
            children: [
              for (final page in tabs)
                Expanded(
                  child: Semantics(
                    button: true,
                    selected: widget.page == page,
                    child: Material(
                      color: widget.page == page
                          ? AppColors.tint
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                      child: InkWell(
                        key: ValueKey('tab-${page.name}'),
                        borderRadius: BorderRadius.circular(10),
                        onTap: () => widget.onNavigate(page),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            AppIcon(
                              pageIcon(page),
                              size: 22,
                              color: widget.page == page
                                  ? AppColors.blue
                                  : AppColors.muted,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              pageLabel(l, page),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: widget.page == page
                                    ? AppColors.blue
                                    : AppColors.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final l = strings(context);
      final phone = constraints.maxWidth < _phoneBreakpoint;
      final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
      return Scaffold(
        key: _scaffoldKey,
        drawer: phone
            ? Drawer(
                width: 320,
                backgroundColor: Colors.white,
                shape: const RoundedRectangleBorder(),
                child: _navigation(
                  320,
                  onClose: () => _scaffoldKey.currentState?.closeDrawer(),
                ),
              )
            : null,
        bottomNavigationBar: phone && !keyboardOpen ? _bottomBar(l) : null,
        body: Row(
          children: [
            if (!phone) _navigation(constraints.maxWidth >= 1200 ? 216 : 196),
            Expanded(
              child: SafeArea(
                bottom: false,
                child: Column(
                  children: [
                    _topbar(
                      l,
                      phone: phone,
                      showRole: constraints.maxWidth >= 1100,
                    ),
                    ...widget.banners,
                    Expanded(
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1500),
                          child: widget.body,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}
