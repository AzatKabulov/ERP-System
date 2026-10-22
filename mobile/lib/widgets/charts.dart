import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'motion.dart';

/// A line over the last days, filled below with a soft gradient. It draws itself from left to
/// right, and a finger or the pointer over it names the day and the figure.
class AreaChart extends StatefulWidget {
  const AreaChart({
    super.key,
    required this.values,
    required this.labelFor,
    required this.valueText,
    this.onDark = false,
    this.height = 120,
  });

  /// One figure per day, oldest first (a day without sales is zero).
  final List<int> values;

  /// The day of the point at an index, for the tooltip.
  final String Function(int index) labelFor;

  /// The figure at an index as text, for the tooltip.
  final String Function(int index) valueText;

  /// On the navy spotlight the line is light; on a white card it is cobalt.
  final bool onDark;
  final double height;

  @override
  State<AreaChart> createState() => _AreaChartState();
}

class _AreaChartState extends State<AreaChart>
    with SingleTickerProviderStateMixin {
  late final AnimationController _draw = AnimationController(
    vsync: this,
    duration: AppMotion.slow,
  );
  int? _active;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (AppMotion.reduced(context)) {
      _draw.value = 1;
    } else {
      _draw.forward();
    }
  }

  @override
  void dispose() {
    _draw.dispose();
    super.dispose();
  }

  void _pick(double dx, double width) {
    final n = widget.values.length;
    if (n < 2) return;
    final index = ((dx - _padX) / (width - 2 * _padX) * (n - 1)).round().clamp(
      0,
      n - 1,
    );
    if (index != _active) setState(() => _active = index);
  }

  static const _padX = 6.0;
  static const _padTop = 12.0;
  static const _padBottom = 8.0;

  @override
  Widget build(BuildContext context) {
    final values = widget.values;
    return LayoutBuilder(
      builder: (context, box) {
        final width = box.maxWidth;
        final maxV = math.max(1, values.reduce(math.max));
        Offset point(int i) => Offset(
          _padX + (width - 2 * _padX) * i / (values.length - 1),
          _padTop +
              (widget.height - _padTop - _padBottom) * (1 - values[i] / maxV),
        );
        final active = _active;
        return MouseRegion(
          onHover: (e) => _pick(e.localPosition.dx, width),
          onExit: (_) => setState(() => _active = null),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (d) => _pick(d.localPosition.dx, width),
            onHorizontalDragUpdate: (d) => _pick(d.localPosition.dx, width),
            onTapUp: (_) => setState(() => _active = null),
            onHorizontalDragEnd: (_) => setState(() => _active = null),
            child: SizedBox(
              height: widget.height,
              width: width,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _AreaPainter(
                        values: values,
                        progress: _draw,
                        active: active,
                        onDark: widget.onDark,
                        padX: _padX,
                        padTop: _padTop,
                        padBottom: _padBottom,
                      ),
                    ),
                  ),
                  if (active != null)
                    Positioned(
                      left: (point(active).dx - 62).clamp(0, width - 124),
                      top: math.max(-6, point(active).dy - 58),
                      width: 124,
                      child: IgnorePointer(
                        child: _Tooltip(
                          title: widget.labelFor(active),
                          value: widget.valueText(active),
                          onDark: widget.onDark,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Tooltip extends StatelessWidget {
  const _Tooltip({
    required this.title,
    required this.value,
    required this.onDark,
  });
  final String title;
  final String value;
  final bool onDark;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: onDark ? Colors.white : AppColors.ink,
      borderRadius: BorderRadius.circular(10),
      boxShadow: const [
        BoxShadow(
          color: Color(0x33000000),
          offset: Offset(0, 6),
          blurRadius: 16,
        ),
      ],
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 11,
              color: onDark ? AppColors.muted : AppColors.onInverseMuted,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: onDark ? AppColors.ink : Colors.white,
              fontFeatures: AppFonts.tabular,
            ),
          ),
        ],
      ),
    ),
  );
}

class _AreaPainter extends CustomPainter {
  _AreaPainter({
    required this.values,
    required this.progress,
    required this.active,
    required this.onDark,
    required this.padX,
    required this.padTop,
    required this.padBottom,
  }) : super(repaint: progress);

  final List<int> values;
  final Animation<double> progress;
  final int? active;
  final bool onDark;
  final double padX;
  final double padTop;
  final double padBottom;

