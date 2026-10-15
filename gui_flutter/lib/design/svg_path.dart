/// A small SVG path-data parser.
///
/// The design's icons are inline `<svg>` elements with hand-written path data.
/// Rather than redraw them as approximations, this parses the same `d`
/// strings into a `ui.Path`, so a Flutter icon is the identical geometry the
/// browser rasterises.
///
/// Supports the commands the design actually uses: M/m, L/l, H/h, V/v, C/c,
/// S/s, Q/q, A/a, Z/z. Unsupported commands throw rather than silently
/// drawing something else.
library;

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

class _Cursor {
  final String d;
  int i = 0;
  _Cursor(this.d);

  bool get atEnd {
    _skipSep();
    return i >= d.length;
  }

  void _skipSep() {
    while (i < d.length) {
      final ch = d.codeUnitAt(i);
      // space, tab, CR, LF, comma
      if (ch == 0x20 || ch == 0x09 || ch == 0x0d || ch == 0x0a || ch == 0x2c) {
        i++;
      } else {
        break;
      }
    }
  }

  bool _isCommand(int ch) =>
      (ch >= 0x41 && ch <= 0x5a) || (ch >= 0x61 && ch <= 0x7a);

  String? nextCommand() {
    _skipSep();
    if (i >= d.length) return null;
    final ch = d.codeUnitAt(i);
    if (_isCommand(ch)) {
      i++;
      return String.fromCharCode(ch);
    }
    return null; // implicit repeat of the previous command
  }

  double nextNumber() {
    _skipSep();
    final start = i;
    if (i < d.length && (d[i] == '-' || d[i] == '+')) i++;
    while (i < d.length) {
      final ch = d.codeUnitAt(i);
      if (ch >= 0x30 && ch <= 0x39) {
        i++;
      } else if (ch == 0x2e) {
        i++; // '.'
      } else if (ch == 0x65 || ch == 0x45) {
        i++; // exponent
        if (i < d.length && (d[i] == '-' || d[i] == '+')) i++;
      } else {
        break;
      }
    }
    if (start == i) {
      throw FormatException('expected number at $i in "$d"');
    }
    return double.parse(d.substring(start, i));
  }

  /// Arc flags may be written without separators, e.g. `a2 2 0 00-2 2`,
  /// where `00` is two flags. So read exactly one digit.
  double nextFlag() {
    _skipSep();
    if (i >= d.length) throw FormatException('expected flag at end of "$d"');
    final ch = d[i];
    if (ch != '0' && ch != '1') {
      throw FormatException('expected 0 or 1 flag at $i in "$d"');
    }
    i++;
    return ch == '1' ? 1 : 0;
  }
}

/// Emit an arc as cubic segments. `Path.addArc` cannot express the
/// x-axis rotation an SVG arc allows, so approximate with cubics — one per
/// quarter turn, which is well under a tenth of a pixel of error at icon size.
void _arcToCubics(
  Path path,
  double cx,
  double cy,
  double rx,
  double ry,
  double phi,
  double startAngle,
  double sweepAngle,
) {
  final segments = (sweepAngle.abs() / (math.pi / 2)).ceil().clamp(1, 8);
  final delta = sweepAngle / segments;
  final t = 4 / 3 * math.tan(delta / 4);
  final cosPhi = math.cos(phi);
  final sinPhi = math.sin(phi);

  Offset point(double a) {
    final x = rx * math.cos(a);
    final y = ry * math.sin(a);
    return Offset(cx + cosPhi * x - sinPhi * y, cy + sinPhi * x + cosPhi * y);
  }

  Offset deriv(double a) {
    final x = -rx * math.sin(a);
    final y = ry * math.cos(a);
    return Offset(cosPhi * x - sinPhi * y, sinPhi * x + cosPhi * y);
  }

  var a = startAngle;
  for (var i = 0; i < segments; i++) {
    final a2 = a + delta;
    final p1 = point(a);
    final p2 = point(a2);
    final d1 = deriv(a);
    final d2 = deriv(a2);
    path.cubicTo(
      p1.dx + t * d1.dx,
      p1.dy + t * d1.dy,
      p2.dx - t * d2.dx,
      p2.dy - t * d2.dy,
      p2.dx,
      p2.dy,
    );
    a = a2;
  }
}

