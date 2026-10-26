import 'dart:async';

import 'package:flutter/material.dart';

/// The motion language of the app: short, decelerating, and only where it explains something
/// (a state changed, something arrived, something was pressed). Every helper here skips its
/// animation when the system asks for reduced motion, so the content simply appears.
abstract final class AppMotion {
  /// Immediate feedback: a press, a hover.
  static const fast = Duration(milliseconds: 140);

  /// A routine change of state: a selection, a switch, a swapped value.
  static const base = Duration(milliseconds: 240);

  /// Something arriving: a page, a dialog, a chart drawing itself.
  static const slow = Duration(milliseconds: 260);

  /// Confident deceleration (exponential ease-out): fast start, long soft landing.
  static const arrive = Cubic(0.16, 1, 0.3, 1);

  static bool reduced(BuildContext context) =>
      MediaQuery.disableAnimationsOf(context);

  /// On narrow screens, show data immediately instead of simultaneously fading
  /// the page, staggering cards, relaying out counting numbers and drawing charts.
  /// Press/selection feedback keeps its normal short animation.
  static bool skipEntrance(BuildContext context) =>
      reduced(context) || MediaQuery.sizeOf(context).width < 768;

  static Duration entrance(BuildContext context, Duration duration) =>
      skipEntrance(context) ? Duration.zero : duration;

  /// [duration], or zero when motion is reduced.
  static Duration of(BuildContext context, Duration duration) =>
      reduced(context) ? Duration.zero : duration;
}

/// Content arriving: a fade and a short rise, played once when it first appears. Give each item
/// of a group its [index] and they arrive one after another (the total delay is capped, so a long
/// list never makes anyone wait).
class Reveal extends StatefulWidget {
  const Reveal({
    super.key,
    required this.child,
    this.index = 0,
    this.distance = 14,
  });
  final Widget child;

  /// The place in the group: 0 arrives first.
  final int index;
  final double distance;

  @override
  State<Reveal> createState() => _RevealState();
}

class _RevealState extends State<Reveal> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppMotion.slow,
  );
  late final CurvedAnimation _curve = CurvedAnimation(
    parent: _controller,
    curve: AppMotion.arrive,
  );
  Timer? _delay;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (AppMotion.skipEntrance(context)) {
      _controller.value = 1;
      return;
    }
    final wait = Duration(milliseconds: widget.index.clamp(0, 8) * 55);
    if (wait == Duration.zero) {
      _controller.forward();
    } else {
      _delay = Timer(wait, () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _delay?.cancel();
    _curve.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _curve,
      child: widget.child,
      builder: (context, child) {
        final t = _curve.value;
        // Keep the same element tree at completion: removing these wrappers
        // remounts stateful children and repeats their loads. Opacity at 1 does
        // not require an opacity compositing layer.
        return Opacity(
          opacity: t.clamp(0, 1),
          child: Transform.translate(
            offset: Offset(0, (1 - t) * widget.distance),
            child: child,
          ),
        );
      },
    );
  }
}

/// A figure that counts up to its value the first time it shows, and glides from the old value
/// to the new one when it changes. [format] turns the animated number into text.
class CountUp extends StatelessWidget {
  const CountUp({
    super.key,
    required this.value,
    required this.format,
    this.style,
    this.textAlign,
  });
  final num value;
  final String Function(num) format;
  final TextStyle? style;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    if (AppMotion.skipEntrance(context)) {
      return Text(format(value), style: style, textAlign: textAlign);
    }
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value.toDouble()),
      duration: AppMotion.slow,
      curve: AppMotion.arrive,
      builder: (context, v, _) => Text(
        format(v == value.toDouble() ? value : v.round()),
        style: style,
        textAlign: textAlign,
      ),
    );
  }
}

/// Gives anything tappable a press: it sinks a little under the finger and springs back.
class PressScale extends StatefulWidget {
  const PressScale({super.key, required this.child, this.scale = 0.985});
  final Widget child;
  final double scale;

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  bool _down = false;

  void _set(bool value) {
    if (_down != value) setState(() => _down = value);
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (_) => _set(true),
    onPointerUp: (_) => _set(false),
    onPointerCancel: (_) => _set(false),
    child: AnimatedScale(
      scale: _down && !AppMotion.reduced(context) ? widget.scale : 1,
      duration: AppMotion.fast,
      curve: Curves.easeOut,
      child: widget.child,
    ),
  );
}
