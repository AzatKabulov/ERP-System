import 'package:flutter/material.dart';
import 'app_icons.dart';

import '../demo/demo_store.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import 'glass.dart';
import 'motion.dart';

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

/// A white card: hairline border and the two-layer low-spread shadow. With [onTap] it is a
/// button: it rises a little and takes a cobalt-tinted edge on hover, and sinks when pressed.
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
    final lifted = interactive && _hover;
    Widget body = Padding(
      padding: EdgeInsets.all(widget.padding),
      child: widget.child,
    );
    if (interactive) {
      body = InkWell(onTap: widget.onTap, borderRadius: radius, child: body);
    }
    final card = AnimatedContainer(
      duration: AppMotion.of(context, AppMotion.base),
      curve: AppMotion.arrive,
      transform: Matrix4.translationValues(0, lifted ? -2 : 0, 0),
      decoration: BoxDecoration(
        color: widget.featured
            ? Color.alphaBlend(
                AppColors.blue.withValues(
                  alpha: AppColors.isDark ? 0.14 : 0.06,
                ),
                AppColors.glassStrong,
              )
            : widget.flat
            ? AppColors.glass
            : AppColors.glass,
        borderRadius: radius,
        // the rim of the glass: lit at rest, cobalt when it is the emphasised card or under
        // the pointer; a flat (list) card has a plain hairline and no shadow
        border: Border.all(
          color: widget.featured
              ? AppColors.blue.withValues(alpha: 0.55)
              : lifted
              ? AppColors.blue.withValues(alpha: 0.38)
              : widget.flat
              ? AppColors.line
              : AppColors.glassEdge,
        ),
        boxShadow: widget.flat
            ? null
            : lifted
            ? AppShadows.cardHover
            : AppShadows.card,
      ),
      child: Material(
        type: MaterialType.transparency,
        clipBehavior: Clip.antiAlias,
        borderRadius: radius,
        child: body,
      ),
    );
    if (!interactive) return card;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: PressScale(child: card),
    );
  }
}

/// The main action: cobalt with a soft glow beneath it, a little deeper on hover, a press scale
/// of 0.98 and a separated focus ring.
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
  bool _hover = false;
  bool _focused = false;

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final deep = enabled && (_pressed || _hover);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Listener(
        onPointerDown: (_) => _setPressed(true),
        onPointerUp: (_) => _setPressed(false),
        onPointerCancel: (_) => _setPressed(false),
        child: AnimatedScale(
          scale: enabled && _pressed ? 0.98 : 1,
          duration: AppMotion.of(context, AppMotion.fast),
          child: Focus(
            canRequestFocus: false,
            skipTraversal: true,
            onFocusChange: (value) => setState(() => _focused = value),
            child: AnimatedContainer(
              duration: AppMotion.of(context, AppMotion.base),
              curve: Curves.easeOut,
              foregroundDecoration: enabled
                  ? BoxDecoration(
                      borderRadius: BorderRadius.circular(AppRadius.control),
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.white.withValues(alpha: 0.18),
                          Colors.white.withValues(alpha: 0),
                        ],
                        stops: const [0, 0.55],
                      ),
                    )
                  : null,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.control),
                color: enabled ? null : AppColors.blue.withValues(alpha: 0.42),
                gradient: enabled
                    ? (deep ? AppGradients.buttonDeep : AppGradients.button)
                    : null,
                boxShadow: [
                  if (_focused && enabled) ...[
                    BoxShadow(color: AppColors.canvas, spreadRadius: 2),
                    BoxShadow(
                      color: AppColors.blue.withValues(alpha: 0.4),
                      spreadRadius: 5,
                    ),
                  ],
                  if (enabled)
                    BoxShadow(
                      color: AppColors.palette.blueFillDeep.withValues(
                        alpha: _pressed
                            ? 0.16
                            : (AppColors.isDark ? 0.45 : 0.32),
                      ),
                      offset: Offset(0, _pressed ? 2 : 8),
                      blurRadius: _pressed ? 6 : 20,
                    ),
                ],
              ),
              child: FilledButton(
                style:
                    FilledButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      disabledBackgroundColor: Colors.transparent,
                      disabledForegroundColor: Colors.white,
                      shadowColor: Colors.transparent,
                    ).copyWith(
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

/// A short caption above a section of a page or a chart ("Revenue by day"): small, muted,
/// sentence case. It names what follows; it is not a label above a heading.
class Eyebrow extends StatelessWidget {
  const Eyebrow(this.text, {super.key, this.color});
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TextStyle(
      color: color ?? AppColors.muted,
      fontSize: 13,
      fontWeight: FontWeight.w600,
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
    this.subtitle,
    this.actions = const [],
    this.titleKey,
    this.titleWidget,
    this.subtitleWidget,
  });
  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final Key? titleKey;

  /// Replaces the plain title text (for a title with a coloured part).
  final Widget? titleWidget;

  /// A structured subtitle or an initial-read placeholder with the same metrics.
  final Widget? subtitleWidget;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final narrow = constraints.maxWidth < 600;
      final heading = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          titleWidget ??
              Text(
                title,
                key: titleKey,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontSize: narrow ? 28 : 34,
                  letterSpacing: narrow ? -0.7 : -1.0,
                  height: 1.1,
                ),
              ),
          if (subtitle != null || subtitleWidget != null) ...[
            const SizedBox(height: 8),
            subtitleWidget ??
                Text(
                  subtitle!,
                  style: TextStyle(color: AppColors.muted, fontSize: 14),
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
      // The title takes what the buttons leave; the buttons sit at the right edge (up to 80% of
      // the width, then they wrap), the same on every page.
      return Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(child: heading),
          const SizedBox(width: 24),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: constraints.maxWidth * 0.8),
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: actions,
            ),
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
    this.background,
    this.color,
  });
  final AppIconData icon;
  final double size;
  final Color? background;
  final Color? color;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: background ?? AppColors.surfaceMuted,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Center(
      child: AppIcon(icon, color: color ?? AppColors.neutral, size: 20),
    ),
  );
}