  @override
  void paint(Canvas canvas, Size size) {
    final n = values.length;
    if (n < 2) return;
    final maxV = math.max(1, values.reduce(math.max));
    final top = padTop;
    final bottom = size.height - padBottom;
    Offset point(int i) => Offset(
      padX + (size.width - 2 * padX) * i / (n - 1),
      bottom - (bottom - top) * values[i] / maxV,
    );

    final line = onDark ? const Color(0xFF8CA2FF) : AppColors.blue;
    final grid = onDark ? const Color(0x1AFFFFFF) : AppColors.line;
    for (final f in [0.0, 0.5, 1.0]) {
      final y = bottom - (bottom - top) * f;
      canvas.drawLine(
        Offset(padX, y),
        Offset(size.width - padX, y),
        Paint()
          ..color = grid
          ..strokeWidth = 1,
      );
    }

    final path = Path()..moveTo(point(0).dx, point(0).dy);
    for (var i = 1; i < n; i++) {
      final a = point(i - 1);
      final b = point(i);
      final mid = (a.dx + b.dx) / 2;
      path.cubicTo(mid, a.dy, mid, b.dy, b.dx, b.dy);
    }
    final fill = Path.from(path)
      ..lineTo(point(n - 1).dx, bottom)
      ..lineTo(point(0).dx, bottom)
      ..close();

    final t = Curves.easeOutCubic.transform(progress.value);
    canvas
      ..save()
      ..clipRect(Rect.fromLTWH(0, -20, size.width * t, size.height + 40))
      ..drawPath(
        fill,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              line.withValues(alpha: onDark ? 0.40 : 0.24),
              line.withValues(alpha: 0),
            ],
          ).createShader(Rect.fromLTWH(0, top, size.width, bottom - top)),
      )
      ..drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = line,
      )
      ..restore();

    // the marked day: the one under the pointer, otherwise the latest
    final index = active ?? n - 1;
    if (active != null || progress.value >= 1) {
      final p = point(index);
      if (active != null) {
        canvas.drawLine(
          Offset(p.dx, top),
          Offset(p.dx, bottom),
          Paint()
            ..color = line.withValues(alpha: 0.35)
            ..strokeWidth = 1,
        );
      }
      canvas
        ..drawCircle(p, 9, Paint()..color = line.withValues(alpha: 0.22))
        ..drawCircle(p, 5, Paint()..color = onDark ? Colors.white : line)
        ..drawCircle(
          p,
          5,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = onDark ? line : Colors.white,
        );
    }
  }

  @override
  bool shouldRepaint(_AreaPainter old) =>
      old.values != values || old.active != active || old.onDark != onDark;
}

/// One row of a [BarList].
class BarItem {
  const BarItem({required this.label, required this.value, required this.text});
  final String label;
  final int value;

  /// The figure as text, shown at the right of the label.
  final String text;
}

/// Horizontal bars compared by length: the label and the figure on top, a rounded bar under
/// them that grows to its share of the largest when the list first shows.
class BarList extends StatelessWidget {
  const BarList({super.key, required this.items});
  final List<BarItem> items;

  @override
  Widget build(BuildContext context) {
    final maxV = math.max(
      1,
      items.fold<int>(0, (m, i) => math.max(m, i.value)),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(height: 16),
          _BarRow(item: items[i], fraction: items[i].value / maxV, index: i),
        ],
      ],
    );
  }
}

class _BarRow extends StatelessWidget {
  const _BarRow({
    required this.item,
    required this.fraction,
    required this.index,
  });
  final BarItem item;
  final double fraction;
  final int index;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 2,
        children: [
          Text(
            item.label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          Text(
            item.text,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(
          height: 10,
          child: Stack(
            children: [
              const Positioned.fill(
                child: ColoredBox(color: AppColors.surfaceMuted),
              ),
              TweenAnimationBuilder<double>(
                tween: Tween(
                  begin: AppMotion.reduced(context) ? fraction : 0,
                  end: fraction,
                ),
                duration: AppMotion.of(
                  context,
                  Duration(milliseconds: 700 + index * 120),
                ),
                curve: AppMotion.arrive,
                builder: (context, f, _) => FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: f.clamp(0.0, 1.0),
                  heightFactor: 1,
                  child: const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFF2B55FF), Color(0xFF6A4DFF)],
                      ),
                      borderRadius: BorderRadius.all(Radius.circular(6)),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ],
  );
}

/// One slice of a [DonutChart].
class DonutSlice {
  const DonutSlice(this.value, this.color);
  final int value;
  final Color color;
}

/// Shares of a whole as a ring that sweeps round when it first shows, with [center] in the hole.
class DonutChart extends StatelessWidget {
  const DonutChart({
    super.key,
    required this.slices,
    required this.center,
    this.size = 148,
    this.thickness = 18,
  });
  final List<DonutSlice> slices;
  final Widget center;
  final double size;
  final double thickness;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: Stack(
      alignment: Alignment.center,
      children: [
        TweenAnimationBuilder<double>(
          tween: Tween(begin: AppMotion.reduced(context) ? 1 : 0, end: 1),
          duration: AppMotion.of(context, const Duration(milliseconds: 1000)),
          curve: AppMotion.arrive,
          builder: (context, t, _) => CustomPaint(
            size: Size.square(size),
            painter: _DonutPainter(slices, t, thickness),
          ),
        ),
        Padding(padding: EdgeInsets.all(thickness + 8), child: center),
      ],
    ),
  );
}

class _DonutPainter extends CustomPainter {
  _DonutPainter(this.slices, this.t, this.thickness);
  final List<DonutSlice> slices;
  final double t;
  final double thickness;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(thickness / 2);
    final total = slices.fold<int>(0, (s, e) => s + e.value);
    canvas.drawArc(
      rect,
      0,
      math.pi * 2,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = thickness
        ..color = AppColors.surfaceMuted,
    );
    if (total <= 0) return;
    // round ends reach half a thickness past each arc: leave a clear 5 px between slices
    final gap = slices.where((s) => s.value > 0).length > 1
        ? (thickness + 5) / (rect.width / 2)
        : 0.0;
    var start = -math.pi / 2;
    for (final slice in slices) {
      if (slice.value <= 0) continue;
      final full = math.pi * 2 * slice.value / total;
      final sweep = math.max(0.001, full * t - gap);
      canvas.drawArc(
        rect,
        start + gap / 2,
        sweep,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = thickness
          ..strokeCap = StrokeCap.round
          ..color = slice.color,
      );
      start += full * t;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter old) =>
      old.t != t || old.slices != slices || old.thickness != thickness;
}
