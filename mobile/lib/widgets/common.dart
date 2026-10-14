import 'package:flutter/material.dart';
import 'app_icons.dart';

import '../demo/demo_store.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';

AppLocalizations strings(BuildContext context) => AppLocalizations.of(context);

String money(int minor) {
  final absolute = minor.abs();
  final integer = (absolute ~/ 100).toString().replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => '\u00a0',
  );
  final decimal = (absolute % 100).toString().padLeft(2, '0');
  return '${minor < 0 ? '−' : ''}$integer,$decimal\u00a0TMT';
}

int? parseMinor(String input) {
  final normalized = input
      .trim()
      .replaceAll(' ', '')
      .replaceAll('\u00a0', '')
      .replaceAll(',', '.');
  if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(normalized)) return null;
  final parts = normalized.split('.');
  final major = int.tryParse(parts[0]);
  if (major == null || major > 999999999) return null;
  return major * 100 +
      (parts.length == 1 ? 0 : int.parse(parts[1].padRight(2, '0')));
}

String locationLabel(AppLocalizations l, String id) => switch (id) {
  'warehouse' => l.warehouse,
  'branch' => l.branch,
  _ => l.store,
};

String categoryLabel(AppLocalizations l, ProductCategory category) =>
    switch (category) {
      ProductCategory.filters => l.filters,
      ProductCategory.brakes => l.brakes,
      ProductCategory.oils => l.oils,
      ProductCategory.electrical => l.electrical,
    };

AppIconData categoryIcon(ProductCategory category) => switch (category) {
  ProductCategory.filters => AppIcons.filter,
  ProductCategory.brakes => AppIcons.brake,
  ProductCategory.oils => AppIcons.drop,
  ProductCategory.electrical => AppIcons.flash,
};

//// A white card: hairline border and the two-layer low-spread shadow. With [onTap] it is a
/// button (ink ripple on the card, a stronger border on hover).
class SurfaceCard extends StatefulWidget {
  const SurfaceCard({
    super.key,
    required this.child,
    this.padding = 20,
    this.onTap,
    this.flat = false,
    this.featured = false,
  });
  final Widget child;
  final double padding;
  final VoidCallback? onTap;

  /// No shadow, for dense lists where many cards sit together.
  final bool flat;

  /// A cobalt outline, for the one card that deserves emphasis.
  final bool featured;

  @override
  State<SurfaceCard> createState() => _SurfaceCardState();
}

class _SurfaceCardState extends State<SurfaceCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final interactive = widget.onTap != null;
    final radius = BorderRadius.circular(AppRadius.card);
    Widget body = Padding(
      padding: EdgeInsets.all(widget.padding),
      child: widget.child,
    );
    if (interactive) {
      body = InkWell(onTap: widget.onTap, borderRadius: radius, child: body);
    }
    final card = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: widget.flat ? null : AppShadows.card,
      ),
      child: Material(
        color: Colors.white,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(
            color: widget.featured
                ? AppColors.blue
                : interactive && _hover
                ? AppColors.lineStrong
                : AppColors.line,
            width: widget.featured ? 1.5 : 1,
          ),
        ),
        child: body,
      ),
    );
    if (!interactive) return card;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: card,
    );
  }
}

/// The main action: flat cobalt, darker on hover (the label never loses contrast), a press
/// scale of 0.98 and a separated focus ring.
class PrimaryButton extends StatefulWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.trailingIcon,
  });
  final String label;
  final VoidCallback? onPressed;
  final AppIconData? icon;

  /// An icon after the label (an arrow, for a step that leads on).
  final AppIconData? trailingIcon;

  @override
  State<PrimaryButton> createState() => _PrimaryButtonState();
}