/// The brand square: one letter, white on the brand gradient.
class BrandMark extends StatelessWidget {
  const BrandMark(this.letter, {super.key, this.size = 28, this.light = false});
  final String letter;
  final double size;

  /// On a dark surface the square turns white with a cobalt letter.
  final bool light;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: light ? Colors.white : null,
      gradient: light ? null : AppGradients.brand,
      borderRadius: BorderRadius.circular(size * 0.32),
      boxShadow: light
          ? null
          : [
              BoxShadow(
                color: AppColors.blue.withValues(alpha: 0.32),
                offset: const Offset(0, 4),
                blurRadius: 10,
              ),
            ],
    ),
    child: Text(
      letter,
      style: TextStyle(
        fontFamily: AppFonts.display,
        fontWeight: FontWeight.w800,
        fontSize: size * 0.56,
        height: 1,
        color: light ? AppColors.blue : Colors.white,
      ),
    ),
  );
}

/// The deep surface of the one figure that matters most: navy running into cobalt, with two soft
/// glows of light in its corners.
class SpotlightCard extends StatelessWidget {
  const SpotlightCard({super.key, required this.child, this.padding = 28});
  final Widget child;
  final double padding;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppRadius.card);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: AppGradients.spotlight,
        borderRadius: radius,
        boxShadow: const [
          BoxShadow(
            color: Color(0x290A1030),
            offset: Offset(0, 4),
            blurRadius: 8,
          ),
          BoxShadow(
            color: Color(0x330A1030),
            offset: Offset(0, 20),
            blurRadius: 44,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Stack(
          children: [
            Positioned(
              top: -110,
              right: -70,
              child: ExcludeSemantics(child: _glow(300, 0x663D63FF)),
            ),
            Positioned(
              bottom: -150,
              left: -60,
              child: ExcludeSemantics(child: _glow(320, 0x446A4DFF)),
            ),
            Padding(padding: EdgeInsets.all(padding), child: child),
          ],
        ),
      ),
    );
  }

  static Widget _glow(double size, int argb) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: RadialGradient(colors: [Color(argb), Color(argb & 0x00FFFFFF)]),
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
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(
          alpha: AppColors.isDark ? 0.55 : 0.7,
        ),
        borderRadius: BorderRadius.circular(999),
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
            AppIcon(AppIcons.chevron, size: 16, color: AppColors.ink),
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
    this.width = 200,
  });

  /// The control's width: long values are cut with an ellipsis, never overflow.
  final double width;

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
    width: width,
    constraints: const BoxConstraints(minHeight: 40),
    padding: const EdgeInsets.symmetric(horizontal: 12),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(12),
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
              dropdownColor: AppColors.surface,
              value: value,
              hint: hint,
              items: items,
              onChanged: onChanged,
              borderRadius: BorderRadius.circular(AppRadius.control),
              icon: AppIcon(AppIcons.chevron, size: 16, color: AppColors.ink),
              style: TextStyle(
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

/// A readable group of related fields. No backdrop blur is needed in a form.
class FormSection extends StatelessWidget {
  const FormSection({super.key, required this.title, required this.children});
  final String title;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => SurfaceCard(
    flat: true,
    padding: 20,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(
            title,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(height: 20),
        ...children,
      ],
    ),
  );
}

