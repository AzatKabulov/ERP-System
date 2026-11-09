import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'pwa_viewport.dart';

/// Frosted glass: what is behind it is blurred and lightened, the surface is a translucent veil
/// of the palette's glass colour, and its edge catches light (a thin rim that is brightest at
/// the top). It is used for the layers that float above the page: the bars, the sheets, the
/// dialogs and the cards that deserve emphasis. Everything else sits on plain surfaces, so the
/// effect stays a specific one and the screens stay quick.
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.radius = AppRadius.card,
    this.borderRadius,
    this.blur = 22,
    this.strong = false,
    this.shadow = true,
    this.rim = true,
    this.padding,
    this.tint,
    this.mobileBlur,
  });

  final Widget child;
  final double radius;

  /// Overrides [radius] where the corners differ (a sheet rounded only at the top).
  final BorderRadius? borderRadius;

  /// How far what is behind it is blurred. Zero draws the veil and the rim only, which is how a
  /// card in a long list stays cheap.
  final double blur;

  /// A denser veil, for a surface that holds text over busy content (a dialog, a menu).
  final bool strong;

  /// A soft shadow beneath. Off for glass that sits flush (a bar against the screen edge).
  final bool shadow;

  /// The lit one-pixel edge all round. Off for a bar that runs edge to edge, which only needs a
  /// line along its lower side.
  final bool rim;
  final EdgeInsetsGeometry? padding;

  /// A wash of colour over the veil (an emphasised card).
  final Color? tint;

  /// The blur used on narrow devices. Backdrop blur is substantially more expensive
  /// while scrolling on phones, where the translucent veil and rim still preserve
  /// the glass treatment without needing the desktop radius.
  final double? mobileBlur;

  @override
  Widget build(BuildContext context) {
    final corners = borderRadius ?? BorderRadius.circular(radius);
    final narrow = MediaQuery.sizeOf(context).shortestSide < 600;
    final effectiveBlur = narrow
        ? (mobileBlur ?? blur.clamp(0, 14).toDouble())
        : blur;
    final fill = strong ? AppColors.glassStrong : AppColors.glass;
    Widget veil = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: corners,
        color: tint == null ? fill : Color.alphaBlend(tint!, fill),
      ),
      child: padding == null ? child : Padding(padding: padding!, child: child),
    );
    if (effectiveBlur > 0) {
      veil = BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: effectiveBlur,
          sigmaY: effectiveBlur,
        ),
        child: veil,
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: corners,
        boxShadow: shadow ? AppShadows.float : null,
      ),
      child: CustomPaint(
        foregroundPainter: rim ? _RimLight(corners) : null,
        child: ClipRRect(borderRadius: corners, child: veil),
      ),
    );
  }
}

/// The edge of the glass: a one-pixel line, lit from above.
class _RimLight extends CustomPainter {
  const _RimLight(this.corners);
  final BorderRadius corners;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = corners.toRRect(rect.deflate(0.5));
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [AppColors.glassHighlight, AppColors.glassEdge],
        stops: const [0, 0.55],
      ).createShader(rect);
    canvas.drawRRect(rrect, paint);
  }

  @override
  bool shouldRepaint(_RimLight old) => old.corners != corners;
}

/// The light behind the glass: the page colour with three soft pools of colour (cobalt, violet
/// and teal) that give the blur something to work on. It is the same on every screen and does
/// not move.
class AmbientField extends StatelessWidget {
  const AmbientField({super.key});

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    key: const ValueKey('ambient-field-paint'),
    child: DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.canvas, AppColors.canvasEdge],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          _pool(const Alignment(-1.1, -1.05), 0.9, AppColors.orbBlue),
          _pool(const Alignment(1.15, -0.45), 0.8, AppColors.orbViolet),
          _pool(const Alignment(-0.3, 1.2), 0.85, AppColors.orbTeal),
        ],
      ),
    ),
  );

  Widget _pool(Alignment at, double radius, Color color) => DecoratedBox(
    decoration: BoxDecoration(
      gradient: RadialGradient(
        center: at,
        radius: radius,
        colors: [color, color.withValues(alpha: 0)],
      ),
    ),
  );
}

/// How much of the screen the floating bars cover, so a page can leave room for them and still
/// scroll beneath them.
class ChromeInsets extends InheritedWidget {
  const ChromeInsets({
    super.key,
    required this.top,
    required this.bottom,
    required super.child,
  });

  final double top;
  final double bottom;

  static ChromeInsets? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ChromeInsets>();

  @override
  bool updateShouldNotify(ChromeInsets old) =>
      top != old.top || bottom != old.bottom;
}

/// The padding of a page's scrolling content: the usual gutters, and room above and below for the
/// bars that float over it.
EdgeInsets pagePadding(
  BuildContext context, {
  required bool compact,
  double? gutter,
}) {
  final chrome = ChromeInsets.maybeOf(context);
  final side = gutter ?? (compact ? 16 : 32);
  final safe = PwaAreas.enabledOf(context)
      ? MediaQuery.paddingOf(context)
      : EdgeInsets.zero;
  return EdgeInsets.fromLTRB(
    side + safe.left,
    (chrome?.top ?? 0) + (compact ? 16 : 28),
    side + safe.right,
    (chrome?.bottom ?? 0) + 32,
  );
}
