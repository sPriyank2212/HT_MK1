/// The three `<canvas>` elements of the design, as CustomPainters.
///
/// `paintDiag`, `paintHist` and `paintSpark` in the page are direct 2D-context
/// drawing code. These are line-for-line ports: same coordinates, same widths,
/// same alpha, same draw order — including the bit where wires are sorted
/// idle → pass → fail so a fault is never painted under a passing wire.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import 'model.dart';
import 'tokens.dart';

// ---------------------------------------------------------------------------
// canvas text helper
// ---------------------------------------------------------------------------

/// `ctx.fillText` uses an alphabetic baseline; Flutter paints from the top
/// left. Measure the baseline and shift, so text lands where the page puts it.
class _CanvasText {
  final TextPainter painter;
  _CanvasText(String text, TextStyle style)
      : painter = TextPainter(
          text: TextSpan(text: text, style: style),
          textDirection: TextDirection.ltr,
        )..layout();

  double get width => painter.width;

  void paint(Canvas canvas, double x, double baselineY) {
    final baseline =
        painter.computeDistanceToActualBaseline(TextBaseline.alphabetic);
    painter.paint(canvas, Offset(x, baselineY - baseline));
  }
}

// `withOpacity` rather than `withValues`: it exists in every Flutter version
// this app might be built against, where `withValues` landed only in 3.27.
// ignore: deprecated_member_use
Color _alpha(Color c, double a) => c.withOpacity((c.opacity * a).clamp(0, 1));

// ---------------------------------------------------------------------------
// harness wiring diagram
// ---------------------------------------------------------------------------

/// Everything `paintDiag` reads out of the page's closure.
class DiagState {
  final List<Net> nets;
  final Map<String, Net> netAt;
  final bool tested;
  final bool faultF06;
  final Net? hoverNet;
  final Net? selNet;

  /// "all" | "fault" | "conn"
  final String filter;
  final String? selConn;
  final double? scanX;
  final bool reduceMotion;

  const DiagState({
    required this.nets,
    required this.netAt,
    required this.tested,
    required this.faultF06,
    this.hoverNet,
    this.selNet,
    this.filter = 'all',
    this.selConn,
    this.scanX,
    this.reduceMotion = false,
  });

  /// `function netState(n)`
  String netState(Net n) {
    if (!tested) return 'idle';
    return (n.open && faultF06) ? 'fail' : 'pass';
  }

  /// The `vis` filter inside `paintDiag`.
  List<Net> visible() {
    final out = nets.where((n) {
      if (scanX != null && pinXY(n.src).x > scanX!) return false;
      if (filter == 'fault') return netState(n) == 'fail';
      if (filter == 'conn' && selConn != null) {
        return n.src.c == selConn || n.dsts.any((d) => d.c == selConn);
      }
      return true;
    }).toList();
    const order = {'idle': 0, 'pass': 1, 'fail': 2};
    out.sort((a, b) => order[netState(a)]! - order[netState(b)]!);
    return out;
  }
}

/// `function hitNet(mx,my)` — nearest sampled point on any visible wire.
Net? hitNet(DiagState s, double mx, double my) {
  Net? best;
  var bd = 11.0;
  for (final n in s.nets) {
    if (s.filter == 'fault' && s.netState(n) != 'fail') continue;
    if (s.filter == 'conn' &&
        s.selConn != null &&
        n.src.c != s.selConn &&
        !n.dsts.any((d) => d.c == s.selConn)) {
      continue;
    }
    final segs = netSegments(n).segs;
    for (final seg in segs) {
      for (var t = 0.0; t <= 1.0; t += 1 / 18) {
        final p = bez(seg[0], seg[1], t);
        final d = math.sqrt(
            (p.x - mx) * (p.x - mx) + (p.y - my) * (p.y - my));
        if (d < bd) {
          bd = d;
          best = n;
        }
      }
    }
  }
  return best;
}

class PinHit {
  final String c;
  final int p;
  final Net? net;
  const PinHit(this.c, this.p, this.net);
}

/// `function hitPin(mx,my)`
PinHit? hitPin(DiagState s, double mx, double my) {
  for (final c in kFix.connectors) {
    for (var i = 0; i < c.pts.length; i++) {
      final p = c.pts[i];
      final d =
          math.sqrt((p.x - mx) * (p.x - mx) + (p.y - my) * (p.y - my));
      if (d < 6) return PinHit(c.id, i + 1, s.netAt['${c.id}:${i + 1}']);
    }
  }
  return null;
}