/// A form field with its label above it (13 px, semibold), as in the design. The field keeps its
/// own label for screen readers; the visible one here is not read twice.
class LabeledField extends StatelessWidget {
  const LabeledField({
    super.key,
    required this.label,
    required this.child,
    this.minLabelHeight = 0,
  });
  final String label;
  final Widget child;

  /// Reserves room for a label of two lines, so side-by-side fields whose labels differ in
  /// length still start their boxes at the same height.
  final double minLabelHeight;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      ExcludeSemantics(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: minLabelHeight),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.ink,
              height: 1.3,
            ),
          ),
        ),
      ),
      const SizedBox(height: 8),
      Semantics(label: label, child: child),
    ],
  );
}

/// A switch between a few options (the language, cash or card, list or gallery): a white thumb
/// glides to the chosen one and its label turns cobalt.
class AppSegmented<T> extends StatelessWidget {
  const AppSegmented({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    this.keyPrefix,
    this.keyName,
    this.expand = false,
  });

  /// The segments share the whole width (the sign-in page); otherwise the switch is as wide as
  /// its widest label, every segment the same.
  final bool expand;

  /// (value, label) pairs.
  final List<(T, String)> options;
  final T value;
  final ValueChanged<T> onChanged;

  /// Each segment gets the key `ValueKey('<keyPrefix>-<name>')`; the name is [keyName] of the
  /// value, or the value itself.
  final String? keyPrefix;
  final String Function(T)? keyName;

