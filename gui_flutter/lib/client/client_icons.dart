/// Painted icons. The client app never relies on a font having a glyph for
/// play, stop, a dropdown arrow, a tick, a cross or a warning sign: a machine
/// without the right fallback font would show an empty box on a START button
/// or in front of a high-voltage warning, so these are drawn.
library;

import 'package:flutter/material.dart';

enum IconKind { play, stop, arrowDown, check, cross, warn, bolt }

class ClientIcon extends StatelessWidget {
  final IconKind kind;
  final Color color;
  final double size;
  const ClientIcon(this.kind, {super.key, required this.color, this.size = 14});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: _IconPainter(kind, color)),
      );
}

class _IconPainter extends CustomPainter {
  final IconKind kind;
  final Color color;
  _IconPainter(this.kind, this.color);

  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width, h = s.height;
    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.16
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;
    switch (kind) {
      case IconKind.play:
        canvas.drawPath(
            Path()
              ..moveTo(w * .22, h * .10)
              ..lineTo(w * .90, h * .50)
              ..lineTo(w * .22, h * .90)
              ..close(),
            fill);
      case IconKind.stop:
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromLTWH(w * .15, h * .15, w * .70, h * .70),
                Radius.circular(w * .08)),
            fill);
      case IconKind.arrowDown:
        canvas.drawPath(
            Path()
              ..moveTo(w * .15, h * .35)
              ..lineTo(w * .85, h * .35)
              ..lineTo(w * .50, h * .75)
              ..close(),
            fill);
      case IconKind.check:
        canvas.drawPath(
            Path()
              ..moveTo(w * .15, h * .55)
              ..lineTo(w * .40, h * .78)
              ..lineTo(w * .85, h * .25),
            stroke);
      case IconKind.cross:
        canvas.drawLine(Offset(w * .22, h * .22), Offset(w * .78, h * .78), stroke);
        canvas.drawLine(Offset(w * .78, h * .22), Offset(w * .22, h * .78), stroke);
      case IconKind.warn:
        canvas.drawPath(
            Path()
              ..moveTo(w * .50, h * .08)
              ..lineTo(w * .96, h * .88)
              ..lineTo(w * .04, h * .88)
              ..close(),
            stroke..strokeWidth = w * 0.11);
        canvas.drawLine(Offset(w * .50, h * .36), Offset(w * .50, h * .62),
            stroke..strokeWidth = w * 0.13);
        canvas.drawCircle(Offset(w * .50, h * .76), w * .05, fill);
      case IconKind.bolt:
        canvas.drawPath(
            Path()
              ..moveTo(w * .58, h * .04)
              ..lineTo(w * .18, h * .56)
              ..lineTo(w * .46, h * .56)
              ..lineTo(w * .38, h * .96)
              ..lineTo(w * .82, h * .40)
              ..lineTo(w * .54, h * .40)
              ..close(),
            fill);
    }
  }

  @override
  bool shouldRepaint(_IconPainter old) => old.kind != kind || old.color != color;
}
