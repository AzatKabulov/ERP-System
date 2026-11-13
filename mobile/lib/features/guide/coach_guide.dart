import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';

/// One tip of a guide: the control it points at (by the key the control already has; the first one
/// that is on screen is used, so a phone's tab and a computer's menu item can share a step) and
/// what to say about it.
class GuideStep {
  const GuideStep(this.targets, this.text);
  final List<String> targets;
  final String Function(AppLocalizations l) text;
}

/// The first-time tips on each page, with arrows, "Next" and "Skip".
class Guides {
  /// Off in widget tests, so a tip never covers the screen under test.
  static bool enabled = true;

  static String _key(String id) => 'guide.$id.done';

  static bool seen(SharedPreferences prefs, String id) =>
      prefs.getBool(_key(id)) ?? false;

  static Future<void> markSeen(SharedPreferences prefs, String id) =>
      prefs.setBool(_key(id), true);

  /// Makes every page's tips appear again the next time the page is opened.
  static Future<void> resetAll(SharedPreferences prefs) async {
    for (final key in prefs.getKeys().where((k) => k.startsWith('guide.'))) {
      await prefs.remove(key);
    }
  }
}

/// Shows [steps] once, the first time [child] is on screen. Skipping counts as seen.
class GuideOnce extends StatefulWidget {
  const GuideOnce({
    super.key,
    required this.id,
    required this.preferences,
    required this.steps,
    required this.child,
  });

  final String id;
  final SharedPreferences preferences;
  final List<GuideStep> steps;
  final Widget child;

  @override
  State<GuideOnce> createState() => _GuideOnceState();
}

class _GuideOnceState extends State<GuideOnce> {
  @override
  void initState() {
    super.initState();
    if (Guides.enabled && !Guides.seen(widget.preferences, widget.id)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _start());
    }
  }

  Future<void> _start() async {
    // let the page finish arriving (its own animations) before pointing at anything on it
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
    await showGuide(context, widget.steps);
    await Guides.markSeen(widget.preferences, widget.id);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Runs the tips. Steps whose control is not on screen are left out.
Future<void> showGuide(BuildContext context, List<GuideStep> steps) =>
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (_, _, _) => _GuideOverlay(steps: steps),
    );

/// The element of the first of [names] that is on screen (it keeps that key and has a size).
Element? _find(List<String> names) {
  for (final name in names) {
    Element? found;
    void visit(Element e) {
      if (found != null) return;
      final key = e.widget.key;
      if (key is ValueKey<String> && key.value == name) {
        final box = e.renderObject;
        if (box is RenderBox &&
            box.attached &&
            box.hasSize &&
            !box.size.isEmpty) {
          found = e;
          return;
        }
      }
      e.visitChildren(visit);
    }

    WidgetsBinding.instance.rootElement?.visitChildren(visit);
    if (found != null) return found;
  }
  return null;
}

class _GuideOverlay extends StatefulWidget {
  const _GuideOverlay({required this.steps});
  final List<GuideStep> steps;

  @override
  State<_GuideOverlay> createState() => _GuideOverlayState();
}

class _GuideOverlayState extends State<_GuideOverlay> {
  /// The steps that have something to point at (checked when the tips start).
  late final List<GuideStep> _steps = [
    for (final s in widget.steps)
      if (_find(s.targets) != null) s,
  ];
  int _index = 0;
  Element? _target;
  Rect? _rect;
  bool _scrolling = false;
  bool _closed = false;

  /// The tips' own drawing area. Where a control is, and how much room there is, are both
  /// measured against this, never against the window, so the two always agree.
  final _area = GlobalKey();