  @override
  Widget build(BuildContext context) {
    final count = options.length;
    final index = options.indexWhere((o) => o.$1 == value);
    final inner = Stack(
      children: [
        if (index >= 0)
          Positioned.fill(
            child: AnimatedAlign(
              duration: AppMotion.of(context, AppMotion.base),
              curve: AppMotion.arrive,
              alignment: Alignment(
                count == 1 ? 0 : -1 + 2 * index / (count - 1),
                0,
              ),
              child: FractionallySizedBox(
                widthFactor: 1 / count,
                heightFactor: 1,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppColors.isDark
                        ? AppColors.palette.surfaceMuted
                        : AppColors.surface,
                    borderRadius: BorderRadius.circular(11),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.shadow.withValues(alpha: 0.14),
                        offset: const Offset(0, 1),
                        blurRadius: 4,
                      ),
                      BoxShadow(
                        color: AppColors.blue.withValues(alpha: 0.1),
                        offset: const Offset(0, 4),
                        blurRadius: 10,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        IntrinsicHeight(
          child: Row(
            children: [
              for (final (v, label) in options)
                Expanded(
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
      ],
    );
    return Container(
      constraints: const BoxConstraints(minHeight: 48),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(AppRadius.control + 2),
      ),
      child: expand ? inner : IntrinsicWidth(child: inner),
    );
  }
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
      borderRadius: BorderRadius.circular(11),
      child: Container(
        constraints: const BoxConstraints(minWidth: 76, minHeight: 40),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.center,
        child: AnimatedDefaultTextStyle(
          duration: AppMotion.of(context, AppMotion.base),
          curve: Curves.easeOut,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: AppFonts.ui,
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: selected ? AppColors.blue : AppColors.muted,
          ),
          child: Text(label, textAlign: TextAlign.center),
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
    final (fg, bg) = switch (tone) {
      StatusTone.warning => (AppColors.warning, AppColors.warningTint),
      StatusTone.danger => (AppColors.danger, AppColors.dangerTint),
      StatusTone.success => (AppColors.success, AppColors.successTint),
      _ => (AppColors.blue, AppColors.tint),
    };
    final edge = fg.withValues(alpha: 0.28);
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
class AppTabs<T> extends StatefulWidget {
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
  State<AppTabs<T>> createState() => _AppTabsState<T>();
}

/// A page's sections as a row of pills in a recessed track. When the row is wider than the
/// screen it fades out at the edge that has more behind it, so nobody has to guess that it
/// scrolls.
class _AppTabsState<T> extends State<AppTabs<T>> {
  final _scroll = ScrollController();
  bool _more = false; // something is hidden to the right
  bool _less = false; // something is hidden to the left

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_check);
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _check() {
    if (!_scroll.hasClients || !_scroll.position.hasContentDimensions) return;
    final p = _scroll.position;
    final more = p.maxScrollExtent - p.pixels > 4;
    final less = p.pixels > 4;
    if (more != _more || less != _less) {
      setState(() {
        _more = more;
        _less = less;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
    final track = Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(AppRadius.control + 4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (v, label) in widget.tabs)
            _TabPill(
              key: widget.keyPrefix == null
                  ? null
                  : ValueKey(
                      '${widget.keyPrefix}-${widget.keyName?.call(v) ?? v}',
                    ),
              label: label,
              selected: v == widget.value,
              onTap: () => widget.onChanged(v),
            ),
        ],
      ),
    );
    return Align(
      alignment: Alignment.centerLeft,
      child: ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (rect) => LinearGradient(
          colors: [
            _less ? Colors.transparent : Colors.black,
            Colors.black,
            Colors.black,
            _more ? Colors.transparent : Colors.black,
          ],
          stops: const [0, 0.07, 0.93, 1],
        ).createShader(rect),
        child: SingleChildScrollView(
          controller: _scroll,
          scrollDirection: Axis.horizontal,
          child: track,
        ),
      ),
    );
  }
}

class _TabPill extends StatelessWidget {
  const _TabPill({
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
      borderRadius: BorderRadius.circular(AppRadius.control + 1),
      hoverColor: AppColors.blue.withValues(alpha: 0.06),
      highlightColor: Colors.transparent,
      splashColor: AppColors.blue.withValues(alpha: 0.08),
      child: AnimatedContainer(
        duration: AppMotion.of(context, AppMotion.base),
        curve: AppMotion.arrive,
        constraints: const BoxConstraints(minHeight: 44),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected
              ? (AppColors.isDark
                    ? AppColors.palette.surface
                    : AppColors.surface)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.control + 1),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: AppColors.shadow.withValues(alpha: 0.14),
                    offset: const Offset(0, 1),
                    blurRadius: 4,
                  ),
                  BoxShadow(
                    color: AppColors.blue.withValues(alpha: 0.1),
                    offset: const Offset(0, 4),
                    blurRadius: 10,
                  ),
                ]
              : null,
        ),
        child: AnimatedDefaultTextStyle(
          duration: AppMotion.of(context, AppMotion.base),
          style: TextStyle(
            fontFamily: AppFonts.ui,
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: selected ? AppColors.blue : AppColors.muted,
          ),
          child: Text(label),
        ),
      ),
    ),
  );
}

/// The "More" button of a page header: a white button with three dots that opens a menu of the
/// page's less-used actions, so the header keeps one main button and one tidy neighbour.
class MoreMenuButton extends StatelessWidget {
  const MoreMenuButton({
    super.key,
    required this.label,
    required this.itemBuilder,
    required this.onSelected,
  });
  final String label;
  final PopupMenuItemBuilder<String> itemBuilder;
  final PopupMenuItemSelected<String> onSelected;

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
    tooltip: label,
    position: PopupMenuPosition.under,
    onSelected: onSelected,
    itemBuilder: itemBuilder,
    child: IgnorePointer(
      child: Container(
        constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: AppColors.surface.withValues(
            alpha: AppColors.isDark ? 0.55 : 0.78,
          ),
          borderRadius: BorderRadius.circular(AppRadius.control),
          border: Border.all(color: AppColors.line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const AppIcon(AppIcons.dots, size: 20),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            ),
          ],
        ),
      ),
    ),
  );
}

