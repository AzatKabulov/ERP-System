import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'app_icons.dart';
import 'bottom_navigation.dart';

import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import 'common.dart';
import 'glass.dart';
import 'motion.dart';
import 'pwa_viewport.dart';

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

  // The platform owner's pages (see features/platform/). A shop never lists these.
  platformOverview,
  platformClients,
  platformSupport,
  platformNotices,
}

/// What a shop's people can open, in menu order.
const storePages = [
  AppPage.dashboard,
  AppPage.products,
  AppPage.sales,
  AppPage.inventory,
  AppPage.expenses,
  AppPage.warranties,
  AppPage.reports,
  AppPage.administration,
];

/// What the platform owner can open, in menu order (settings are the shared page).
const platformPages = [
  AppPage.platformOverview,
  AppPage.platformClients,
  AppPage.platformSupport,
  AppPage.platformNotices,
  AppPage.administration,
];

String pageLabel(AppLocalizations l, AppPage page) => switch (page) {
  AppPage.dashboard => l.dashboard,
  AppPage.products => l.products,
  AppPage.inventory => l.inventory,
  AppPage.sales => l.sales,
  AppPage.expenses => l.expenses,
  AppPage.warranties => l.warranties,
  AppPage.reports => l.reports,
  AppPage.administration => l.administration,
  AppPage.platformOverview => l.pfOverview,
  AppPage.platformClients => l.pfClients,
  AppPage.platformSupport => l.pfSupport,
  AppPage.platformNotices => l.pfNotices,
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
  AppPage.platformOverview => AppIcons.overview,
  AppPage.platformClients => AppIcons.user,
  AppPage.platformSupport => AppIcons.chat,
  AppPage.platformNotices => AppIcons.mail,
};

/// The four modules of the phone's bottom bar; every other module is behind its "More" tab.
const _phoneTabs = [
  AppPage.dashboard,
  AppPage.products,
  AppPage.sales,
  AppPage.inventory,
];

/// Width below which the layout is a phone's: no side navigation, a bottom bar and a "More" tab.
const _phoneBreakpoint = 768.0;

/// The height of the floating tab bar, and the gap around it.
const _barHeight = 74.0;
const _barGap = 12.0;

