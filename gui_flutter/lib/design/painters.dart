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
  ///
  /// A net made of netlist rows is idle until the run has reported on at
  /// least one of its pairs, then fails if any of them came back open. (The
  /// built-in demo harness has no per-pair results and keeps the old
  /// whole-run `tested` flag.)
  String netState(Net n) {
    if (n.pairs.isNotEmpty) {
      if (n.reportedPairs.isEmpty) return 'idle';
      return n.open ? 'fail' : 'pass';
    }
    if (!tested) return 'idle';
    return (n.open && faultF06) ? 'fail' : 'pass';
  }

  /// State of one wire of a net: a Y branch answers for itself, a shared trunk
  /// (leaf null) for the whole net.
  String branchState(Net n, PinRef? leaf) {
    if (leaf == null) return netState(n);
    if (n.pairs.isNotEmpty) {
      if (!n.pinReported(leaf)) return 'idle';
      return n.pinOpen(leaf) ? 'fail' : 'pass';
    }
    if (!tested) return 'idle';
    return (n.pinOpen(leaf) && faultF06) ? 'fail' : 'pass';
  }

  /// State of the wire(s) on one pin.
  String pinState(Net n, PinRef pin) => branchState(n, pin);

  bool _touches(Net n, String conn) =>
      n.srcs.any((p) => p.c == conn) || n.dsts.any((d) => d.c == conn);

  /// The `vis` filter inside `paintDiag`.
  List<Net> visible() {
    final out = nets.where((n) {
      if (scanX != null && pinXY(n.src).x > scanX!) return false;
      if (filter == 'fault') return netState(n) == 'fail';
      if (filter == 'conn' && selConn != null) return _touches(n, selConn!);
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
    if (s.filter == 'conn' && s.selConn != null && !s._touches(n, s.selConn!)) {
      continue;
    }
    for (final line in netSegments(n).segs) {
      for (var i = 1; i < line.length; i++) {
        final d = _distToSegment(mx, my, line[i - 1], line[i]);
        if (d < bd) {
          bd = d;
          best = n;
        }
      }
    }
  }
  return best;
}

double _distToSegment(double px, double py, Offset2 a, Offset2 b) {
  final dx = b.x - a.x;
  final dy = b.y - a.y;
  final len2 = dx * dx + dy * dy;
  final t = len2 == 0
      ? 0.0
      : (((px - a.x) * dx + (py - a.y) * dy) / len2).clamp(0.0, 1.0);
  final cx = a.x + dx * t;
  final cy = a.y + dy * t;
  return math.sqrt((px - cx) * (px - cx) + (py - cy) * (py - cy));
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

/// A wire as a path: straight legs with square corners.
void _strokeLine(Path path, List<Offset2> pts) {
  path.moveTo(pts.first.x, pts.first.y);
  for (var i = 1; i < pts.length; i++) {
    path.lineTo(pts[i].x, pts[i].y);
  }
}

/// Text that is shortened with an ellipsis rather than allowed to run out of
/// its box.
_CanvasText _fitText(String text, TextStyle style, double maxWidth) {
  var t = _CanvasText(text, style);
  if (t.width <= maxWidth || text.length < 2) return t;
  var n = text.length;
  while (n > 1) {
    n--;
    t = _CanvasText('${text.substring(0, n)}…', style);
    if (t.width <= maxWidth) break;
  }
  return t;
}

class DiagramPainter extends CustomPainter {
  final DiagState s;
  final HtColors c;

  const DiagramPainter(this.s, this.c);

  @override
  void paint(Canvas canvas, Size size) {
    // The page draws into a fixed 1060×N buffer that is scaled to width.
    canvas.save();
    canvas.scale(size.width / kCanvasW, size.height / kCanvasH);
    canvas.clipRect(Rect.fromLTWH(0, 0, kCanvasW, kCanvasH));

    canvas.drawRect(
      Rect.fromLTWH(0, 0, kCanvasW, kCanvasH),
      Paint()..color = c.sunk,
    );

    _paintColumnTitles(canvas);
    _paintConnectors(canvas);
    _paintWires(canvas);
    _paintPinDots(canvas); // wires end at the dot centres: dots go on top

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

  // -- column titles -------------------------------------------------------

  void _paintColumnTitles(Canvas canvas) {
    final style = TextStyle(
      fontFamily: kMonoFont,
      fontFamilyFallback: kMonoFallback,
      fontSize: 9.5,
      fontWeight: FontWeight.w600,
      letterSpacing: 1.4,
      color: c.ink3,
    );
    final hasL = kConnsL.isNotEmpty;
    final hasR = kConnsR.isNotEmpty;
    if (hasL) {
      _CanvasText('SIDE A', style).paint(canvas, 18, 17);
      canvas.drawLine(
        const Offset(16, kColTitleH),
        Offset(16 + kConnW, kColTitleH),
        Paint()
          ..color = c.line
          ..strokeWidth = 1,
      );
    }
    if (hasR) {
      final t = _CanvasText('SIDE B', style);
      t.paint(canvas, kCanvasW - 18 - t.width, 17);
      canvas.drawLine(
        Offset(kCanvasW - 16 - kConnW, kColTitleH),
        Offset(kCanvasW - 16, kColTitleH),
        Paint()
          ..color = c.line
          ..strokeWidth = 1,
      );
    }
  }

  // -- connectors -------------------------------------------------------------

  /// The outline of a connector body, by type.
  Path _shell(ConnectorDef conn, Rect r) {
    final left = conn.side == 'L'; // the outward edge is the far-left one
    final path = Path();
    switch (conn.type) {
      case ConnType.dsub:
        // the trapezoid of a D-shell: the outward corners are cut away
        const ch = 12.0;
        if (left) {
          path
            ..moveTo(r.left + ch, r.top)
            ..lineTo(r.right, r.top)
            ..lineTo(r.right, r.bottom)
            ..lineTo(r.left + ch, r.bottom)
            ..lineTo(r.left, r.bottom - ch)
            ..lineTo(r.left, r.top + ch)
            ..close();
        } else {
          path
            ..moveTo(r.left, r.top)
            ..lineTo(r.right - ch, r.top)
            ..lineTo(r.right, r.top + ch)
            ..lineTo(r.right, r.bottom - ch)
            ..lineTo(r.right - ch, r.bottom)
            ..lineTo(r.left, r.bottom)
            ..close();
        }
      case ConnType.circ:
        path.addRRect(RRect.fromRectAndRadius(
            r, Radius.circular(math.min(26, r.height / 2))));
      case ConnType.rect:
        path.addRRect(RRect.fromRectAndRadius(r, const Radius.circular(4)));
      case ConnType.term:
        path.addRRect(RRect.fromRectAndRadius(r, const Radius.circular(2)));
      case ConnType.mod:
        // a jack: the body with a latch tab standing proud of one edge
        path.addRRect(RRect.fromRectAndRadius(r, const Radius.circular(3)));
    }
    return path;
  }

  /// Detail drawn on top of the outline that says what kind of connector this
  /// is: a second ring on a circular, mounting holes on a rectangular flange,
  /// a screw head and separator per way on a terminal block, a latch on a jack.
  void _paintShellDetail(
      Canvas canvas, ConnectorDef conn, Rect r, Color line, double alpha) {
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..color = _alpha(line, alpha * .7)
      ..strokeWidth = 1;
    final left = conn.side == 'L';
    switch (conn.type) {
      case ConnType.circ:
        final inner = r.deflate(5);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
              inner, Radius.circular(math.min(21, inner.height / 2))),
          stroke,
        );
      case ConnType.rect:
        for (final dy in [r.top + 7, r.bottom - 7]) {
          final dx = left ? r.left + 7 : r.right - 7;
          canvas.drawCircle(Offset(dx, dy), 2.4, stroke);
        }
      case ConnType.term:
        // one screw head per way on the outward edge, a separator between ways
        for (var i = 0; i < conn.pts.length; i++) {
          final p = conn.pts[i];
          final sx = left ? r.left + 8 : r.right - 14;
          canvas.drawRect(Rect.fromLTWH(sx, p.y - 3.5, 6, 7), stroke);
          if (i > 0) {
            final y = (conn.pts[i - 1].y + p.y) / 2;
            canvas.drawLine(
                Offset(r.left + 2, y),
                Offset(r.right - 2, y),
                Paint()
                  ..color = _alpha(line, alpha * .35)
                  ..strokeWidth = .6);
          }
        }
      case ConnType.mod:
        final tabX = left ? r.left - 5 : r.right;
        canvas.drawRect(
            Rect.fromLTWH(tabX, r.top + r.height / 2 - 9, 5, 18), stroke);
      case ConnType.dsub:
        break;
    }
  }

  /// The small outline in a connector's header that shows its kind at a
  /// glance — D-sub trapezoid with two staggered rows, circular with a ring of
  /// contacts, rectangular with a grid, terminal block with screws, modular
  /// jack with a latch and a row of contacts.
  void _paintPictogram(
      Canvas canvas, ConnType type, Rect r, Color col, double alpha) {
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..color = _alpha(col, alpha)
      ..strokeWidth = 1.2;
    final fill = Paint()..color = _alpha(col, alpha);
    switch (type) {
      case ConnType.dsub:
        canvas.drawPath(
          Path()
            ..moveTo(r.left, r.top)
            ..lineTo(r.right, r.top)
            ..lineTo(r.right - 4, r.bottom)
            ..lineTo(r.left + 4, r.bottom)
            ..close(),
          stroke,
        );
        for (var i = 0; i < 5; i++) {
          canvas.drawCircle(Offset(r.left + 5 + i * 5, r.top + 6), 1.2, fill);
        }
        for (var i = 0; i < 4; i++) {
          canvas.drawCircle(
              Offset(r.left + 7.5 + i * 5, r.top + 13), 1.2, fill);
        }
      case ConnType.circ:
        final ctr = r.center;
        final rad = math.min(r.width, r.height) / 2;
        canvas.drawCircle(ctr, rad, stroke);
        for (var i = 0; i < 6; i++) {
          final a = i * math.pi / 3;
          canvas.drawCircle(
              Offset(ctr.dx + math.cos(a) * rad * .58,
                  ctr.dy + math.sin(a) * rad * .58),
              1.2,
              fill);
        }
        canvas.drawCircle(ctr, 1.2, fill);
      case ConnType.rect:
        canvas.drawRRect(
            RRect.fromRectAndRadius(r, const Radius.circular(3)), stroke);
        for (var row = 0; row < 2; row++) {
          for (var i = 0; i < 4; i++) {
            canvas.drawCircle(
                Offset(
                    r.left + 5 + i * (r.width - 10) / 3, r.top + 6 + row * 8),
                1.2,
                fill);
          }
        }
      case ConnType.term:
        for (var i = 0; i < 3; i++) {
          final x = r.left + 1 + i * (r.width - 2) / 3;
          final cell =
              Rect.fromLTWH(x, r.top + 2, (r.width - 2) / 3 - 2, r.height - 4);
          canvas.drawRect(cell, stroke);
          canvas.drawCircle(cell.center, 2.2, stroke);
          canvas.drawLine(Offset(cell.center.dx - 1.6, cell.center.dy),
              Offset(cell.center.dx + 1.6, cell.center.dy), stroke);
        }
      case ConnType.mod:
        canvas.drawRect(
            Rect.fromLTRB(r.left + 2, r.top + 4, r.right - 2, r.bottom),
            stroke);
        canvas.drawRect(
            Rect.fromLTWH(r.center.dx - 4, r.top, 8, 4), stroke); // latch
        for (var i = 0; i < 6; i++) {
          final x = r.left + 5 + i * (r.width - 10) / 5;
          canvas.drawLine(
              Offset(x, r.bottom - 6), Offset(x, r.bottom - 2), stroke);
        }
    }
  }

  void _paintConnectors(Canvas canvas) {
    for (final conn in kFix.connectors) {
      final dim = s.selConn != null && s.selConn != conn.id;
      final alpha = dim ? .35 : 1.0;
      final isSel = s.selConn == conn.id;
      final left = conn.side == 'L';

      final x = conn.x;
      final y = conn.y + kConnHeaderH;
      final w = conn.w;
      final h = conn.h - kConnHeaderH;

      // body
      final body = Rect.fromLTWH(x + 2, y + 3, w - 4, h - 6);
      final shell = _shell(conn, body);
      canvas.drawPath(shell, Paint()..color = _alpha(c.panel, alpha));
      canvas.drawPath(
        shell,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = _alpha(isSel ? c.accent : c.line, alpha)
          ..strokeWidth = isSel ? 2 : 1.2,
      );
      _paintShellDetail(canvas, conn, body, c.line, alpha);

      // pins — one vertical column, pin 1 at the top. The dot sits on the
      // wire-facing edge; the number sits beside it and the signal label
      // outboard of the number.
      final numStyle = TextStyle(
        fontFamily: kMonoFont,
        fontFamilyFallback: kMonoFallback,
        fontSize: 8,
        color: _alpha(c.ink3, alpha),
      );
      for (var i = 0; i < conn.pts.length; i++) {
        final p = conn.pts[i];
        final n = s.netAt['${conn.id}:${i + 1}'];
        final st = n != null ? s.pinState(n, PinRef(conn.id, i + 1)) : null;
        final fill = n == null
            ? c.gridEmpty
            : st == 'fail'
                ? c.fail
                : st == 'pass'
                    ? c.pass
                    : c.ink3;
        final dot = Paint()..color = _alpha(fill, alpha);
        if (conn.type == ConnType.term) {
          canvas.drawRect(
              Rect.fromCenter(center: Offset(p.x, p.y), width: 6, height: 6),
              dot);
        } else {
          canvas.drawCircle(Offset(p.x, p.y), 3.1, dot);
        }
        if (n != null && (identical(n, s.hoverNet) || identical(n, s.selNet))) {
          canvas.drawCircle(
            Offset(p.x, p.y),
            4.6,
            Paint()
              ..style = PaintingStyle.stroke
              ..color = _alpha(c.accent, alpha)
              ..strokeWidth = 1.6,
          );
        }
        final pinNum = _CanvasText('${i + 1}', numStyle);
        final numX = left ? p.x - 7 - pinNum.width : p.x + 7;
        pinNum.paint(canvas, numX, p.y + 3);

        final lab = conn.pinLabels[i + 1];
        if (lab != null) {
          final room = (left
                  ? (numX - 6) - (body.left + 14)
                  : (body.right - 8) - (numX + pinNum.width + 6))
              .clamp(0.0, 200.0);
          final t = _fitText(
            lab,
            TextStyle(
              fontFamily: kMonoFont,
              fontFamilyFallback: kMonoFallback,
              fontSize: 8.5,
              color: _alpha(st == 'fail' ? c.fail : c.ink2, alpha),
            ),
            room,
          );
          final lx = left ? numX - 6 - t.width : numX + pinNum.width + 6;
          t.paint(canvas, lx, p.y + 3);
        }
      }

      // header: pictogram, designator, part number, type and way count
      _paintPictogram(
        canvas,
        conn.type,
        Rect.fromLTWH(x + 6, conn.y + 8, 30, 22),
        isSel ? c.accent : c.ink3,
        alpha,
      );
      final textX = x + 44;
      final room = w - 44 - 4;
      final nameStyle = TextStyle(
        fontFamily: kUiFont,
        fontFamilyFallback: kUiFallback,
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: _alpha(dim ? c.ink3 : c.ink, alpha),
      );
      final monoSmall = TextStyle(
        fontFamily: kMonoFont,
        fontFamilyFallback: kMonoFallback,
        fontSize: 9,
        color: _alpha(c.ink3, alpha),
      );
      _fitText(conn.name, nameStyle, room).paint(canvas, textX, conn.y + 17);
      final hasPart = conn.label.isNotEmpty && conn.label != conn.name;
      if (hasPart) {
        _fitText(conn.label, monoSmall, room).paint(canvas, textX, conn.y + 30);
      }
      _fitText('${kTypeName[conn.type]} · ${conn.pins} pins', monoSmall, room)
          .paint(canvas, textX, conn.y + (hasPart ? 42 : 30));
    }
  }

  /// The pin dots, again, over the wires — a wire's outline otherwise cuts
  /// through the dot it ends on.
  void _paintPinDots(Canvas canvas) {
    for (final conn in kFix.connectors) {
      final alpha = s.selConn != null && s.selConn != conn.id ? .35 : 1.0;
      for (var i = 0; i < conn.pts.length; i++) {
        final p = conn.pts[i];
        final n = s.netAt['${conn.id}:${i + 1}'];
        if (n == null) continue;
        final st = s.pinState(n, PinRef(conn.id, i + 1));
        final fill = st == 'fail'
            ? c.fail
            : st == 'pass'
                ? c.pass
                : c.ink3;
        final dot = Paint()..color = _alpha(fill, alpha);
        if (conn.type == ConnType.term) {
          canvas.drawRect(
              Rect.fromCenter(center: Offset(p.x, p.y), width: 6, height: 6),
              dot);
        } else {
          canvas.drawCircle(Offset(p.x, p.y), 3.4, dot);
        }
        canvas.drawCircle(
          Offset(p.x, p.y),
          3.4,
          Paint()
            ..style = PaintingStyle.stroke
            ..color = _alpha(c.sunk, alpha)
            ..strokeWidth = 1,
        );
        if (identical(n, s.hoverNet) || identical(n, s.selNet)) {
          canvas.drawCircle(
            Offset(p.x, p.y),
            4.8,
            Paint()
              ..style = PaintingStyle.stroke
              ..color = _alpha(c.accent, alpha)
              ..strokeWidth = 1.6,
          );
        }
      }
    }
  }

  // -- wires --------------------------------------------------------------------

  Color _wireColor(String st, bool hot) => hot
      ? c.accent
      : st == 'fail'
          ? c.fail
          : st == 'pass'
              ? c.pass
              : c.ink3;

  void _paintWires(Canvas canvas) {
    // untested first, then pass, then fail, so faults are never hidden
    for (final n in s.visible()) {
      final st = s.netState(n);
      final hot = identical(n, s.hoverNet) || identical(n, s.selNet);
      final parts = netSegments(n);

      // GUI-22: idle wires draw in `ink3`, the same colour an untested pin dot
      // uses for exactly this "present but not yet tested" meaning.
      final width = hot
          ? 2.6
          : st == 'fail'
              ? 2.0
              : 1.4;
      final alpha = hot
          ? 1.0
          : (s.selNet != null || s.selConn != null)
              ? .3
              : st == 'idle'
                  ? .8
                  : .95;

      // failed branches last, so a fault is never painted under a good wire
      final order = List<int>.generate(parts.segs.length, (i) => i)
        ..sort((a, b) {
          int rank(int i) {
            final leaf = i < parts.leaves.length ? parts.leaves[i] : null;
            return s.branchState(n, leaf) == 'fail' ? 1 : 0;
          }

          return rank(a) - rank(b);
        });
      for (final i in order) {
        final leaf = i < parts.leaves.length ? parts.leaves[i] : null;
        final bst = s.branchState(n, leaf);
        final path = Path();
        _strokeLine(path, parts.segs[i]);
        // A dark outline under the coloured core keeps neighbouring wires and
        // crossings distinguishable where lanes sit close together.
        canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeJoin = StrokeJoin.round
            ..color = _alpha(c.sunk, alpha)
            ..strokeWidth = width + 2.4,
        );
        canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeJoin = StrokeJoin.round
            ..color = _alpha(_wireColor(bst, hot), alpha)
            ..strokeWidth = width,
        );
      }

      final joint = parts.joint;
      final kind = parts.kind;
      for (final j in parts.junctions) {
        canvas.drawCircle(Offset(j.x, j.y), 2.4,
            Paint()..color = _alpha(hot ? c.accent : c.ink2, alpha));
      }
      if (joint != null && kind == 'Y') {
        final col = hot ? c.accent : (st == 'fail' ? c.fail : c.accent);
        canvas.drawCircle(
            Offset(joint.x, joint.y), 4.8, Paint()..color = _alpha(col, alpha));
        canvas.drawCircle(
          Offset(joint.x, joint.y),
          4.8,
          Paint()
            ..style = PaintingStyle.stroke
            ..color = _alpha(c.panel, alpha)
            ..strokeWidth = 1.4,
        );
        // "1:3" - how many wires leave the joint. Only for the wire under the
        // cursor / selected: with many spines side by side the labels sit on
        // top of one another and on the wires.
        final fan = n.srcs.length == 1 ? n.dsts.length : n.srcs.length;
        final mirrored = n.srcs.length > 1;
        if (hot) {
          final t = _CanvasText(
            mirrored ? '$fan:1' : '1:$fan',
            TextStyle(
              fontFamily: kMonoFont,
              fontFamilyFallback: kMonoFallback,
              fontSize: 8.5,
              fontWeight: FontWeight.w600,
              color: _alpha(c.ink2, alpha),
            ),
          );
          final lx = joint.x + (mirrored ? 7 : -7 - t.width);
          _plate(canvas, lx - 2, joint.y - 15, t.width + 4, 12);
          t.paint(canvas, lx, joint.y - 6);
        }
      } else if (joint != null && kind == 'M') {
        final col = hot ? c.accent : (st == 'fail' ? c.fail : c.accent);
        canvas.save();
        canvas.translate(joint.x, joint.y);
        canvas.rotate(math.pi / 4);
        final r = RRect.fromRectAndRadius(
            const Rect.fromLTWH(-4.6, -4.6, 9.2, 9.2),
            const Radius.circular(1.5));
        canvas.drawRRect(r, Paint()..color = _alpha(col, alpha));
        canvas.drawRRect(
            r,
            Paint()
              ..style = PaintingStyle.stroke
              ..color = _alpha(c.panel, alpha)
              ..strokeWidth = 1.3);
        canvas.restore();
        if (hot) {
          final tag = _CanvasText(
            '${n.srcs.length}×${n.dsts.length}',
            TextStyle(
              fontFamily: kMonoFont,
              fontFamilyFallback: kMonoFallback,
              fontSize: 8.5,
              fontWeight: FontWeight.w600,
              color: _alpha(c.ink2, alpha),
            ),
          );
          _plate(canvas, joint.x + 6, joint.y - 6, tag.width + 4, 12);
          tag.paint(canvas, joint.x + 8, joint.y + 3);
        }
      } else if (joint != null && kind == 'I') {
        canvas.save();
        canvas.translate(joint.x, joint.y);
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

      if (hot) _paintNetLabel(canvas, n, parts);
    }
  }

  /// A small opaque backing so a label stays legible over nearby wires.
  void _plate(Canvas canvas, double x, double y, double w, double h) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, w, h), const Radius.circular(2)),
      Paint()..color = _alpha(c.sunk, .92),
    );
  }

  /// The net's name, on a small plate at its joint (or the middle of a plain
  /// wire) — only for the wire under the cursor / selected, so the diagram
  /// stays calm otherwise.
  void _paintNetLabel(Canvas canvas, Net n, NetSegments parts) {
    final at = parts.joint ?? polyMid(parts.segs.first);
    final t = _CanvasText(
      n.name,
      TextStyle(
        fontFamily: kMonoFont,
        fontFamilyFallback: kMonoFallback,
        fontSize: 10,
        fontWeight: FontWeight.w600,
        color: c.ink,
      ),
    );
    final w = t.width + 12;
    final x =
        (at.x - w / 2).clamp(kFixLabelMargin, kCanvasW - w - kFixLabelMargin);
    final y = at.y - 24;
    final plate = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, w, 17), const Radius.circular(4));
    canvas.drawRRect(plate, Paint()..color = c.panel);
    canvas.drawRRect(
      plate,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = c.accent
        ..strokeWidth = 1.2,
    );
    t.paint(canvas, x + 6, y + 12.5);
  }

  @override
  bool shouldRepaint(DiagramPainter old) => true;
}

/// Keeps a net-name plate off the very edge of the canvas.
const double kFixLabelMargin = 4;

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