class _PrimaryButtonState extends State<PrimaryButton> {
  bool _pressed = false;
  bool _focused = false;

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    return Listener(
      onPointerDown: (_) => _setPressed(true),
      onPointerUp: (_) => _setPressed(false),
      onPointerCancel: (_) => _setPressed(false),
      child: AnimatedScale(
        scale: enabled && _pressed ? 0.98 : 1,
        duration: const Duration(milliseconds: 120),
        child: Focus(
          canRequestFocus: false,
          skipTraversal: true,
          onFocusChange: (value) => setState(() => _focused = value),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.control),
              boxShadow: _focused && enabled
                  ? [
                      const BoxShadow(color: AppColors.canvas, spreadRadius: 2),
                      BoxShadow(
                        color: AppColors.blue.withValues(alpha: 0.4),
                        spreadRadius: 5,
                      ),
                    ]
                  : null,
            ),
            child: FilledButton(
              style:
                  FilledButton.styleFrom(
                    disabledBackgroundColor: AppColors.blue.withValues(
                      alpha: 0.42,
                    ),
                    disabledForegroundColor: Colors.white,
                  ).copyWith(
                    backgroundColor: WidgetStateProperty.resolveWith(
                      (states) =>
                          states.contains(WidgetState.pressed) ||
                              states.contains(WidgetState.hovered)
                          ? AppColors.blueDark
                          : AppColors.blue,
                    ),
                    overlayColor: const WidgetStatePropertyAll(
                      Colors.transparent,
                    ),
                  ),
              onPressed: widget.onPressed,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.icon != null) ...[
                    AppIcon(widget.icon!, size: 20),
                    const SizedBox(width: 8),
                  ],
                  Flexible(
                    child: Text(widget.label, textAlign: TextAlign.center),
                  ),
                  if (widget.trailingIcon != null) ...[
                    const SizedBox(width: 8),
                    AppIcon(widget.trailingIcon!, size: 20),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum StatusTone { success, warning, danger, info, neutral }

/// A status badge: a soft tone, a readable label and (usually) an icon. Colour never carries
/// the meaning alone.
class StatusPill extends StatelessWidget {
  const StatusPill({
    super.key,
    required this.label,
    this.warning = false,
    this.tone,
    this.icon,
  });
  final String label;

  /// Kept for older call sites: a warning badge, otherwise a success badge.
  final bool warning;
  final StatusTone? tone;
  final AppIconData? icon;

  @override
  Widget build(BuildContext context) {
    final t = tone ?? (warning ? StatusTone.warning : StatusTone.success);
    final (fg, bg) = switch (t) {
      StatusTone.success => (AppColors.success, AppColors.successTint),
      StatusTone.warning => (AppColors.warning, AppColors.warningTint),
      StatusTone.danger => (AppColors.danger, AppColors.dangerTint),
      StatusTone.info => (AppColors.blue, AppColors.tint),
      StatusTone.neutral => (AppColors.neutral, AppColors.surfaceMuted),
    };
    return Container(
      constraints: const BoxConstraints(minHeight: 28),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            AppIcon(icon!, size: 16, color: fg),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                color: fg,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The small uppercase label above a title or a form section.
class Eyebrow extends StatelessWidget {
  const Eyebrow(this.text, {super.key, this.color = AppColors.muted});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    style: TextStyle(
      color: color,
      fontSize: 12,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.2,
      height: 1.3,
    ),
  );
}

/// The title block of a page: an optional eyebrow, the serif title, a subtitle, and the page's
/// actions on the right (they drop below the title on a narrow screen).
class PageHead extends StatelessWidget {
  const PageHead({
    super.key,
    required this.title,
    this.eyebrow,
    this.subtitle,
    this.actions = const [],
    this.titleKey,
    this.titleWidget,
  });
  final String title;
  final String? eyebrow;
  final String? subtitle;
  final List<Widget> actions;
  final Key? titleKey;

  /// Replaces the plain title text (for a title with a coloured part).
  final Widget? titleWidget;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final narrow = constraints.maxWidth < 600;
      final heading = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (eyebrow != null) ...[
            Eyebrow(eyebrow!),
            const SizedBox(height: 8),
          ],
          titleWidget ??
              Text(
                title,
                key: titleKey,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontSize: narrow ? 24 : 28,
                ),
              ),
          if (subtitle != null) ...[
            const SizedBox(height: 8),
            Text(
              subtitle!,
              style: const TextStyle(color: AppColors.muted, fontSize: 14),
            ),
          ],
        ],
      );
      if (actions.isEmpty) return heading;
      final buttons = Wrap(spacing: 8, runSpacing: 8, children: actions);
      if (narrow) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [heading, const SizedBox(height: 16), buttons],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Flexible(child: heading),
          const SizedBox(width: 24),
          Flexible(
            flex: 3,
            child: Align(alignment: Alignment.centerRight, child: buttons),
          ),
        ],
      );
    },
  );
}