/// `function strokeBez(ctx,p0,p1)`
void _strokeBez(Path path, Offset2 p0, Offset2 p1) {
  final dx = (p1.x - p0.x) * 0.45;
  path.moveTo(p0.x, p0.y);
  path.cubicTo(p0.x + dx, p0.y, p1.x - dx, p1.y, p1.x, p1.y);
}

class DiagramPainter extends CustomPainter {
  final DiagState s;
  final HtColors c;

  const DiagramPainter(this.s, this.c);

  @override
  void paint(Canvas canvas, Size size) {
    // The page draws into a fixed 1060×440 buffer that CSS scales to width.
    canvas.save();
    canvas.scale(size.width / kCanvasW, size.height / kCanvasH);
    canvas.clipRect(Rect.fromLTWH(0, 0, kCanvasW, kCanvasH));

    canvas.drawRect(
      Rect.fromLTWH(0, 0, kCanvasW, kCanvasH),
      Paint()..color = c.sunk,
    );

    _paintConnectors(canvas);
    _paintWires(canvas);

    // cross-mode sweep marker
    if (s.scanX != null && !s.reduceMotion) {
      canvas.drawLine(
        Offset(s.scanX!, 8),
        Offset(s.scanX!, kCanvasH - 8),
        Paint()
          ..color = _alpha(c.accent, .7)
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke,
      );
    }
    canvas.restore();
  }

  void _paintConnectors(Canvas canvas) {
    for (final conn in kFix.connectors) {
      final dim = s.selConn != null && s.selConn != conn.id;
      final alpha = dim ? .35 : 1.0;

      final x = conn.x;
      final y = conn.y + kConnHeaderH;
      final w = conn.w;
      final h = conn.h - kConnHeaderH;

      // One plain rounded-rect shell for every connector, whatever its real
      // shape — a vertical pin column (model.dart's layoutConn) has nothing
      // left to draw a D-shell or a ring of pins around; kTypeName below
      // still says what the connector actually is.
      final shell = RRect.fromRectAndRadius(
        Rect.fromLTWH(x + 2, y + 3, w - 4, h - 6),
        const Radius.circular(4),
      );

      canvas.drawRRect(shell, Paint()..color = _alpha(c.panel, alpha));
      canvas.drawRRect(
        shell,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = _alpha(s.selConn == conn.id ? c.accent : c.line, alpha)
          ..strokeWidth = s.selConn == conn.id ? 2 : 1.2,
      );

      // pins — one vertical column, pin 1 at the top. The dot sits on the
      // shell's canvas-facing edge (model.dart's layoutConn); the pin
      // number is drawn in the space left over on the shell's outward edge,
      // so numbers never collide with the wires crossing the canvas middle.
      final pinLabelStyle = TextStyle(
        fontFamily: kMonoFont,
        fontFamilyFallback: kMonoFallback,
        fontSize: 8,
        color: _alpha(c.ink3, alpha),
      );
      for (var i = 0; i < conn.pts.length; i++) {
        final p = conn.pts[i];
        final n = s.netAt['${conn.id}:${i + 1}'];
        final st = n != null ? s.netState(n) : null;
        final fill = n == null
            ? c.gridEmpty
            : st == 'fail'
                ? c.fail
                : st == 'pass'
                    ? c.pass
                    : c.ink3;
        canvas.drawCircle(
            Offset(p.x, p.y), 3.1, Paint()..color = _alpha(fill, alpha));
        if (n != null && (identical(n, s.hoverNet) || identical(n, s.selNet))) {
          canvas.drawCircle(
            Offset(p.x, p.y),
            3.1,
            Paint()
              ..style = PaintingStyle.stroke
              ..color = _alpha(c.accent, alpha)
              ..strokeWidth = 1.6,
          );
        }
        final pinNum = _CanvasText('${i + 1}', pinLabelStyle);
        final numX = conn.side == 'L'
            ? p.x - 6 - pinNum.width // left of the dot, inside the shell
            : p.x + 6; // right of the dot, inside the shell
        pinNum.paint(canvas, numX, p.y + 3);
      }

      // label — ctx.font='600 11px <ui>'
      final label = '${conn.id}  ${conn.label}';
      final labelText = _CanvasText(
        label,
        TextStyle(
          fontFamily: kUiFont,
          fontFamilyFallback: kUiFallback,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: _alpha(dim ? c.ink3 : c.ink, alpha),
        ),
      );
      labelText.paint(canvas, x + 2, conn.y + 12);

      // meta — ctx.font='9px <mono>', wrapped under the id/label line since
      // the shell is narrow now (vertical layout), not to its right.
      final meta = _CanvasText(
        '${kTypeName[conn.type]} · ${conn.pins}w',
        TextStyle(
          fontFamily: kMonoFont,
          fontFamilyFallback: kMonoFallback,
          fontSize: 9,
          color: _alpha(c.ink3, alpha),
        ),
      );
      meta.paint(canvas, x + 2, conn.y + 12 + 12);
    }
  }

