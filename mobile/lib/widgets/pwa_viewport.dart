import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Insets affect controls, never the size/origin of Flutter's drawing surface.
/// This also avoids adding CSS insets twice if a future engine reports them.
MediaQueryData withBrowserSafeAreas(MediaQueryData data, EdgeInsets css) {
  double safe(double value) => value.isFinite ? math.max(0, value) : 0;
  final native = data.viewPadding;
  final viewPadding = EdgeInsets.fromLTRB(
    math.max(native.left, safe(css.left)),
    math.max(native.top, safe(css.top)),
    math.max(native.right, safe(css.right)),
    math.max(native.bottom, safe(css.bottom)),
  );
  final keyboard = data.viewInsets;
  return data.copyWith(
    viewPadding: viewPadding,
    padding: EdgeInsets.fromLTRB(
      math.max(0, viewPadding.left - keyboard.left),
      math.max(0, viewPadding.top - keyboard.top),
      math.max(0, viewPadding.right - keyboard.right),
      math.max(0, viewPadding.bottom - keyboard.bottom),
    ),
  );
}

/// Present only in the opt-in /fs/ document. Ordinary web/native paths retain
/// their existing MediaQuery, themes and layout.
class PwaViewport extends StatelessWidget {
  const PwaViewport({
    super.key,
    required this.enabled,
    required this.insets,
    required this.child,
  });
  final bool enabled;
  final EdgeInsets insets;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    return MediaQuery(
      data: withBrowserSafeAreas(MediaQuery.of(context), insets),
      child: PwaAreas(child: child),
    );
  }
}

class PwaAreas extends InheritedWidget {
  const PwaAreas({super.key, required super.child});
  static bool enabledOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PwaAreas>() != null;
  @override
  bool updateShouldNotify(PwaAreas oldWidget) => false;
}

ThemeData fullScreenTheme(ThemeData theme, {required bool enabled}) => enabled
    ? theme.copyWith(
        appBarTheme: theme.appBarTheme.copyWith(
          backgroundColor: Colors.transparent,
        ),
      )
    : theme;

/// A translucent veil, fading beyond the safe-area boundary, keeps iOS's white
/// clock readable. It composites the actual scene (including scrolling content),
/// rather than sampling a color or painting a separate status-bar rectangle.
class PwaStatusVeil extends StatelessWidget {
  const PwaStatusVeil({super.key});
  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    if (!PwaAreas.enabledOf(context) || AppColors.isDark || top <= 0) {
      return const SizedBox.shrink();
    }
    return IgnorePointer(
      child: ExcludeSemantics(
        child: SizedBox(
          key: const ValueKey('pwa-status-veil'),
          height: top + 48,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AppColors.navy.withValues(alpha: 0.60),
                  AppColors.navy.withValues(alpha: 0),
                ],
                stops: const [0, 1],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