/// An icon on a soft neutral square, the leading mark of a list row.
class Glyph extends StatelessWidget {
  const Glyph(
    this.icon, {
    super.key,
    this.size = 48,
    this.background = AppColors.surfaceMuted,
    this.color = AppColors.neutral,
  });
  final AppIconData icon;
  final double size;
  final Color background;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Center(child: AppIcon(icon, color: color, size: 20)),
  );
}

/// The brand square: one serif letter on ink.
class BrandMark extends StatelessWidget {
  const BrandMark(this.letter, {super.key, this.size = 28, this.light = false});
  final String letter;
  final double size;

  /// On an ink surface the square turns white with an ink letter.
  final bool light;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: light ? Colors.white : AppColors.ink,
      borderRadius: BorderRadius.circular(size * 0.32),
    ),
    child: Text(
      letter,
      style: TextStyle(
        fontFamily: AppFonts.display,
        fontWeight: FontWeight.w600,
        fontSize: 16,
        height: 1,
        color: light ? AppColors.ink : Colors.white,
      ),
    ),
  );
}

/// The ink "inverted" surface of the one figure that matters most, with a thin brass hairline
/// near the top right corner.
class SpotlightCard extends StatelessWidget {
  const SpotlightCard({super.key, required this.child, this.padding = 28});
  final Widget child;
  final double padding;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: AppColors.ink,
      borderRadius: BorderRadius.circular(AppRadius.card),
      border: Border.all(color: AppColors.ink),
      boxShadow: AppShadows.card,
    ),
    child: Stack(
      children: [
        Positioned(
          top: 0,
          right: 32,
          child: ExcludeSemantics(
            child: Container(width: 56, height: 1, color: AppColors.brass),
          ),
        ),
        Padding(padding: EdgeInsets.all(padding), child: child),
      ],
    ),
  );
}

/// A control of the top bar and filter rows: a white box with a hairline, an icon, the current
/// value and (for a menu) a chevron.
class TopbarControl extends StatelessWidget {
  const TopbarControl({
    super.key,
    required this.icon,
    required this.text,
    this.chevron = false,
  });
  final AppIconData icon;
  final String text;
  final bool chevron;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(minHeight: 40),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppIcon(icon, size: 16, color: AppColors.ink),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
          if (chevron) ...[
            const SizedBox(width: 8),
            const AppIcon(AppIcons.chevron, size: 16, color: AppColors.ink),
          ],
        ],
      ),
    ),
  );
}

/// A drop-down filter drawn like the other filter controls.
class FilterSelect<T> extends StatelessWidget {
  const FilterSelect({
    super.key,
    this.fieldKey,
    required this.value,
    required this.items,
    required this.onChanged,
    this.hint,
    this.leading,
  });

  /// A small icon before the value (a building for a place).
  final AppIconData? leading;

