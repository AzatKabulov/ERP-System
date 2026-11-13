import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'app_icons.dart';
import 'motion.dart';

/// Touch targets stay fixed while one quiet selection marker follows taps or drags.
class BottomTab {
  const BottomTab({
    required this.key,
    required this.label,
    required this.icon,
    this.reselect = false,
  });
  final Key key;
  final String label;
  final AppIconData icon;
  final bool reselect;
}

class SlidingBottomNavigation extends StatefulWidget {
  const SlidingBottomNavigation({
    super.key,
    required this.tabs,
    required this.selected,
    required this.onSelected,
  });
  final List<BottomTab> tabs;
  final int selected;
  final ValueChanged<int> onSelected;
  @override
  State<SlidingBottomNavigation> createState() =>
      _SlidingBottomNavigationState();
}

class _SlidingBottomNavigationState extends State<SlidingBottomNavigation> {
  double? _drag;
  void _select(int index) {
    if (index != widget.selected || widget.tabs[index].reselect) {
      widget.onSelected(index);
    }
  }

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(26),
      border: Border.all(color: AppColors.line),
      boxShadow: [
        BoxShadow(
          color: AppColors.shadow.withValues(alpha: 0.10),
          blurRadius: 18,
          offset: const Offset(0, 5),
        ),
      ],
    ),
    child: Padding(
      padding: const EdgeInsets.all(6),
      child: SizedBox(
        height: 62,
        child: LayoutBuilder(
          builder: (context, box) {
            final cell = box.maxWidth / widget.tabs.length;
            double at(double x) =>
                (x / cell - 0.5).clamp(0.0, widget.tabs.length - 1.0);
            final position = _drag ?? widget.selected.toDouble();
            final active = position.round();
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragStart: (d) =>
                  setState(() => _drag = at(d.localPosition.dx)),
              onHorizontalDragUpdate: (d) =>
                  setState(() => _drag = at(d.localPosition.dx)),
              onHorizontalDragEnd: (_) {
                final chosen = (_drag ?? position).round();
                setState(() => _drag = null);
                _select(chosen);
              },
              onHorizontalDragCancel: () => setState(() => _drag = null),
              child: Stack(
                children: [
                  AnimatedPositioned(
                    key: const ValueKey('navigation-indicator'),
                    duration: _drag == null
                        ? AppMotion.of(context, AppMotion.base)
                        : Duration.zero,
                    curve: Curves.easeOutCubic,
                    top: 0,
                    bottom: 0,
                    left: position * cell,
                    width: cell,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: AppColors.tint,
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      for (var i = 0; i < widget.tabs.length; i++)
                        Expanded(
                          child: Semantics(
                            button: true,
                            selected: widget.selected == i,
                            child: Material(
                              type: MaterialType.transparency,
                              child: InkWell(
                                key: widget.tabs[i].key,
                                onTap: () => _select(i),
                                splashFactory: NoSplash.splashFactory,
                                highlightColor: Colors.transparent,
                                hoverColor: Colors.transparent,
                                borderRadius: BorderRadius.circular(20),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    AnimatedScale(
                                      scale: active == i ? 1.06 : 1,
                                      duration: AppMotion.of(
                                        context,
                                        AppMotion.fast,
                                      ),
                                      child: AppIcon(
                                        widget.tabs[i].icon,
                                        size: 22,
                                        color: active == i
                                            ? AppColors.blue
                                            : AppColors.muted,
                                      ),
                                    ),
                                    const SizedBox(height: 5),
                                    MediaQuery.withClampedTextScaling(
                                      maxScaleFactor: 1.3,
                                      child: AnimatedDefaultTextStyle(
                                        duration: AppMotion.of(
                                          context,
                                          AppMotion.fast,
                                        ),
                                        style: TextStyle(
                                          fontFamily: AppFonts.ui,
                                          fontSize: 11,
                                          fontWeight: active == i
                                              ? FontWeight.w700
                                              : FontWeight.w500,
                                          color: active == i
                                              ? AppColors.blue
                                              : AppColors.muted,
                                        ),
                                        child: Text(
                                          widget.tabs[i].label,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
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
                  ),
                ],
              ),
            );
          },
        ),
      ),
    ),
  );
}