/// A menu entry with a title and a short grey explanation under it.
class MenuEntry extends StatelessWidget {
  const MenuEntry({
    super.key,
    required this.icon,
    required this.title,
    this.help,
  });
  final AppIconData icon;
  final String title;
  final String? help;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 320),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: AppIcon(icon, size: 18, color: AppColors.neutral),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                if (help != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      help!,
                      style: TextStyle(
                        color: AppColors.muted,
                        fontSize: 12,
                        height: 1.35,
                      ),
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

/// A filter or choice drawn as a pill: white with a hairline, or tinted with a cobalt edge when
/// chosen. One clean outline (the Material chip drew a second ring on hover and focus), a soft
/// colour glide, and a ripple that stays inside the pill.
class AppPill extends StatelessWidget {
  const AppPill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.trailing,
  });
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final AppIconData? icon;

  /// A small widget after the label (a chevron, a count).
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.blue : AppColors.neutral;
    return Semantics(
      button: true,
      selected: selected,
      child: AnimatedContainer(
        duration: AppMotion.of(context, AppMotion.fast),
        curve: Curves.easeOut,
        decoration: ShapeDecoration(
          color: selected
              ? AppColors.blue.withValues(alpha: AppColors.isDark ? 0.22 : 0.1)
              : AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: selected
                  ? AppColors.blue.withValues(alpha: 0.6)
                  : AppColors.line,
            ),
          ),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            hoverColor: AppColors.blue.withValues(alpha: 0.05),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (icon != null) ...[
                      AppIcon(icon!, size: 16, color: color),
                      const SizedBox(width: 6),
                    ],
                    Flexible(
                      child: AnimatedDefaultTextStyle(
                        duration: AppMotion.of(context, AppMotion.fast),
                        style: TextStyle(
                          fontFamily: AppFonts.ui,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: color,
                        ),
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    ?trailing,
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A filter that opens a list or a menu: a caption, the chosen value and a chevron. Cobalt-tinted
/// while a value other than "all" is chosen, so an active filter is never missed.
class FilterButton extends StatelessWidget {
  const FilterButton({
    super.key,
    required this.caption,
    required this.value,
    required this.onTap,
    this.active = false,
    this.icon,
  });
  final String caption;
  final String value;
  final bool active;
  final VoidCallback onTap;
  final AppIconData? icon;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: caption,
    child: AppPill(
      label: value,
      selected: active,
      onTap: onTap,
      icon: icon,
      trailing: Padding(
        padding: const EdgeInsets.only(left: 6),
        child: AppIcon(
          AppIcons.chevronDown,
          size: 16,
          color: active ? AppColors.blue : AppColors.neutral,
        ),
      ),
    ),
  );
}

/// A page's content arriving: a fade and a short rise (see [Reveal]). Skipped when the platform
/// asks for reduced motion.
class FadeUp extends StatelessWidget {
  const FadeUp({super.key, required this.child, this.index = 0});
  final Widget child;
  final int index;

  @override
  Widget build(BuildContext context) =>
      Reveal(index: index, distance: 10, child: child);
}

/// The colours of a product category: a tint for the tile and a strong shade for its icon.
(Color, Color) categoryColors(ProductCategory category) => switch (category) {
  ProductCategory.filters => (AppColors.tint, AppColors.blue),
  ProductCategory.brakes => (AppColors.roseTint, AppColors.danger),
  ProductCategory.oils => (AppColors.amberTint, AppColors.warning),
  ProductCategory.electrical => (AppColors.violetTint, AppColors.violetText),
};

class ProductMark extends StatelessWidget {
  const ProductMark({super.key, required this.product, this.size = 48});
  final Product product;
  final double size;

  @override
  Widget build(BuildContext context) {
    final (tint, strong) = categoryColors(product.category);
    return Glyph(
      categoryIcon(product.category),
      size: size,
      background: tint,
      color: strong,
    );
  }
}

/// Nothing here yet: a calm line icon in a circle, one sentence, an optional hint.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.title,
    this.subtitle,
    this.icon = AppIcons.inbox,
    this.action,
  });
  final String title;
  final String? subtitle;
  final AppIconData icon;

  /// The obvious next step (a button, or a few): an empty page must say what to do about it.
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
    child: Column(
      children: [
        TweenAnimationBuilder<double>(
          tween: Tween(
            begin: AppMotion.skipEntrance(context) ? 1 : 0.6,
            end: 1,
          ),
          duration: AppMotion.entrance(context, AppMotion.slow),
          curve: Curves.easeOutBack,
          builder: (context, scale, child) =>
              Transform.scale(scale: scale, child: child),
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: AppColors.tint,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: AppIcon(icon, size: 26, color: AppColors.blue),
            ),
          ),
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
              style: TextStyle(
                color: AppColors.muted,
                fontSize: 13,
                height: 1.55,
              ),
            ),
          ),
        ],
        if (action != null) ...[const SizedBox(height: 20), action!],
      ],
    ),
  );
}

