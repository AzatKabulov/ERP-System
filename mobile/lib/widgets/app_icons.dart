import 'dart:math' as math;

import 'package:flutter/material.dart';

/// One icon of the design: thin (1.5 px on a 24-pixel grid) rounded line art, drawn from SVG
/// path data, circles and rounded rectangles so that it matches the design file exactly.
class AppIconData {
  const AppIconData({
    this.paths = const [],
    this.circles = const [],
    this.rects = const [],
    this.dots = const [],
  });

  /// SVG path data, stroked.
  final List<String> paths;

  /// Stroked circles: (centre x, centre y, radius).
  final List<(double, double, double)> circles;

  /// Stroked rounded rectangles: (x, y, width, height, corner radius).
  final List<(double, double, double, double, double)> rects;

  /// Solid dots: (centre x, centre y, radius).
  final List<(double, double, double)> dots;
}

/// The icons. The first group is the design file's own set; the second group follows the same
/// drawing rules for the few places the file has no icon.
abstract final class AppIcons {
  // ---- the design's set ----
  static const overview = AppIconData(
    rects: [
      (3, 3, 7, 7, 1.5),
      (14, 3, 7, 7, 1.5),
      (3, 14, 7, 7, 1.5),
      (14, 14, 7, 7, 1.5),
    ],
  );
  static const box = AppIconData(
    paths: ['m4 7 8-4 8 4-8 4-8-4Z', 'M4 7v10l8 4 8-4V7M12 11v10'],
  );
  static const stock = AppIconData(
    paths: [
      'M3 21h18M5 21V6l7-3 7 3v15',
      'M8 9h2M14 9h2M8 13h2M14 13h2M10 21v-4h4v4',
    ],
  );
  static const cart = AppIconData(
    paths: ['M3 4h2l2.2 10.1a2 2 0 0 0 2 1.6h7.7a2 2 0 0 0 2-1.6L20 8H6'],
    circles: [(9, 20, 1), (17, 20, 1)],
  );
  static const sale = AppIconData(
    paths: ['M6 3h12v18l-3-2-3 2-3-2-3 2V3Z', 'M9 8h6M9 12h6'],
  );
  static const receipt = sale;
  static const expense = AppIconData(
    paths: [
      'M12 7v10M15 9.5c-.6-1-1.5-1.5-3-1.5-1.7 0-3 1-3 2.3 0 3.7 6 1.1 6 4.2 0 1.4-1.3 2.5-3.2 2.5-1.4 0-2.5-.5-3.2-1.5',
    ],
    circles: [(12, 12, 9)],
  );
  static const shield = AppIconData(
    paths: ['M12 3 20 6v6c0 5-3.4 8-8 9-4.6-1-8-4-8-9V6l8-3Z', 'm9 12 2 2 4-4'],
  );
  static const chart = AppIconData(
    paths: ['M4 20V10M10 20V4M16 20v-7M22 20H2'],
  );
  static const settings = AppIconData(
    paths: [
      'M19.4 15a1.7 1.7 0 0 0 .3 1.9l.1.1-2.8 2.8-.1-.1a1.7 1.7 0 0 0-1.9-.3 1.7 1.7 0 0 0-1 1.6v.2h-4V21a1.7 1.7 0 0 0-1-1.6 1.7 1.7 0 0 0-1.9.3l-.1.1L4.2 17l.1-.1a1.7 1.7 0 0 0 .3-1.9A1.7 1.7 0 0 0 3 14H2.8v-4H3a1.7 1.7 0 0 0 1.6-1 1.7 1.7 0 0 0-.3-1.9L4.2 7 7 4.2l.1.1A1.7 1.7 0 0 0 9 4.6a1.7 1.7 0 0 0 1-1.6v-.2h4V3a1.7 1.7 0 0 0 1 1.6 1.7 1.7 0 0 0 1.9-.3l.1-.1L19.8 7l-.1.1a1.7 1.7 0 0 0-.3 1.9 1.7 1.7 0 0 0 1.6 1h.2v4H21a1.7 1.7 0 0 0-1.6 1Z',
    ],
    circles: [(12, 12, 3)],
  );
  static const search = AppIconData(
    paths: ['m16 16 4.5 4.5'],
    circles: [(10.5, 10.5, 6.5)],
  );
  static const scan = AppIconData(
    paths: ['M4 8V4h4M16 4h4v4M20 16v4h-4M8 20H4v-4M8 9v6M11 9v6M15 9v6'],
  );
  static const plus = AppIconData(paths: ['M12 5v14M5 12h14']);
  static const minus = AppIconData(paths: ['M5 12h14']);
  static const trash = AppIconData(
    paths: ['M4 7h16M9 7V4h6v3M7 7l1 14h8l1-14M10 11v6M14 11v6'],
  );
  static const chevron = AppIconData(paths: ['m9 6 6 6-6 6']);
  static const menu = AppIconData(paths: ['M4 7h16M4 12h16M4 17h16']);
  static const close = AppIconData(paths: ['M5 5l14 14M19 5 5 19']);
  static const check = AppIconData(paths: ['m5 12 4 4L19 6']);
  static const warning = AppIconData(
    paths: ['M12 3 2.8 20h18.4L12 3Z', 'M12 9v4M12 17h.01'],
  );
  static const info = AppIconData(
    paths: ['M12 11v6M12 7h.01'],
    circles: [(12, 12, 9)],
  );
  static const clock = AppIconData(
    paths: ['M12 7v5l3 2'],
    circles: [(12, 12, 9)],
  );
  static const arrow = AppIconData(paths: ['M5 12h14m-5-5 5 5-5 5']);
  static const download = AppIconData(paths: ['M12 3v12m-4-4 4 4 4-4M4 20h16']);
  static const upload = AppIconData(paths: ['M12 16V4m-4 4 4-4 4 4M4 20h16']);
  static const camera = AppIconData(
    paths: ['M4 8h3l1.5-2h7L17 8h3v11H4V8Z'],
    circles: [(12, 13, 3.5)],
  );
  static const image = AppIconData(
    paths: ['m4 18 5-5 3 3 2-2 6 5'],
    circles: [(9, 10, 2)],
    rects: [(3, 4, 18, 16, 2)],
  );
  static const file = AppIconData(
    paths: ['M6 3h8l4 4v14H6V3Z', 'M14 3v5h4M9 13h6M9 17h6'],
  );
  static const print = AppIconData(
    paths: ['M7 9V3h10v6M7 18H4v-7h16v7h-3M7 15h10v6H7v-6Z'],
  );
  static const share = AppIconData(
    paths: ['m8 11 8-5M8 13l8 5'],
    circles: [(18, 5, 2), (6, 12, 2), (18, 19, 2)],
  );
  static const user = AppIconData(
    paths: ['M4 21c.8-4.3 3.5-6 8-6s7.2 1.7 8 6'],
    circles: [(12, 8, 4)],
  );
  static const lock = AppIconData(
    paths: ['M8 10V7a4 4 0 0 1 8 0v3'],
    rects: [(5, 10, 14, 11, 2)],
  );
  static const eye = AppIconData(
    paths: [
      'M2.5 12S6 6.5 12 6.5 21.5 12 21.5 12 18 17.5 12 17.5 2.5 12 2.5 12Z',
    ],
    circles: [(12, 12, 2.5)],
  );
  static const returnArrow = AppIconData(
    paths: ['m8 8-4 4 4 4', 'M4 12h10a5 5 0 0 1 5 5v2'],
  );
  static const truck = AppIconData(
    paths: ['M3 6h11v11H3V6ZM14 10h4l3 3v4h-7v-7Z'],
    circles: [(7, 19, 2), (18, 19, 2)],
  );
  static const edit = AppIconData(
    paths: ['m14 5 5 5L9 20H4v-5L14 5Z', 'm12 7 5 5'],
  );
  static const dots = AppIconData(dots: [(5, 12, 1), (12, 12, 1), (19, 12, 1)]);
  static const wifi = AppIconData(
    paths: [
      'M4 9a12 12 0 0 1 16 0M7 13a8 8 0 0 1 10 0M10 17a3 3 0 0 1 4 0M12 21h.01',
    ],
  );
  static const retry = AppIconData(
    paths: [
      'M20 7v5h-5M4 17v-5h5',
      'M18.5 9A7.5 7.5 0 0 0 6 6.5L4 9M5.5 15A7.5 7.5 0 0 0 18 17.5l2-2.5',
    ],
  );
  static const tag = AppIconData(
    paths: ['M3 12V4h8l10 10-7 7L3 12Z'],
    circles: [(8, 8, 1.5)],
  );

