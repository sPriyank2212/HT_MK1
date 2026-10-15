/// The design's inline SVG icons, transcribed shape for shape.
///
/// Every icon in the approved page is a 24×24 `viewBox` stroked with
/// `fill:none`. The path data below is copied verbatim from `index.html`; the
/// widget scales the canvas by `size / 24` and strokes in viewBox units, which
/// is exactly what the browser does, so the line weight scales the same way.
library;

import 'package:flutter/widgets.dart';

import 'svg_path.dart';

/// One drawable element of an icon: a path, a rect or a circle.
sealed class IconShape {
  const IconShape();
  Path toPath();
}

class SvgPathShape extends IconShape {
  final String d;
  const SvgPathShape(this.d);
  @override
  Path toPath() => parseSvgPath(d);
}

class SvgRectShape extends IconShape {
  final double x, y, w, h, rx;
  const SvgRectShape(this.x, this.y, this.w, this.h, {this.rx = 0});
  @override
  Path toPath() => Path()
    ..addRRect(RRect.fromRectAndRadius(
      Rect.fromLTWH(x, y, w, h),
      Radius.circular(rx),
    ));
}

class SvgCircleShape extends IconShape {
  final double cx, cy, r;
  const SvgCircleShape(this.cx, this.cy, this.r);
  @override
  Path toPath() => Path()..addOval(Rect.fromCircle(center: Offset(cx, cy), radius: r));
}

class HtIconData {
  final List<IconShape> shapes;
  const HtIconData(this.shapes);
}

/// Every icon the page uses, keyed by where it appears.
class HtIcons {
  const HtIcons._();

  // ---- rail ----

  /// Run — `<path d="M6 4l13 8-13 8z"/>`
  static const run = HtIconData([SvgPathShape('M6 4l13 8-13 8z')]);

  /// Continuity — `<path d="M3 12h5l2-5 4 10 2-5h5"/>`
  static const cont = HtIconData([SvgPathShape('M3 12h5l2-5 4 10 2-5h5')]);

  /// Resistance — two paths
  static const res = HtIconData([
    SvgPathShape('M2 12h4l1.5-4 3 8 3-8 1.5 4h5'),
    SvgPathShape('M6 17h12'),
  ]);

  /// HV — `<path d="M13 2L4 14h6l-1 8 9-12h-6z"/>`
  static const hv = HtIconData([SvgPathShape('M13 2L4 14h6l-1 8 9-12h-6z')]);

  /// Netlist — `<path d="M4 6h16M4 12h16M4 18h10"/>`
  static const netlist = HtIconData([SvgPathShape('M4 6h16M4 12h16M4 18h10')]);

  /// Results — `<path d="M5 20V9M12 20V4M19 20v-7"/>`
  static const results = HtIconData([SvgPathShape('M5 20V9M12 20V4M19 20v-7')]);

  /// Diagnostics — rect + tick marks
  static const diag = HtIconData([
    SvgRectShape(7, 7, 10, 10, rx: 1),
    SvgPathShape(
        'M10 3v4M14 3v4M10 17v4M14 17v4M3 10h4M3 14h4M17 10h4M17 14h4'),
  ]);

  // ---- chrome ----

  /// Theme toggle — sun
  static const theme = HtIconData([
    SvgCircleShape(12, 12, 4.5),
    SvgPathShape('M12 2v2M12 20v2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4'
        'M2 12h2M20 12h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4'),
  ]);

  /// Refresh — the port selector's re-enumerate button
  static const refresh = HtIconData([
    SvgPathShape('M23 4v6h-6M1 20v-6h6'),
    SvgPathShape('M3.5 9a9 9 0 0114.9-3.4L23 10M1 14l4.6 4.4A9 9 0 0020.5 15'),
  ]);

  /// Document — the netbar and file-picker icon
  static const doc = HtIconData([
    SvgPathShape('M14 3H7a2 2 0 00-2 2v14a2 2 0 002 2h10a2 2 0 002-2V8z'),
    SvgPathShape('M14 3v5h5'),
  ]);

  /// Handover / gate arrows — `<path d="M4 7h11l-3-3M20 17H9l3 3"/>`
  static const transfer = HtIconData([SvgPathShape('M4 7h11l-3-3M20 17H9l3 3')]);

  /// Padlock — the HV lock overlay
  static const lock = HtIconData([
    SvgRectShape(4, 10, 16, 11, rx: 2),
    SvgPathShape('M8 10V7a4 4 0 018 0v3'),
  ]);

  /// Warning triangle — the pre-HV verification modal
  static const warning = HtIconData([
    SvgPathShape('M12 9v4M12 17h.01'
        'M10.3 3.9L1.8 18a2 2 0 001.7 3h17a2 2 0 001.7-3L13.7 3.9a2 2 0 00-3.4 0z'),
  ]);
}

class _IconPainter extends CustomPainter {
  final HtIconData icon;
  final Color color;
  final double strokeWidth;

  const _IconPainter(this.icon, this.color, this.strokeWidth);

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.shortestSide / 24.0;
    canvas.save();
    canvas.scale(scale, scale);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..color = color
      ..strokeWidth = strokeWidth
      // stroke-linecap:round;stroke-linejoin:round
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;
    for (final shape in icon.shapes) {
      canvas.drawPath(shape.toPath(), paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_IconPainter old) =>
      old.icon != icon || old.color != color || old.strokeWidth != strokeWidth;
}

/// Draws an [HtIconData] at [size] logical pixels, `fill:none` and stroked in
/// [color]. [strokeWidth] is in viewBox units, matching the CSS.
class HtIcon extends StatelessWidget {
  final HtIconData icon;
  final double size;
  final Color color;
  final double strokeWidth;

  const HtIcon(
    this.icon, {
    super.key,
    required this.size,
    required this.color,
    this.strokeWidth = 1.6,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _IconPainter(icon, color, strokeWidth),
          isComplex: false,
        ),
      );
}