/// One figure: a coloured icon tile and the label on top, the figure (tabular digits) and a short
/// note at the bottom. The colour says what kind of figure it is (see [AppColors]); the label and
/// the icon say it too. A changed figure glides in from below.
class MetricCard extends StatelessWidget {
  const MetricCard({
    super.key,
    required this.label,
    required this.value,
    this.meta,
    this.onTap,
    this.featured = false,
    this.icon,
    this.accent,
    this.accentTint,
    this.alignWithPeers = false,
  });
  final String label;
  final String value;
  final String? meta;
  final VoidCallback? onTap;
  final bool featured;
  final AppIconData? icon;
  final Color? accent;
  final Color? accentTint;
  final bool alignWithPeers;

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
          ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: alignWithPeers
                  ? MediaQuery.textScalerOf(context).scale(14) * 1.35 * 3
                  : 0,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: AppColors.muted,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      height: 1.35,
                    ),
                  ),
                ),
                if (icon != null) ...[
                  const SizedBox(width: 10),
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: accentTint ?? AppColors.tint,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Center(
                      child: AppIcon(
                        icon!,
                        size: 18,
                        color: accent ?? AppColors.blue,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: alignWithPeers
                ? MediaQuery.textScalerOf(context).scale(26) * 1.2
                : null,
            width: alignWithPeers ? double.infinity : null,
            child: AnimatedSwitcher(
              duration: AppMotion.of(context, AppMotion.base),
              switchInCurve: AppMotion.arrive,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween(
                    begin: const Offset(0, 0.25),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              ),
              layoutBuilder: (current, previous) => Stack(
                alignment: Alignment.centerLeft,
                children: [...previous, ?current],
              ),
              child: FittedBox(
                key: ValueKey(value),
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  softWrap: false,
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                    letterSpacing: -0.5,
                    color: AppColors.ink,
                    fontFeatures: AppFonts.tabular,
                  ),
                ),
              ),
            ),
          ),
          if (meta != null || alignWithPeers) ...[
            const SizedBox(height: 8),
            Text(
              meta ?? ' ',
              style: TextStyle(color: AppColors.muted, fontSize: 13),
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
      var count = ((constraints.maxWidth + gap) / (minimumWidth + gap))
          .floor()
          .clamp(1, maxColumns);
      // More cards than columns: take the column count (at most two fewer) that leaves the last
      // row fullest, so six cards sit as 3 + 3 rather than 4 + 2.
      if (children.length > count && count > 2) {
        var best = count;
        var fewest = (count - children.length % count) % count;
        for (var c = count - 1; c >= (count - 2).clamp(2, count); c--) {
          final empty = (c - children.length % c) % c;
          if (empty < fewest) {
            best = c;
            fewest = empty;
          }
        }
        count = best;
      }
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

/// The dialog of the design: an icon tile, a serif title, a sentence, optional content and the
/// actions on the right (stacked on a narrow screen).
class AppDialog extends StatelessWidget {
  const AppDialog({
    super.key,
    required this.title,
    this.icon = AppIcons.info,
    this.message,
    this.content,
    this.actions = const [],
  });
  final String title;
  final AppIconData icon;
  final String? message;
  final Widget? content;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: AppMotion.skipEntrance(context) ? 1 : 0.94, end: 1),
    duration: AppMotion.entrance(context, AppMotion.base),
    curve: AppMotion.arrive,
    builder: (context, scale, child) =>
        Transform.scale(scale: scale, child: child),
    child: _dialog(context),
  );

  Widget _dialog(BuildContext context) => Dialog(
    backgroundColor: Colors.transparent,
    surfaceTintColor: Colors.transparent,
    insetPadding: const EdgeInsets.all(16),
    elevation: 0,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 440),
      child: GlassSurface(
        radius: AppRadius.dialog,
        strong: true,
        blur: 30,
        shadow: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppColors.tint,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Center(
                    child: AppIcon(icon, size: 20, color: AppColors.blue),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(title, style: Theme.of(context).dialogTheme.titleTextStyle),
              if (message != null) ...[
                const SizedBox(height: 8),
                Text(
                  message!,
                  style: Theme.of(context).dialogTheme.contentTextStyle,
                ),
              ],
              if (content != null) ...[const SizedBox(height: 20), content!],
              if (actions.isNotEmpty) ...[
                const SizedBox(height: 24),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 8,
                  children: actions,
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}

Future<bool> confirmAction(
  BuildContext context,
  String title,
  String message,
) async {
  final l = strings(context);
  return await showDialog<bool>(
        context: context,
        builder: (context) => AppDialog(
          title: title,
          message: message,
          actions: [
            OutlinedButton(
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