  // ---- the same drawing rules, for places the design file has no icon ----
  static const chevronDown = AppIconData(paths: ['m6 9 6 6 6-6']);
  static const back = AppIconData(paths: ['M19 12H5m5-5-5 5 5 5']);
  static const logout = AppIconData(
    paths: ['M9 4H5v16h4M16 8l4 4-4 4M20 12H9'],
  );
  static const login = AppIconData(
    paths: ['M15 4h4v16h-4M10 8l4 4-4 4M14 12H3'],
  );
  static const history = AppIconData(
    paths: ['M3 12a9 9 0 1 0 3-6.7L3 8M3 3v5h5', 'M12 7v5l3 2'],
  );
  static const swap = AppIconData(
    paths: ['M7 4 3 8l4 4M3 8h14M17 20l4-4-4-4M21 16H7'],
  );
  static const checklist = AppIconData(
    paths: [
      'm4 6 1.5 1.5L8 5M4 13l1.5 1.5L8 12M4 20l1.5 1.5L8 19M11 6h9M11 13h9M11 20h9',
    ],
  );
  static const tune = AppIconData(
    paths: ['M4 7h9M17 7h3M4 17h3M11 17h9M13 5v4M7 15v4'],
  );
  static const listPlus = AppIconData(
    paths: ['M4 6h12M4 12h8M4 18h8M17 15v6M14 18h6'],
  );
  static const list = AppIconData(
    paths: ['M8 6h13M8 12h13M8 18h13M3.5 6h.01M3.5 12h.01M3.5 18h.01'],
  );
  static const mail = AppIconData(paths: ['M3 6h18v12H3V6Z', 'm3 7 9 7 9-7']);
  static const flash = AppIconData(paths: ['M13 2 4 14h7l-1 8 9-12h-7l1-8Z']);
  static const keyboard = AppIconData(
    paths: ['M3 7h18v10H3V7Z', 'M7 10h.01M11 10h.01M15 10h.01M7 14h10'],
  );
  static const archive = AppIconData(
    paths: ['M3 4h18v4H3V4Z', 'M5 8v12h14V8M10 12h4'],
  );
  static const send = AppIconData(
    paths: ['M21 3 10 14M21 3l-7 18-4-7-7-4 18-7Z'],
  );
  static const block = AppIconData(
    paths: ['M5.6 5.6l12.8 12.8'],
    circles: [(12, 12, 9)],
  );
  static const folder = AppIconData(paths: ['M3 6h6l2 2h10v11H3V6Z']);
  static const event = AppIconData(
    paths: ['M4 6h16v14H4V6Z', 'M4 11h16M8 3v4M16 3v4'],
  );
  static const brake = AppIconData(circles: [(12, 12, 9), (12, 12, 3)]);
  static const drop = AppIconData(
    paths: ['M12 3s6 6.5 6 11a6 6 0 0 1-12 0c0-4.5 6-11 6-11Z'],
  );
  static const filter = AppIconData(paths: ['M4 5h16l-6 8v6l-4-2v-4L4 5Z']);
  static const noteAdd = AppIconData(
    paths: ['M6 3h8l4 4v14H6V3Z', 'M14 3v5h4M12 11v6M9 14h6'],
  );
  static const personAdd = AppIconData(
    paths: ['M2 21c.8-4.3 3-6 8-6M19 8v6M16 11h6'],
    circles: [(10, 8, 4)],
  );
  static const personOff = AppIconData(
    paths: ['M4 21c.8-4.3 3.5-6 8-6s7.2 1.7 8 6M4 4l16 16'],
    circles: [(12, 8, 4)],
  );
  static const attach = AppIconData(
    paths: [
      'M20 11 12 19a5 5 0 0 1-7-7l8-8a3.5 3.5 0 0 1 5 5l-8 8a2 2 0 0 1-3-3l7-7',
    ],
  );
  static const inbox = AppIconData(
    paths: ['M4 13l3-8h10l3 8v6H4v-6Z', 'M4 13h5l1 2h4l1-2h5'],
  );
  static const checkCircle = AppIconData(
    paths: ['m8 12 3 3 5-6'],
    circles: [(12, 12, 9)],
  );
  static const addCircle = AppIconData(
    paths: ['M12 8v8M8 12h8'],
    circles: [(12, 12, 9)],
  );
  static const removeCircle = AppIconData(
    paths: ['M8 12h8'],
    circles: [(12, 12, 9)],
  );
  static const qr = AppIconData(
    paths: ['M14 14h2v2h-2zM18 14h2M14 18h2M18 18h2v2h-2'],
    rects: [(4, 4, 6, 6, 1), (14, 4, 6, 6, 1), (4, 14, 6, 6, 1)],
  );
  static const save = AppIconData(
    paths: ['M5 3h12l3 3v15H5V3Z', 'M8 3v5h7V3M8 21v-7h8v7'],
  );
}

