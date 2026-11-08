import 'dart:ui' show SemanticsRole;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'common.dart';

/// One localized loading announcement and one repaint-only pulse for a region.
/// Nested composites share the pulse. No delay, blur, shader mask or per-bone ticker.
class SkeletonRegion extends StatefulWidget {
  const SkeletonRegion({
    super.key,
    required this.child,
    this.label,
    this.animate = true,
  });
  final Widget child;
  final String? label;
  final bool animate;

  @override
  State<SkeletonRegion> createState() => _SkeletonRegionState();
}

class _SkeletonRegionState extends State<SkeletonRegion>
    with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );
  bool _nested = false;

  void _sync() {
    final animate =
        widget.animate &&
        !_nested &&
        TickerMode.valuesOf(context).enabled &&
        !MediaQuery.disableAnimationsOf(context);
    if (animate && !_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    } else if (!animate) {
      _pulse.stop();
      _pulse.value = 0.35;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _nested =
        context.dependOnInheritedWidgetOfExactType<_SkeletonPulse>() != null;
    _sync();
  }

  @override
  void didUpdateWidget(SkeletonRegion oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_nested) return widget.child;
    // Theme dependency repaints existing bones when the scheme changes in place.
    Theme.of(context);
    return Semantics(
      container: true,
      role: SemanticsRole.status,
      label: widget.label ?? strings(context).loading,
      child: ExcludeSemantics(
        child: IgnorePointer(
          child: RepaintBoundary(
            child: _SkeletonPulse(animation: _pulse, child: widget.child),
          ),
        ),
      ),
    );
  }
}

class _SkeletonPulse extends InheritedWidget {
  const _SkeletonPulse({required this.animation, required super.child});
  final Animation<double> animation;

  @override
  bool updateShouldNotify(_SkeletonPulse oldWidget) =>
      animation != oldWidget.animation;
}

class SkeletonBase extends StatelessWidget {
  const SkeletonBase({
    super.key,
    this.width,
    this.height = 16,
    this.radius = AppRadius.small,
  });
  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final pulse =
        context
            .dependOnInheritedWidgetOfExactType<_SkeletonPulse>()
            ?.animation ??
        const AlwaysStoppedAnimation(0.35);
    return SizedBox(
      width: width,
      height: height,
      child: CustomPaint(
        painter: _BonePainter(
          pulse,
          AppColors.surfaceMuted,
          AppColors.lineStrong,
          radius,
        ),
      ),
    );
  }
}

class _BonePainter extends CustomPainter {
  _BonePainter(this.pulse, this.base, this.highlight, this.radius)
    : super(repaint: pulse);
  final Animation<double> pulse;
  final Color base;
  final Color highlight;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final amount = Curves.easeInOut.transform(pulse.value) * 0.28;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)),
      Paint()..color = Color.lerp(base, highlight, amount)!,
    );
  }

  @override
  bool shouldRepaint(_BonePainter oldDelegate) =>
      oldDelegate.base != base ||
      oldDelegate.highlight != highlight ||
      oldDelegate.radius != radius ||
      oldDelegate.pulse != pulse;
}

class SkeletonText extends StatelessWidget {
  const SkeletonText({
    super.key,
    this.lines = 1,
    this.lineHeight = 14,
    this.spacing = 6,
    this.lastLineWidth = 0.72,
  });
  final int lines;
  final double lineHeight;
  final double spacing;
  final double lastLineWidth;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (var i = 0; i < lines; i++) ...[
        if (i > 0) SizedBox(height: spacing),
        FractionallySizedBox(
          widthFactor: i == lines - 1 ? lastLineWidth : 1,
          alignment: AlignmentDirectional.centerStart,
          child: SkeletonBase(
            height: MediaQuery.textScalerOf(context).scale(lineHeight),
            radius: 4,
          ),
        ),
      ],
    ],
  );
}

class SkeletonAvatar extends StatelessWidget {
  const SkeletonAvatar({super.key, this.size = 48, this.circular = false});
  final double size;
  final bool circular;
  @override
  Widget build(BuildContext context) =>
      SkeletonBase(width: size, height: size, radius: circular ? size / 2 : 12);
}