  void _paintWires(Canvas canvas) {
    // untested first, then pass, then fail, so faults are never hidden
    for (final n in s.visible()) {
      final st = s.netState(n);
      final hot = identical(n, s.hoverNet) || identical(n, s.selNet);
      final parts = netSegments(n);

      // GUI-22: idle wires used to draw in `gridEmpty` (a near-background
      // fill colour meant for *empty grid cells*, not stroked lines) at
      // .55 alpha - on the old compact 8-connector canvas the short
      // diagonal wires were tolerably faint, but this vertical ladder can
      // run an idle wire most of the canvas's 1060px width, at which point
      // that combination reads as no wire at all (confirmed by rendering
      // it: technically non-transparent pixels, indistinguishable from the
      // background by eye). `ink3` is the same colour untested pin dots
      // already use for exactly this "present but not yet tested" meaning,
      // so idle wires now match them instead of nearly vanishing.
      final stroke = hot
          ? c.accent
          : st == 'fail'
              ? c.fail
              : st == 'pass'
                  ? c.pass
                  : c.ink3;
      final width = hot
          ? 3.0
          : st == 'fail'
              ? 2.4
              : 1.5;
      final alpha = hot
          ? 1.0
          : (s.selNet != null || s.selConn != null)
              ? .3
              : st == 'idle'
                  ? .7
                  : .85;

      final path = Path();
      for (final seg in parts.segs) {
        _strokeBez(path, seg[0], seg[1]);
      }
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = _alpha(stroke, alpha)
          ..strokeWidth = width,
      );

      final joint = parts.joint;
      if (joint != null && parts.kind == 'Y') {
        canvas.drawCircle(
          Offset(joint.x, joint.y),
          4.5,
          Paint()
            ..color = _alpha(
                hot ? c.accent : (st == 'fail' ? c.fail : c.accent), alpha),
        );
        canvas.drawCircle(
          Offset(joint.x, joint.y),
          4.5,
          Paint()
            ..style = PaintingStyle.stroke
            ..color = _alpha(c.panel, alpha)
            ..strokeWidth = 1.4,
        );
      } else if (joint != null && parts.kind == 'I') {
        final a = bez(pinXY(n.src), pinXY(n.dsts[0]), 0.46);
        final b = bez(pinXY(n.src), pinXY(n.dsts[0]), 0.54);
        final ang = math.atan2(b.y - a.y, b.x - a.x);
        canvas.save();
        canvas.translate(joint.x, joint.y);
        canvas.rotate(ang);
        final rect = RRect.fromRectAndRadius(
          const Rect.fromLTWH(-7, -3.2, 14, 6.4),
          const Radius.circular(2),
        );
        canvas.drawRRect(
            rect, Paint()..color = _alpha(hot ? c.accent : c.ink2, alpha));
        canvas.drawRRect(
          rect,
          Paint()
            ..style = PaintingStyle.stroke
            ..color = _alpha(c.panel, alpha)
            ..strokeWidth = 1.2,
        );
        canvas.restore();
      }
    }
  }

  @override
  bool shouldRepaint(DiagramPainter old) => true;
}

// ---------------------------------------------------------------------------
// resistance histogram
// ---------------------------------------------------------------------------

class HistPainter extends CustomPainter {
  final List<Net> nets;
  final bool faultF06;
  final HtColors c;

  const HistPainter(this.nets, this.faultF06, this.c);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    const h = 150.0;
    const pad = 26.0;
    final iw = w - pad * 2;
    const ih = h - 34;
    const maxR = 5.2;