  @override
  void initState() {
    super.initState();
    if (_steps.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _close());
      return;
    }
    _enter();
    _follow();
  }

  void _close() {
    if (_closed || !mounted) return;
    _closed = true;
    Navigator.of(context).pop();
  }

  /// Finds this step's control now (not earlier: the page may have moved since), brings it into
  /// view, and starts pointing at it.
  Future<void> _enter() async {
    final step = _steps[_index];
    final target = _find(step.targets);
    if (target == null) {
      _next();
      return;
    }
    _target = target;
    _rect = null;
    _scrolling = true;
    try {
      await Scrollable.ensureVisible(
        target,
        alignment: 0.4,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    } on Object {
      // not inside a scroll view: it is where it is
    }
    _scrolling = false;
  }

  /// Every frame: where the control is now. The tip follows it if the page still moves.
  void _follow() {
    if (_closed || !mounted) return;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (_closed || !mounted) return;
      final target = _target;
      if (target != null && !_scrolling) {
        final box = target.mounted ? target.renderObject : null;
        if (box is RenderBox && box.attached && box.hasSize) {
          final area = _area.currentContext?.findRenderObject();
          if (area is RenderBox && area.attached) {
            final rect =
                area.globalToLocal(box.localToGlobal(Offset.zero)) & box.size;
            if (rect != _rect) setState(() => _rect = rect);
          }
        } else {
          // the control went away (the page changed): look for it again, or move on
          final again = _find(_steps[_index].targets);
          if (again == null) {
            _next();
          } else {
            _target = again;
          }
        }
      }
      _follow();
    });
  }

  void _next() {
    if (_index >= _steps.length - 1) {
      _close();
      return;
    }
    setState(() {
      _index++;
      _rect = null;
      _target = null;
    });
    _enter();
  }

  void _back() {
    if (_index == 0) return;
    setState(() {
      _index--;
      _rect = null;
      _target = null;
    });
    _enter();
  }

  @override
  Widget build(BuildContext context) {
    if (_steps.isEmpty) return const SizedBox.expand();
    final rect = _rect;
    return SizedBox.expand(
      key: _area,
      child: rect == null
          ? const SizedBox.shrink()
          : LayoutBuilder(
              builder: (context, box) => _tip(context, box.biggest, rect),
            ),
    );
  }

  Widget _tip(BuildContext context, Size screen, Rect rect) {
    final l = strings(context);
    final step = _steps[_index];
    final hole = rect.inflate(6);
    // the tip goes on the side of the control that has more room
    final below = screen.height - hole.bottom > hole.top;
    final room = (below ? screen.height - hole.bottom : hole.top) - 28;
    final cardHeight = room.clamp(72.0, screen.height - 32);
    final width = (screen.width - 32).clamp(0.0, 330.0);
    final left = (hole.center.dx - width / 2).clamp(
      16.0,
      screen.width - width - 16,
    );
    final arrowX = (hole.center.dx - left).clamp(24.0, width - 24);
    final last = _index == _steps.length - 1;
    final card = Material(
      key: const ValueKey('guide-card'),
      color: Colors.transparent,
      child: Container(
        width: width,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.line),
          boxShadow: const [
            BoxShadow(
              color: Color(0x55000000),
              blurRadius: 24,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              step.text(l),
              style: const TextStyle(
                fontSize: 15,
                height: 1.45,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 14),
            if (_steps.length > 1)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  l.suStepOf(_index + 1, _steps.length),
                  style: TextStyle(color: AppColors.muted, fontSize: 12),
                ),
              ),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 4,
              children: [
                TextButton(
                  key: const ValueKey('guide-skip'),
                  onPressed: _close,
                  child: Text(l.suSkip),
                ),
                if (_index > 0)
                  TextButton(
                    key: const ValueKey('guide-back'),
                    onPressed: _back,
                    child: Text(l.pfBack),
                  ),
                FilledButton(
                  key: const ValueKey('guide-next'),
                  onPressed: _next,
                  child: Text(last ? l.guDone : l.suNext),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    final arrow = CustomPaint(
      size: const Size(20, 10),
      painter: _ArrowPainter(color: AppColors.surface, up: below),
    );
    return Stack(
      children: [
        // the dimmed screen with a hole where the control is; taps are absorbed
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {},
            child: CustomPaint(painter: _DimPainter(hole)),
          ),
        ),
        Positioned(
          left: left,
          top: below ? hole.bottom + 2 : null,
          bottom: below ? null : screen.height - hole.top + 2,
          width: width,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (below)
                Padding(
                  padding: EdgeInsets.only(left: arrowX - 10),
                  child: arrow,
                ),
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: cardHeight),
                child: SingleChildScrollView(child: card),
              ),
              if (!below)
                Padding(
                  padding: EdgeInsets.only(left: arrowX - 10),
                  child: arrow,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DimPainter extends CustomPainter {
  _DimPainter(this.hole);
  final Rect hole;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRRect(RRect.fromRectAndRadius(hole, const Radius.circular(14)));
    canvas.drawPath(path, Paint()..color = const Color(0xB0060A18));
    canvas.drawRRect(
      RRect.fromRectAndRadius(hole, const Radius.circular(14)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = AppColors.blue,
    );
  }

  @override
  bool shouldRepaint(_DimPainter old) => old.hole != hole;
}

class _ArrowPainter extends CustomPainter {
  _ArrowPainter({required this.color, required this.up});
  final Color color;
  final bool up;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();
    if (up) {
      path
        ..moveTo(0, size.height)
        ..lineTo(size.width / 2, 0)
        ..lineTo(size.width, size.height);
    } else {
      path
        ..moveTo(0, 0)
        ..lineTo(size.width / 2, size.height)
        ..lineTo(size.width, 0);
    }
    canvas.drawPath(path..close(), Paint()..color = color);
  }

  @override
  bool shouldRepaint(_ArrowPainter old) => old.up != up || old.color != color;
}
