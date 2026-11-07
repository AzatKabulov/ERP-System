import 'dart:async';

import 'package:flutter/material.dart';
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
  /// Off in widget tests, so a tip never covers the screen a test is looking at.
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
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;
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

Element? _find(String name) {
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
  return found;
}

class _GuideOverlay extends StatefulWidget {
  const _GuideOverlay({required this.steps});
  final List<GuideStep> steps;

  @override
  State<_GuideOverlay> createState() => _GuideOverlayState();
}

class _GuideOverlayState extends State<_GuideOverlay> {
  /// The steps that have something to point at, with where it is.
  final List<(GuideStep, Rect)> _shown = [];
  int _index = 0;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  Future<void> _measure() async {
    for (final step in widget.steps) {
      Element? target;
      for (final name in step.targets) {
        target = _find(name);
        if (target != null) break;
      }
      if (target == null) continue;
      try {
        await Scrollable.ensureVisible(
          target,
          alignment: 0.4,
          duration: const Duration(milliseconds: 150),
        );
      } on Object {
        // not inside a scroll view: it is where it is
      }
      final box = target.renderObject;
      if (box is! RenderBox || !box.attached) continue;
      final rect = box.localToGlobal(Offset.zero) & box.size;
      _shown.add((step, rect));
    }
    if (!mounted) return;
    if (_shown.isEmpty) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _ready = true);
  }

  void _next() {
    if (_index >= _shown.length - 1) {
      Navigator.of(context).pop();
    } else {
      setState(() => _index++);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) return const SizedBox.expand();
    final l = strings(context);
    final screen = MediaQuery.sizeOf(context);
    final (step, rect) = _shown[_index];
    final hole = rect.inflate(6);
    final below = hole.center.dy < screen.height * 0.5;
    final width = (screen.width - 32).clamp(0.0, 330.0);
    final left = (hole.center.dx - width / 2).clamp(
      16.0,
      screen.width - width - 16,
    );
    final arrowX = (hole.center.dx - left).clamp(24.0, width - 24);
    final last = _index == _shown.length - 1;
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
            if (_shown.length > 1)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  l.suStepOf(_index + 1, _shown.length),
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
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(l.suSkip),
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
              card,
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