class SkeletonImage extends StatelessWidget {
  const SkeletonImage({super.key, this.aspectRatio = 4 / 3, this.radius = 12});
  final double aspectRatio;
  final double radius;
  @override
  Widget build(BuildContext context) => AspectRatio(
    aspectRatio: aspectRatio,
    child: SkeletonBase(height: double.infinity, radius: radius),
  );
}

class SkeletonButton extends StatelessWidget {
  const SkeletonButton({super.key, this.width = 128, this.height = 48});
  final double width;
  final double height;
  @override
  Widget build(BuildContext context) =>
      SkeletonBase(width: width, height: height, radius: AppRadius.control);
}

class SkeletonBadge extends StatelessWidget {
  const SkeletonBadge({super.key, this.width = 72});
  final double width;
  @override
  Widget build(BuildContext context) =>
      SkeletonBase(width: width, height: 24, radius: 12);
}

class SkeletonCard extends StatelessWidget {
  const SkeletonCard({
    super.key,
    this.image = false,
    this.avatar = false,
    this.lines = 2,
    this.metadata = true,
    this.padding = 16,
    this.product = false,
    this.stock = false,
  });
  final bool image;
  final bool avatar;
  final int lines;
  final bool metadata;
  final double padding;
  final bool product;
  final bool stock;

  @override
  Widget build(BuildContext context) => SkeletonRegion(
    child: SurfaceCard(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (image) ...[const SkeletonImage(), const SizedBox(height: 12)],
          Row(
            children: [
              if (avatar) ...[
                const SkeletonAvatar(),
                const SizedBox(width: 14),
              ],
              Expanded(
                child: SkeletonText(
                  lines: lines,
                  lineHeight: product ? 19.5 : 14,
                  spacing: product ? 0 : 6,
                ),
              ),
            ],
          ),
          if (metadata) ...[
            SizedBox(height: product ? 4 : 12),
            SkeletonText(lineHeight: product ? 17 : 12, lastLineWidth: 0.45),
            SizedBox(height: product && stock ? 16 : 10),
            if (product && stock)
              const SkeletonText(lineHeight: 19, lastLineWidth: 0.85),
            SkeletonText(lineHeight: product ? 23 : 16, lastLineWidth: 0.58),
          ],
        ],
      ),
    ),
  );
}

/// Shared rows for pickers, feeds and search. Geometry is supplied by the route.
class SkeletonList extends StatelessWidget {
  const SkeletonList({
    super.key,
    this.rows = 4,
    this.avatar = false,
    this.badge = true,
    this.lines = 2,
    this.rowHeight = 80,
    this.inCard = true,
    this.padding = 16,
  });
  final int rows;
  final bool avatar;
  final bool badge;
  final int lines;
  final double rowHeight;
  final bool inCard;
  final double padding;