  /// The key of the drop-down itself (the part a person taps and a screen reader reads).
  final Key? fieldKey;
  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;
  final Widget? hint;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 48),
    padding: const EdgeInsets.symmetric(horizontal: 12),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: AppColors.line),
    ),
    child: Row(
      children: [
        if (leading != null) ...[
          AppIcon(leading!, size: 16, color: AppColors.ink),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: DropdownButtonHideUnderline(
            child: DropdownButton<T>(
              key: fieldKey,
              isExpanded: true,
              value: value,
              hint: hint,
              items: items,
              onChanged: onChanged,
              borderRadius: BorderRadius.circular(AppRadius.control),
              icon: const AppIcon(
                AppIcons.chevron,
                size: 16,
                color: AppColors.ink,
              ),
              style: const TextStyle(
                fontFamily: AppFonts.ui,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.ink,
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

/// The segmented switch of the design (RU | TM, Cash | Card): a soft track, the chosen segment
/// raised in white.
class AppSegmented<T> extends StatelessWidget {
  const AppSegmented({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    this.keyPrefix,
    this.keyName,
  });

  /// (value, label) pairs.
  final List<(T, String)> options;
  final T value;
  final ValueChanged<T> onChanged;

  /// Each segment gets the key `ValueKey('<keyPrefix>-<name>')`; the name is [keyName] of the
  /// value, or the value itself.
  final String? keyPrefix;
  final String Function(T)? keyName;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 48),
    padding: const EdgeInsets.all(4),
    decoration: BoxDecoration(
      color: AppColors.surfaceSoft,
      borderRadius: BorderRadius.circular(AppRadius.control),
      border: Border.all(color: AppColors.line),
    ),
    child: IntrinsicHeight(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (v, label) in options)
            Flexible(
              child: _Segment(
                key: keyPrefix == null
                    ? null
                    : ValueKey('$keyPrefix-${keyName?.call(v) ?? v}'),
                label: label,
                selected: v == value,
                onTap: () => onChanged(v),
              ),
            ),
        ],
      ),
    ),
  );
}

class _Segment extends StatelessWidget {
  const _Segment({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(9),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        constraints: const BoxConstraints(minWidth: 76, minHeight: 40),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
          boxShadow: selected
              ? const [
                  BoxShadow(
                    color: Color(0x1A0D1311),
                    offset: Offset(0, 1),
                    blurRadius: 4,
                  ),
                ]
              : null,
        ),
        child: Center(
          widthFactor: 1,
          heightFactor: 1,
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: selected ? AppColors.ink : AppColors.muted,
            ),
          ),
        ),
      ),
    ),
  );
}

/// An informational strip (offline, pending, a note): a soft tone, an icon and a sentence.
class NoticeBanner extends StatelessWidget {
  const NoticeBanner({
    super.key,
    required this.text,
    this.icon = AppIcons.info,
    this.tone = StatusTone.info,
    this.action,
  });
  final String text;
  final AppIconData icon;
  final StatusTone tone;

  /// A button under the sentence (a retry, a link).
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final (fg, bg, edge) = switch (tone) {
      StatusTone.warning => (
        AppColors.warning,
        AppColors.warningTint,
        const Color(0xFFF0D5A9),
      ),
      StatusTone.danger => (
        AppColors.danger,
        AppColors.dangerTint,
        const Color(0xFFF3C9C5),
      ),
      StatusTone.success => (
        AppColors.success,
        AppColors.successTint,
        const Color(0xFFBFE0CB),
      ),
      _ => (AppColors.blue, AppColors.tint, const Color(0xFFCBD5FF)),
    };
    return Container(
      constraints: const BoxConstraints(minHeight: 52),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: edge),
      ),
      child: Row(
        children: [
          AppIcon(icon, size: 20, color: fg),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  text,
                  style: TextStyle(
                    color: fg,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    height: 1.4,
                  ),
                ),
                ?action,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Underlined tabs (a page's sections), with a cobalt line under the current one.
class AppTabs<T> extends StatelessWidget {
  const AppTabs({
    super.key,
    required this.tabs,
    required this.value,
    required this.onChanged,
    this.keyPrefix,
    this.keyName,
  });

  /// (value, label) pairs.
  final List<(T, String)> tabs;
  final T value;
  final ValueChanged<T> onChanged;

  /// Each tab gets the key `ValueKey('<keyPrefix>-<name>')`.
  final String? keyPrefix;
  final String Function(T)? keyName;

  @override
  Widget build(BuildContext context) => Container(
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: AppColors.line)),
    ),
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final (v, label) in tabs)
            Semantics(
              button: true,
              selected: v == value,
              child: InkWell(
                key: keyPrefix == null
                    ? null
                    : ValueKey('$keyPrefix-${keyName?.call(v) ?? v}'),
                onTap: () => onChanged(v),
                child: Container(
                  constraints: const BoxConstraints(minHeight: 48),
                  margin: const EdgeInsets.only(right: 24),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: v == value ? AppColors.blue : Colors.transparent,
                        width: 2,
                      ),
                    ),
                  ),
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: v == value ? AppColors.ink : AppColors.muted,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