/// Draws an [AppIconData] with the current icon color and size (or the ones given).
class AppIcon extends StatelessWidget {
  const AppIcon(this.icon, {super.key, this.size, this.color});
  final AppIconData icon;
  final double? size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context);
    final side = size ?? theme.size ?? 20;
    return SizedBox(
      width: side,
      height: side,
      child: CustomPaint(
        painter: _IconPainter(
          icon,
          color ?? theme.color ?? const Color(0xFF0D1311),
        ),
      ),
    );
  }
}

class _IconPainter extends CustomPainter {
  _IconPainter(this.icon, this.color);
  final AppIconData icon;
  final Color color;

  static final _cache = <String, Path>{};

  static Path _path(String data) =>
      _cache.putIfAbsent(data, () => parseSvgPath(data));

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 24;
    canvas
      ..save()
      ..scale(scale);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color;
    for (final d in icon.paths) {
      canvas.drawPath(_path(d), stroke);
    }
    for (final (cx, cy, r) in icon.circles) {
      canvas.drawCircle(Offset(cx, cy), r, stroke);
    }
    for (final (x, y, w, h, r) in icon.rects) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(x, y, w, h), Radius.circular(r)),
        stroke,
      );
    }
    final fill = Paint()
      ..style = PaintingStyle.fill
      ..color = color;
    for (final (cx, cy, r) in icon.dots) {
      canvas.drawCircle(Offset(cx, cy), r, fill);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_IconPainter old) =>
      old.icon != icon || old.color != color;
}