  @override
  Widget build(BuildContext context) {
    final content = SingleChildScrollView(
      primary: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < rows; i++)
            Container(
              constraints: BoxConstraints(minHeight: rowHeight),
              padding: EdgeInsets.all(padding),
              decoration: BoxDecoration(
                border: i == 0
                    ? null
                    : Border(top: BorderSide(color: AppColors.line)),
              ),
              child: Row(
                children: [
                  if (avatar) ...[
                    const SkeletonAvatar(),
                    const SizedBox(width: 14),
                  ],
                  Expanded(child: SkeletonText(lines: lines)),
                  if (badge) ...[
                    const SizedBox(width: 16),
                    const SkeletonBadge(width: 64),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
    return SkeletonRegion(
      child: inCard ? SurfaceCard(padding: 0, child: content) : content,
    );
  }
}

/// The same table columns as the loaded route; compact layouts use stacked rows.
class SkeletonTable extends StatelessWidget {
  const SkeletonTable({
    super.key,
    this.rows = 5,
    this.columns = const [4, 2, 3, 2],
    this.compact = false,
    this.rowHeight = 72,
    this.inCard = true,
  });
  final int rows;
  final List<int> columns;
  final bool compact;
  final double rowHeight;
  final bool inCard;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return SkeletonList(rows: rows, rowHeight: rowHeight, inCard: inCard);
    }
    final content = SingleChildScrollView(
      primary: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var row = -1; row < rows; row++)
            Container(
              height: row == -1 ? 44 : rowHeight,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: row == -1 ? AppColors.surfaceSoft : null,
                border: row == -1
                    ? null
                    : Border(top: BorderSide(color: AppColors.line)),
              ),
              child: Row(
                children: [
                  for (var col = 0; col < columns.length; col++)
                    Expanded(
                      flex: columns[col],
                      child: Padding(
                        padding: EdgeInsetsDirectional.only(
                          end: col == columns.length - 1 ? 0 : 16,
                        ),
                        child: SkeletonText(
                          lines: row == -1 || col > 0 ? 1 : 2,
                          lineHeight: row == -1 ? 11 : 14,
                          lastLineWidth: col == 0 ? 0.8 : 0.65,
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
    return SkeletonRegion(
      child: inCard ? SurfaceCard(padding: 0, child: content) : content,
    );
  }
}

class SkeletonForm extends StatelessWidget {
  const SkeletonForm({
    super.key,
    this.fields = 5,
    this.columns = 1,
    this.actions = true,
    this.padding = 0,
    this.maxWidth = 720,
    this.fieldHeights = const {},
    this.helperLines = const {},
  });
  final int fields;
  final int columns;
  final bool actions;
  final double padding;
  final double maxWidth;

  /// Inputs/selects default to 48; callers can reserve actual textarea heights.
  final Map<int, double> fieldHeights;
  final Map<int, int> helperLines;

  Widget _fields(int count) {
    Widget field(int index) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SkeletonText(lineHeight: 13, lastLineWidth: 0.35),
        const SizedBox(height: 8),
        SkeletonBase(
          height: fieldHeights[index] ?? 48,
          radius: AppRadius.control,
        ),
        if ((helperLines[index] ?? 0) > 0) ...[
          const SizedBox(height: 6),
          SkeletonText(lines: helperLines[index]!, lineHeight: 12),
        ],
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var row = 0; row < fields; row += count) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var col = 0; col < count; col++) ...[
                if (col > 0) const SizedBox(width: 16),
                Expanded(
                  child: row + col < fields
                      ? field(row + col)
                      : const SizedBox.shrink(),
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),
        ],
        if (actions)
          const Align(
            alignment: AlignmentDirectional.centerEnd,
            child: SkeletonButton(),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => SkeletonRegion(
    child: Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(
          padding: EdgeInsets.all(padding),
          // AlertDialog uses intrinsic/dry layout. A one-column form needs no
          // LayoutBuilder, so inline reference placeholders remain dialog-safe.
          child: columns == 1
              ? _fields(1)
              : LayoutBuilder(
                  builder: (context, box) =>
                      _fields(box.maxWidth >= 560 ? columns : 1),
                ),
        ),
      ),
    ),
  );
}

class SkeletonStats extends StatelessWidget {
  const SkeletonStats({
    super.key,
    this.count = 6,
    this.minimumWidth = 220,
    this.maxColumns = 4,
    this.gap = 16,
  });
  final int count;
  final double minimumWidth;
  final int maxColumns;
  final double gap;

  @override
  Widget build(BuildContext context) => SkeletonRegion(
    child: AdaptiveGrid(
      minimumWidth: minimumWidth,
      maxColumns: maxColumns,
      gap: gap,
      children: [
        for (var i = 0; i < count; i++)
          SurfaceCard(
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 94),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: SkeletonText(lines: 2, lineHeight: 14)),
                      SizedBox(width: 10),
                      SkeletonAvatar(size: 36),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const SkeletonText(lineHeight: 31, lastLineWidth: 0.7),
                ],
              ),
            ),
          ),
      ],
    ),
  );
}

class SkeletonChart extends StatelessWidget {
  const SkeletonChart({super.key, this.height = 180, this.inCard = true});
  final double height;
  final bool inCard;

  @override
  Widget build(BuildContext context) {
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SkeletonText(lineHeight: 17, lastLineWidth: 0.55),
        const SizedBox(height: 16),
        SizedBox(
          height: height,
          child: Stack(
            children: [
              for (final fraction in [0.25, 0.5, 0.75, 1.0])
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: (height - 1) * fraction,
                  child: const SkeletonBase(height: 1, radius: 0),
                ),
              Positioned.fill(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (var i = 0; i < 7; i++)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: SkeletonBase(
                            height:
                                height *
                                [0.3, 0.5, 0.4, 0.7, 0.6, 0.85, 0.72][i],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
    return SkeletonRegion(
      child: inCard ? SurfaceCard(child: content) : content,
    );
  }
}