/// Parse SVG path data into a [Path].
Path parseSvgPath(String d) {
  final path = Path();
  final c = _Cursor(d);
  var cx = 0.0, cy = 0.0; // current point
  var sx = 0.0, sy = 0.0; // subpath start
  double? lastCtrlX, lastCtrlY;
  String? cmd;
  var started = false;

  while (!c.atEnd) {
    final next = c.nextCommand();
    if (next != null) {
      cmd = next;
    } else if (cmd == null) {
      throw FormatException('path data does not start with a command: "$d"');
    } else if (cmd == 'M') {
      cmd = 'L'; // implicit repeat of M is L
    } else if (cmd == 'm') {
      cmd = 'l';
    }

    final rel = cmd == cmd.toLowerCase();
    switch (cmd.toUpperCase()) {
      case 'M':
        final x = c.nextNumber() + (rel && started ? cx : 0);
        final y = c.nextNumber() + (rel && started ? cy : 0);
        path.moveTo(x, y);
        cx = sx = x;
        cy = sy = y;
        started = true;
        lastCtrlX = lastCtrlY = null;
        break;
      case 'L':
        final x = c.nextNumber() + (rel ? cx : 0);
        final y = c.nextNumber() + (rel ? cy : 0);
        path.lineTo(x, y);
        cx = x;
        cy = y;
        lastCtrlX = lastCtrlY = null;
        break;
      case 'H':
        final x = c.nextNumber() + (rel ? cx : 0);
        path.lineTo(x, cy);
        cx = x;
        lastCtrlX = lastCtrlY = null;
        break;
      case 'V':
        final y = c.nextNumber() + (rel ? cy : 0);
        path.lineTo(cx, y);
        cy = y;
        lastCtrlX = lastCtrlY = null;
        break;
      case 'C':
        final x1 = c.nextNumber() + (rel ? cx : 0);
        final y1 = c.nextNumber() + (rel ? cy : 0);
        final x2 = c.nextNumber() + (rel ? cx : 0);
        final y2 = c.nextNumber() + (rel ? cy : 0);
        final x = c.nextNumber() + (rel ? cx : 0);
        final y = c.nextNumber() + (rel ? cy : 0);
        path.cubicTo(x1, y1, x2, y2, x, y);
        lastCtrlX = x2;
        lastCtrlY = y2;
        cx = x;
        cy = y;
        break;
      case 'S':
        final x1 = lastCtrlX == null ? cx : 2 * cx - lastCtrlX;
        final y1 = lastCtrlY == null ? cy : 2 * cy - lastCtrlY;
        final x2 = c.nextNumber() + (rel ? cx : 0);
        final y2 = c.nextNumber() + (rel ? cy : 0);
        final x = c.nextNumber() + (rel ? cx : 0);
        final y = c.nextNumber() + (rel ? cy : 0);
        path.cubicTo(x1, y1, x2, y2, x, y);
        lastCtrlX = x2;
        lastCtrlY = y2;
        cx = x;
        cy = y;
        break;
      case 'Q':
        final x1 = c.nextNumber() + (rel ? cx : 0);
        final y1 = c.nextNumber() + (rel ? cy : 0);
        final x = c.nextNumber() + (rel ? cx : 0);
        final y = c.nextNumber() + (rel ? cy : 0);
        path.quadraticBezierTo(x1, y1, x, y);
        lastCtrlX = x1;
        lastCtrlY = y1;
        cx = x;
        cy = y;
        break;
      case 'A':
        final rx = c.nextNumber();
        final ry = c.nextNumber();
        final rot = c.nextNumber();
        final large = c.nextFlag() == 1;
        final sweep = c.nextFlag() == 1;
        final x = c.nextNumber() + (rel ? cx : 0);
        final y = c.nextNumber() + (rel ? cy : 0);
        _arcSegment(path, cx, cy, rx, ry, rot, large, sweep, x, y);
        cx = x;
        cy = y;
        lastCtrlX = lastCtrlY = null;
        break;
      case 'Z':
        path.close();
        cx = sx;
        cy = sy;
        lastCtrlX = lastCtrlY = null;
        break;
      default:
        throw FormatException('unsupported path command "$cmd" in "$d"');
    }
  }
  return path;
}

/// SVG elliptical arc: convert endpoint parameterisation to centre
/// parameterisation, exactly as the SVG spec's implementation notes describe.
void _arcSegment(
  Path path,
  double x0,
  double y0,
  double rx,
  double ry,
  double rotDeg,
  bool largeArc,
  bool sweep,
  double x,
  double y,
) {
  if (x0 == x && y0 == y) return;
  if (rx == 0 || ry == 0) {
    path.lineTo(x, y);
    return;
  }
  rx = rx.abs();
  ry = ry.abs();

  final phi = rotDeg * math.pi / 180.0;
  final cosPhi = math.cos(phi);
  final sinPhi = math.sin(phi);

  final dx2 = (x0 - x) / 2.0;
  final dy2 = (y0 - y) / 2.0;
  final x1 = cosPhi * dx2 + sinPhi * dy2;
  final y1 = -sinPhi * dx2 + cosPhi * dy2;

  var rxs = rx * rx;
  var rys = ry * ry;
  final lambda = (x1 * x1) / rxs + (y1 * y1) / rys;
  if (lambda > 1) {
    final s = math.sqrt(lambda);
    rx *= s;
    ry *= s;
    rxs = rx * rx;
    rys = ry * ry;
  }

  final sign = (largeArc == sweep) ? -1.0 : 1.0;
  var numer = rxs * rys - rxs * y1 * y1 - rys * x1 * x1;
  final den = rxs * y1 * y1 + rys * x1 * x1;
  if (numer < 0) numer = 0;
  final coef = den == 0 ? 0.0 : sign * math.sqrt(numer / den);
  final cx1 = coef * (rx * y1 / ry);
  final cy1 = coef * -(ry * x1 / rx);

  final cxc = cosPhi * cx1 - sinPhi * cy1 + (x0 + x) / 2.0;
  final cyc = sinPhi * cx1 + cosPhi * cy1 + (y0 + y) / 2.0;

  double angle(double ux, double uy, double vx, double vy) {
    final dot = ux * vx + uy * vy;
    final len = math.sqrt(ux * ux + uy * uy) * math.sqrt(vx * vx + vy * vy);
    if (len == 0) return 0;
    var a = math.acos((dot / len).clamp(-1.0, 1.0));
    if (ux * vy - uy * vx < 0) a = -a;
    return a;
  }

  final ux = (x1 - cx1) / rx;
  final uy = (y1 - cy1) / ry;
  final vx = (-x1 - cx1) / rx;
  final vy = (-y1 - cy1) / ry;

  final startAngle = angle(1, 0, ux, uy);
  var sweepAngle = angle(ux, uy, vx, vy);
  if (!sweep && sweepAngle > 0) {
    sweepAngle -= 2 * math.pi;
  } else if (sweep && sweepAngle < 0) {
    sweepAngle += 2 * math.pi;
  }

  _arcToCubics(path, cxc, cyc, rx, ry, phi, startAngle, sweepAngle);
}