/// The application frame shared by the demonstration workspace and the real one. The page fills
/// the whole screen and scrolls beneath frosted layers: a top bar (the shop, the help, on a
/// computer the page name, language and role) with any banners, and on a phone a floating tab bar
/// (on a tablet or computer a floating side navigation).
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
    this.phoneTabs = _phoneTabs,
  });

  /// The destinations on a phone's bottom bar; the rest are behind its "More" tab.
  final List<AppPage> phoneTabs;

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
  /// The measured height of the top layer (bar and banners), so the page can leave room.
  double _top = 0;

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
    height: 56,
    child: Row(
      children: [
        const SizedBox(width: 8),
        BrandMark(l.appName.characters.first.toUpperCase()),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            l.appName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 16,
              letterSpacing: -0.3,
              height: 1.2,
              color: AppColors.ink,
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
          onTap: () => widget.onNavigate(page),
          borderRadius: BorderRadius.circular(14),
          hoverColor: AppColors.blue.withValues(alpha: 0.06),
          child: AnimatedContainer(
            duration: duration,
            curve: AppMotion.arrive,
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: selected
                  ? AppColors.blue.withValues(
                      alpha: AppColors.isDark ? 0.2 : 0.1,
                    )
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
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
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                      color: selected ? AppColors.blue : AppColors.neutral,
                    ),
                    child: Text(pageLabel(l, page)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _user(AppLocalizations l) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Divider(height: 1, color: AppColors.line),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  gradient: AppGradients.brand,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  _initials,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
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
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: AppColors.ink,
                      ),
                    ),
                    if (widget.roleName != null)
                      Text(
                        widget.roleName!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: AppColors.muted),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (widget.onSignOut != null) ...[
          const SizedBox(height: 8),
          InkWell(
            key: const ValueKey('sidebar-sign-out'),
            onTap: widget.onSignOut,
            borderRadius: BorderRadius.circular(12),
            hoverColor: AppColors.blue.withValues(alpha: 0.06),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  children: [
                    AppIcon(AppIcons.logout, size: 20, color: AppColors.muted),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        l.signOut,
                        style: TextStyle(
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
        ],
      ],
    ),
  );

  /// The side navigation of tablets and computers: a floating pane of glass.
  Widget _navigation(double width) {
    final l = strings(context);
    return Padding(
      padding: const EdgeInsets.all(12),
      child: SizedBox(
        width: width,
        child: GlassSurface(
          radius: 24,
          child: SafeArea(
            minimum: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _brand(l),
                const SizedBox(height: 20),
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

  /// The top layer: the bar, then any banners, all on one pane of glass that the page scrolls
  /// beneath.
  Widget _topLayer(
    AppLocalizations l, {
    required bool phone,
    required bool showRole,
  }) {
    final safeTop = MediaQuery.paddingOf(context).top;
    if (phone) {
      return Column(
        key: const ValueKey('app-top-layer'),
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(height: safeTop),
          ...widget.banners,
        ],
      );
    }

    final safeSides = PwaAreas.enabledOf(context)
        ? MediaQuery.paddingOf(context)
        : EdgeInsets.zero;
    final title = Text(
      pageLabel(l, widget.page),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
        color: AppColors.ink,
      ),
    );
    final role = widget.roleName == null || !showRole
        ? null
        : TopbarControl(
            key: const ValueKey('role-control'),
            icon: AppIcons.user,
            text: widget.roleName!,
          );
    final help = widget.onHelp == null
        ? null
        : IconButton(
            key: const ValueKey('help-button'),
            tooltip: l.helpTitle,
            icon: AppIcon(AppIcons.help, size: 22, color: AppColors.neutral),
            onPressed: widget.onHelp,
          );
    final bar = phone
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
              ?help,
            ],
          )
        : Row(
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
                      ?help,
                      ?role,
                    ],
                  ),
                ),
              ),
            ],
          );
    return GlassSurface(
      key: const ValueKey('app-top-layer'),
      radius: 0,
      blur: 26,
      mobileBlur: 0,
      shadow: false,
      rim: false,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.line)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                (phone ? 12 : 28) + safeSides.left,
                safeTop + (phone ? 6 : 10),
                (phone ? 4 : 28) + safeSides.right,
                phone ? 6 : 10,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: bar,
              ),
            ),
            ...widget.banners,
            if (widget.banners.isNotEmpty) const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  /// The tab that stands for every page not on the bar.
  bool get _moreSelected => !widget.phoneTabs.contains(widget.page);

  /// The pages that are not on the bar, and help and sign-out, as one list: what used to hide
  /// behind a menu button now sits behind a labelled tab people can see.
  Future<void> _openMore() {
    final l = strings(context);
    final others = [
      for (final p in widget.pages)
        if (!widget.phoneTabs.contains(p)) p,
    ];
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: false,
      sheetAnimationStyle: AnimationStyle(
        duration: AppMotion.of(context, const Duration(milliseconds: 280)),
        reverseDuration: AppMotion.of(
          context,
          const Duration(milliseconds: 220),
        ),
      ),
      backgroundColor: Colors.transparent,
      elevation: 0,
      barrierColor: AppColors.scrim,
      builder: (sheet) => GlassSurface(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        strong: true,
        blur: 30,
        shadow: false,
        child: SafeArea(
          // A list, not a column: a sheet is at most 9/16 of the screen high, and large system
          // text makes the rows taller, so it must be able to scroll.
          child: SingleChildScrollView(
            key: const ValueKey('more-sheet'),
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: AppColors.lineStrong,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                  child: widget.locationControl,
                ),
                for (final page in others)
                  _MoreRow(
                    key: ValueKey('more-${page.name}'),
                    icon: pageIcon(page),
                    label: pageLabel(l, page),
                    selected: widget.page == page,
                    onTap: () {
                      Navigator.of(sheet).pop();
                      widget.onNavigate(page);
                    },
                  ),
                if (widget.onHelp != null)
                  _MoreRow(
                    key: const ValueKey('more-help'),
                    icon: AppIcons.help,
                    label: l.helpTitle,
                    onTap: () {
                      Navigator.of(sheet).pop();
                      widget.onHelp!();
                    },
                  ),
                if (widget.onSignOut != null) ...[
                  Divider(height: 16, color: AppColors.line),
                  _MoreRow(
                    key: const ValueKey('more-sign-out'),
                    icon: AppIcons.logout,
                    label: widget.userName.isEmpty
                        ? l.signOut
                        : '${l.signOut} · ${widget.userName}',
                    onTap: () {
                      Navigator.of(sheet).pop();
                      widget.onSignOut!();
                    },
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The floating tab bar of a phone.
  Widget _bottomBar(AppLocalizations l) {
    final tabs = [
      for (final p in widget.phoneTabs)
        if (widget.pages.contains(p)) p,
    ];
    final hasMore = widget.pages.any((p) => !widget.phoneTabs.contains(p));

    final selected = tabs.indexOf(widget.page);
    return SlidingBottomNavigation(
      key: const ValueKey('phone-navigation'),
      tabs: [
        for (final page in tabs)
          BottomTab(
            key: ValueKey('tab-${page.name}'),
            label: pageLabel(l, page),
            icon: pageIcon(page),
          ),
        if (hasMore)
          BottomTab(
            key: const ValueKey('tab-more'),
            label: l.navMore,
            icon: AppIcons.dots,
            reselect: true,
          ),
      ],
      selected: _moreSelected ? tabs.length : math.max(0, selected),
      onSelected: (index) {
        if (index < tabs.length) {
          widget.onNavigate(tabs[index]);
        } else {
          _openMore();
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final l = strings(context);
      final phone = constraints.maxWidth < _phoneBreakpoint;
      final media = MediaQuery.of(context);
      final keyboardOpen = media.viewInsets.bottom > 0;
      final showBar = phone && !keyboardOpen;
      final bottomInset = showBar
          ? _barHeight + _barGap + math.max(media.padding.bottom, 8) + 8
          : 0.0;
      final content = Stack(
        children: [
          Positioned.fill(
            child: ChromeInsets(
              top: _top,
              bottom: bottomInset,
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
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _Measured(
              onHeight: (h) {
                if ((h - _top).abs() > 0.5) setState(() => _top = h);
              },
              child: _topLayer(
                l,
                phone: phone,
                showRole: constraints.maxWidth >= 1100,
              ),
            ),
          ),
          if (showBar)
            Positioned(
              left:
                  _barGap +
                  (PwaAreas.enabledOf(context) ? media.padding.left : 0),
              right:
                  _barGap +
                  (PwaAreas.enabledOf(context) ? media.padding.right : 0),
              bottom: _barGap + math.max(media.padding.bottom - 4, 0),
              child: _bottomBar(l),
            ),
        ],
      );
      return Scaffold(
        backgroundColor: Colors.transparent,
        body: phone
            ? content
            : Row(
                children: [
                  _navigation(constraints.maxWidth >= 1200 ? 224 : 204),
                  Expanded(child: content),
                ],
              ),
      );
    },
  );
}

/// One row of the phone's "More" list.
class _MoreRow extends StatelessWidget {
  const _MoreRow({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.selected = false,
  });

  final AppIconData icon;
  final String label;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 56),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.blue.withValues(alpha: AppColors.isDark ? 0.2 : 0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            AppIcon(icon, color: selected ? AppColors.blue : AppColors.muted),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? AppColors.blue : AppColors.ink,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Reports the height of its child whenever it changes (the banners come and go).
class _Measured extends StatefulWidget {
  const _Measured({required this.child, required this.onHeight});

  final Widget child;
  final ValueChanged<double> onHeight;

  @override
  State<_Measured> createState() => _MeasuredState();
}

class _MeasuredState extends State<_Measured> {
  final _key = GlobalKey();

  void _report() {
    if (!mounted) return;
    final box = _key.currentContext?.findRenderObject();
    if (box is RenderBox && box.hasSize) widget.onHeight(box.size.height);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _report());
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _report());
    return KeyedSubtree(key: _key, child: widget.child);
  }
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
    duration: const Duration(milliseconds: 220),
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
    if (AppMotion.reduced(context)) {
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
