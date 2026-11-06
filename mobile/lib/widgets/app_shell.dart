import 'package:flutter/material.dart';
import 'app_icons.dart';

import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import 'common.dart';
import 'motion.dart';

/// The order is the order of the side menu and of the "More" list, and starts with the four
/// pages of the phone's bottom bar in the same order as the bar.
enum AppPage {
  dashboard,
  products,
  sales,
  inventory,
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

/// The four modules of the phone's bottom bar; every other module is behind its "More" tab.
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
    this.onHelp,
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

  /// Opens the how-to pages: a "?" in the top bar and an entry in the phone's "More" list.
  final VoidCallback? onHelp;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  void _navigate(AppPage page) => widget.onNavigate(page);

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
    final duration = AppMotion.of(context, AppMotion.base);
    final color = selected ? AppColors.blue : AppColors.muted;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          key: ValueKey('nav-${page.name}'),
          onTap: () => _navigate(page),
          borderRadius: BorderRadius.circular(12),
          hoverColor: AppColors.surfaceSoft,
          child: AnimatedContainer(
            duration: duration,
            curve: AppMotion.arrive,
            decoration: BoxDecoration(
              color: selected ? AppColors.tint : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Stack(
              children: [
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: ExcludeSemantics(
                      child: AnimatedContainer(
                        duration: duration,
                        curve: AppMotion.arrive,
                        width: 3,
                        height: selected ? 22 : 0,
                        decoration: const BoxDecoration(
                          color: AppColors.blue,
                          borderRadius: BorderRadius.horizontal(
                            right: Radius.circular(3),
                          ),
                        ),
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
                        TweenAnimationBuilder<Color?>(
                          tween: ColorTween(end: color),
                          duration: duration,
                          builder: (context, c, _) =>
                              AppIcon(pageIcon(page), size: 20, color: c),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: AnimatedDefaultTextStyle(
                            duration: duration,
                            style: TextStyle(
                              fontFamily: AppFonts.ui,
                              fontSize: 15,
                              fontWeight: selected
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                              color: selected
                                  ? AppColors.blue
                                  : AppColors.muted,
                            ),
                            child: Text(pageLabel(l, page)),
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
                  gradient: AppGradients.brand,
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

  /// The side navigation of tablets and computers.
  Widget _navigation(double width) {
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
            _brand(l),
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
      padding: EdgeInsets.fromLTRB(
        phone ? 12 : 32,
        phone ? 8 : 12,
        phone ? 4 : 32,
        phone ? 8 : 12,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFFF6F3EE),
        border: Border(bottom: BorderSide(color: AppColors.line)),
      ),
      child: phone
          // One slim row: whose shop this is, and the help. The page's own name is on the page
          // (not repeated here) and the language is set once, in Settings.
          ? Row(
              children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: widget.locationControl,
                  ),
                ),
                if (widget.onHelp != null)
                  IconButton(
                    key: const ValueKey('help-button'),
                    tooltip: l.helpTitle,
                    icon: const AppIcon(AppIcons.help, size: 22),
                    onPressed: widget.onHelp,
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
                          if (widget.onHelp != null)
                            IconButton(
                              key: const ValueKey('help-button'),
                              tooltip: l.helpTitle,
                              icon: const AppIcon(AppIcons.help, size: 22),
                              onPressed: widget.onHelp,
                            ),
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

  /// The tab that stands for every page not on the bar.
  bool get _moreSelected => !_phoneTabs.contains(widget.page);

  /// The pages that are not on the bar, and help and sign-out, as one list: what used to hide
  /// behind a menu button now sits behind a labelled tab people can see.
  Future<void> _openMore() {
    final l = strings(context);
    final others = [
      for (final p in widget.pages)
        if (!_phoneTabs.contains(p)) p,
    ];
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (sheet) => SafeArea(
        // A list, not a column: a sheet is at most 9/16 of the screen high, and large system
        // text makes the rows taller, so it must be able to scroll.
        child: ListView(
          key: const ValueKey('more-sheet'),
          shrinkWrap: true,
          children: [
            for (final page in others)
              ListTile(
                key: ValueKey('more-${page.name}'),
                minTileHeight: 56,
                leading: AppIcon(
                  pageIcon(page),
                  color: widget.page == page ? AppColors.blue : AppColors.muted,
                ),
                title: Text(
                  pageLabel(l, page),
                  style: TextStyle(
                    fontWeight: widget.page == page
                        ? FontWeight.w700
                        : FontWeight.w500,
                    color: widget.page == page ? AppColors.blue : AppColors.ink,
                  ),
                ),
                selected: widget.page == page,
                onTap: () {
                  Navigator.of(sheet).pop();
                  widget.onNavigate(page);
                },
              ),
            if (widget.onHelp != null)
              ListTile(
                key: const ValueKey('more-help'),
                minTileHeight: 56,
                leading: const AppIcon(AppIcons.help, color: AppColors.muted),
                title: Text(l.helpTitle),
                onTap: () {
                  Navigator.of(sheet).pop();
                  widget.onHelp!();
                },
              ),
            if (widget.onSignOut != null) ...[
              const Divider(height: 1),
              ListTile(
                key: const ValueKey('more-sign-out'),
                minTileHeight: 56,
                leading: const AppIcon(AppIcons.logout, color: AppColors.muted),
                title: Text(
                  widget.userName.isEmpty
                      ? l.signOut
                      : '${l.signOut} · ${widget.userName}',
                ),
                onTap: () {
                  Navigator.of(sheet).pop();
                  widget.onSignOut!();
                },
              ),
            ],
            const SizedBox(height: 8),
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
    final hasMore = widget.pages.any((p) => !_phoneTabs.contains(p));

    Widget tab({
      required Key key,
      required String label,
      required AppIconData icon,
      required bool selected,
      required VoidCallback onTap,
    }) => Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            key: key,
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedContainer(
                  duration: AppMotion.of(context, AppMotion.base),
                  curve: AppMotion.arrive,
                  width: selected ? 56 : 36,
                  height: 30,
                  decoration: BoxDecoration(
                    color: selected ? AppColors.tint : Colors.transparent,
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Center(
                    child: TweenAnimationBuilder<Color?>(
                      tween: ColorTween(
                        end: selected ? AppColors.blue : AppColors.muted,
                      ),
                      duration: AppMotion.of(context, AppMotion.base),
                      builder: (context, c, _) =>
                          AppIcon(icon, size: 22, color: c),
                    ),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: selected ? AppColors.blue : AppColors.muted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

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
          height: 72,
          child: Row(
            children: [
              for (final page in tabs)
                tab(
                  key: ValueKey('tab-${page.name}'),
                  label: pageLabel(l, page),
                  icon: pageIcon(page),
                  selected: widget.page == page,
                  onTap: () => widget.onNavigate(page),
                ),
              if (hasMore)
                tab(
                  key: const ValueKey('tab-more'),
                  label: l.navMore,
                  icon: AppIcons.dots,
                  selected: _moreSelected,
                  onTap: _openMore,
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
                          child: KeyedSubtree(
                            key: ValueKey(widget.page),
                            child: _PageEnter(child: widget.body),
                          ),
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

/// A page arriving: a fade and a short rise, played when the page is first built. Only the new
/// page animates (the old one is gone at once), so nothing waits and nothing overlaps.
class _PageEnter extends StatefulWidget {
  const _PageEnter({required this.child});
  final Widget child;

  @override
  State<_PageEnter> createState() => _PageEnterState();
}

class _PageEnterState extends State<_PageEnter>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppMotion.slow,
  );
  late final Animation<double> _curve = CurvedAnimation(
    parent: _controller,
    curve: AppMotion.arrive,
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (AppMotion.skipEntrance(context)) {
      _controller.value = 1;
    } else {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: Tween<double>(begin: 0.0, end: 1).animate(_curve),
    child: SlideTransition(
      position: Tween(
        begin: const Offset(0, 0.015),
        end: Offset.zero,
      ).animate(_curve),
      child: widget.child,
    ),
  );
}