final _tokenPattern = RegExp(
  r'([MmLlHhVvCcSsAaZz])|(-?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?)',
);

/// A small SVG path parser (M L H V C S A Z, absolute and relative): enough for the icons.
Path parseSvgPath(String data) {
  final tokens = _tokenPattern.allMatches(data).toList();
  final path = Path();
  var i = 0;
  var cx = 0.0, cy = 0.0; // current point
  var sx = 0.0, sy = 0.0; // start of the subpath
  var lastCx = 0.0, lastCy = 0.0; // last cubic control point
  var lastWasCubic = false;
  String? command;

  double next() => double.parse(tokens[i++].group(2)!);

  while (i < tokens.length) {
    if (tokens[i].group(1) != null) {
      command = tokens[i++].group(1);
      if (command == 'Z' || command == 'z') {
        path.close();
        cx = sx;
        cy = sy;
        lastWasCubic = false;
        continue;
      }
    } else if (command == null) {
      break;
    }
    final c = command!;
    final rel = c == c.toLowerCase();
    switch (c.toUpperCase()) {
      case 'M':
        var x = next(), y = next();
        if (rel) {
          x += cx;
          y += cy;
        }
        path.moveTo(x, y);
        cx = sx = x;
        cy = sy = y;
        command = rel ? 'l' : 'L'; // extra pairs are line-tos
        lastWasCubic = false;
      case 'L':
        var x = next(), y = next();
        if (rel) {
          x += cx;
          y += cy;
        }
        path.lineTo(x, y);
        cx = x;
        cy = y;
        lastWasCubic = false;
      case 'H':
        var x = next();
        if (rel) x += cx;
        path.lineTo(x, cy);
        cx = x;
        lastWasCubic = false;
      case 'V':
        var y = next();
        if (rel) y += cy;
        path.lineTo(cx, y);
        cy = y;
        lastWasCubic = false;
      case 'C':
        var x1 = next(), y1 = next(), x2 = next(), y2 = next();
        var x = next(), y = next();
        if (rel) {
          x1 += cx;
          y1 += cy;
          x2 += cx;
          y2 += cy;
          x += cx;
          y += cy;
        }
        path.cubicTo(x1, y1, x2, y2, x, y);
        lastCx = x2;
        lastCy = y2;
        cx = x;
        cy = y;
        lastWasCubic = true;
      case 'S':
        var x2 = next(), y2 = next();
        var x = next(), y = next();
        if (rel) {
          x2 += cx;
          y2 += cy;
          x += cx;
          y += cy;
        }
        final x1 = lastWasCubic ? 2 * cx - lastCx : cx;
        final y1 = lastWasCubic ? 2 * cy - lastCy : cy;
        path.cubicTo(x1, y1, x2, y2, x, y);
        lastCx = x2;
        lastCy = y2;
        cx = x;
        cy = y;
        lastWasCubic = true;
      case 'A':
        final rx = next(), ry = next(), rotation = next();
        final large = next() != 0, sweep = next() != 0;
        var x = next(), y = next();
        if (rel) {
          x += cx;
          y += cy;
        }
        if (rx == 0 || ry == 0) {
          path.lineTo(x, y);
        } else {
          path.arcToPoint(
            Offset(x, y),
            radius: Radius.elliptical(rx.abs(), ry.abs()),
            rotation: rotation * math.pi / 180,
            largeArc: large,
            clockwise: sweep,
          );
        }
        cx = x;
        cy = y;
        lastWasCubic = false;
      default:
        return path;
    }
  }
  return path;
}