/// A page's content arriving: a short fade with a 4 px rise. Skipped when the platform asks
/// for reduced motion.
class FadeUp extends StatelessWidget {
  const FadeUp({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      child: child,
      builder: (context, t, child) => t >= 1
          ? child!
          : Opacity(
              opacity: t,
              child: Transform.translate(
                offset: Offset(0, (1 - t) * 4),
                child: child,
              ),
            ),
    );
  }
}

class ProductMark extends StatelessWidget {
  const ProductMark({super.key, required this.product, this.size = 48});
  final Product product;
  final double size;

  @override
  Widget build(BuildContext context) => Glyph(
    categoryIcon(product.category),
    size: size,
    background: AppColors.surfaceMuted,
    color: AppColors.neutral,
  );
}

/// Nothing here yet: a calm line icon in a circle, one sentence, an optional hint.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.title,
    this.subtitle,
    this.icon = AppIcons.inbox,
  });
  final String title;
  final String? subtitle;
  final AppIconData icon;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
    child: Column(
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: AppColors.surfaceSoft,
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.line),
          ),
          child: Center(child: AppIcon(icon, size: 24, color: AppColors.muted)),
        ),
        const SizedBox(height: 16),
        Text(
          title,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: Text(
              subtitle!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.muted,
                fontSize: 13,
                height: 1.55,
              ),
            ),
          ),
        ],
      ],
    ),
  );
}

/// One figure: the label on top, the figure (tabular digits) and a short note at the bottom.
class MetricCard extends StatelessWidget {
  const MetricCard({
    super.key,
    required this.label,
    required this.value,
    this.meta,
    this.onTap,
    this.featured = false,
  });
  final String label;
  final String value;
  final String? meta;
  final VoidCallback? onTap;
  final bool featured;

  @override
  Widget build(BuildContext context) => SurfaceCard(
    onTap: onTap,
    featured: featured,
    child: ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 94),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppColors.muted,
              fontSize: 13,
              fontWeight: FontWeight.w500,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 16),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              softWrap: false,
              style: const TextStyle(
                fontSize: 24,
                fontVariations: [FontVariation.weight(650)],
                height: 1.2,
                letterSpacing: -0.96,
                color: AppColors.ink,
                fontFeatures: AppFonts.tabular,
              ),
            ),
          ),
          if (meta != null) ...[
            const SizedBox(height: 8),
            Text(
              meta!,
              style: const TextStyle(color: AppColors.muted, fontSize: 12),
            ),
          ],
        ],
      ),
    ),
  );
}

class AdaptiveGrid extends StatelessWidget {
  const AdaptiveGrid({
    super.key,
    required this.children,
    this.minimumWidth = 220,
    this.maxColumns = 4,
    this.gap = 16,
  });
  final List<Widget> children;
  final double minimumWidth;
  final int maxColumns;
  final double gap;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final count = ((constraints.maxWidth + gap) / (minimumWidth + gap))
          .floor()
          .clamp(1, maxColumns);
      final width = (constraints.maxWidth - (count - 1) * gap) / count;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (final child in children) SizedBox(width: width, child: child),
        ],
      );
    },
  );
}

/// A section title with an optional action beside it.
class SectionHeading extends StatelessWidget {
  const SectionHeading(this.title, {super.key, this.action});
  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Wrap(
    crossAxisAlignment: WrapCrossAlignment.center,
    spacing: 16,
    runSpacing: 8,
    children: [
      Text(title, style: Theme.of(context).textTheme.titleMedium),
      ?action,
    ],
  );
}

// Shows a short message. A newer message replaces the one still on screen instead of
/// waiting behind it, so what the user reads is always the latest outcome.
void showFeedback(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

Future<bool> confirmAction(
  BuildContext context,
  String title,
  String message,
) async {
  final l = strings(context);
  return await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: SingleChildScrollView(child: Text(message)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(l.confirm),
            ),
          ],
        ),
      ) ??
      false;
}

/// Owns an input controller for the entire dialog route, including dismissal.
class DialogInput extends StatefulWidget {
  const DialogInput({super.key, this.initialText = '', required this.builder});
  final String initialText;
  final Widget Function(BuildContext, TextEditingController) builder;
  @override
  State<DialogInput> createState() => _DialogInputState();
}

class _DialogInputState extends State<DialogInput> {
  late final _controller = TextEditingController(text: widget.initialText);
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _controller);
}