    final bins = List<int>.filled(52, 0);
    for (final n in nets) {
      if (n.open && faultF06) continue;
      bins[math.min(51, (n.r / maxR * 52).toInt())]++;
    }
    final top = bins.reduce(math.max) == 0 ? 1 : bins.reduce(math.max);
    double x(double v) => pad + v / maxR * iw;
    final bw = iw / 52;

    // limit window
    canvas.drawRect(
      Rect.fromLTWH(x(0.05), 8, x(2.0) - x(0.05), ih - 8),
      Paint()..color = c.passSoft,
    );
    final limitPaint = Paint()
      ..style = PaintingStyle.stroke
      ..color = c.pass
      ..strokeWidth = 1;
    for (final v in [0.05, 2.0]) {
      canvas.drawLine(
          Offset(x(v) + .5, 8), Offset(x(v) + .5, ih), limitPaint);
    }

    // bars
    for (var i = 0; i < bins.length; i++) {
      final v = bins[i];
      final bx = pad + i * bw;
      final r = (i + .5) / 52 * maxR;
      final hgt = (v / top) * (ih - 16);
      canvas.drawRect(
        Rect.fromLTWH(bx + .5, ih - hgt, math.max(1, bw - 1.5), hgt),
        Paint()..color = (r > 2.0 || r < 0.05) ? c.fail : c.accent,
      );
    }

    // axis
    canvas.drawLine(
      Offset(pad, ih + .5),
      Offset(w - pad, ih + .5),
      Paint()
        ..style = PaintingStyle.stroke
        ..color = c.line
        ..strokeWidth = 1,
    );

    final tickStyle = TextStyle(
      fontFamily: kMonoFont,
      fontFamilyFallback: kMonoFallback,
      fontSize: 10,
      color: c.ink3,
    );
    for (final v in [0, 1, 2, 3, 4, 5]) {
      _CanvasText('$v Ω', tickStyle)
          .paint(canvas, x(v.toDouble()) - 8, h - 6);
    }
    _CanvasText('limit window', tickStyle.copyWith(color: c.pass))
        .paint(canvas, x(0.05) + 6, 20);
  }

  @override
  bool shouldRepaint(HistPainter old) => true;
}

// ---------------------------------------------------------------------------
// first-pass-yield sparkline
// ---------------------------------------------------------------------------

class SparkPainter extends CustomPainter {
  final HtColors c;

  /// A real rolling pass-rate series (0-100), oldest first — see
  /// `AppState.history`/`_recentPassRate` in `misc_views.dart`. Used to be a
  /// fixed 24-build demo series unrelated to any real run.
  final List<double> data;
  const SparkPainter(this.c, this.data);

  @override
  void paint(Canvas canvas, Size size) {
    if (data.length < 2) return;
    final w = size.width;
    const h = 54.0;
    const pad = 6.0;
    final iw = w - pad * 2;
    const ih = h - pad * 2;
    const minV = 60.0;
    const maxV = 100.0;

    double x(int i) => pad + i / (data.length - 1) * iw;
    double y(num v) => pad + (1 - (v - minV) / (maxV - minV)) * ih;

    final grid = Paint()
      ..style = PaintingStyle.stroke
      ..color = c.lineSoft
      ..strokeWidth = 1;
    for (final g in [70, 80, 90]) {
      canvas.drawLine(Offset(pad, y(g) + .5), Offset(w - pad, y(g) + .5), grid);
    }

    // area fill, accent-soft -> transparent
    final area = Path()..moveTo(x(0), y(data[0]));
    for (var i = 0; i < data.length; i++) {
      area.lineTo(x(i), y(data[i]));
    }
    area.lineTo(x(data.length - 1), h - pad);
    area.lineTo(x(0), h - pad);
    area.close();
    canvas.drawPath(
      area,
      Paint()
        ..shader = ui.Gradient.linear(
          const Offset(0, pad),
          const Offset(0, h),
          [c.accentSoft, const Color(0x00000000)],
        ),
    );

    // line
    final line = Path();
    for (var i = 0; i < data.length; i++) {
      if (i == 0) {
        line.moveTo(x(i), y(data[i]));
      } else {
        line.lineTo(x(i), y(data[i]));
      }
    }
    canvas.drawPath(
      line,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = c.accent
        ..strokeWidth = 1.75,
    );

    final li = data.length - 1;
    canvas.drawCircle(
        Offset(x(li), y(data[li])), 3.5, Paint()..color = c.accent);
  }

  @override
  bool shouldRepaint(SparkPainter old) => old.c != c || old.data != data;
}
