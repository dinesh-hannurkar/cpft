import 'dart:math';
import 'package:flutter/material.dart';

class RadarSweepPainter extends CustomPainter {
  final double sweepAngle;
  final Color color;

  RadarSweepPainter({
    required this.sweepAngle,
    this.color = const Color(0xFFB8D9ED),
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = min(size.width, size.height) / 2;

    // Subtle concentric rings - more visible than before
    final baseColor = const Color(0xFFB8D9ED);
    final ringCount = 4;
    for (int i = 1; i <= ringCount; i++) {
      final r = radius * (i / ringCount);
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..color = baseColor.withValues(alpha: 0.2 - (i - 1) * 0.03);
      canvas.drawCircle(center, r, paint);
    }

    // Crosshair grid lines
    final gridPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = baseColor.withValues(alpha: 0.12);
    canvas.drawLine(
      Offset(center.dx - radius, center.dy),
      Offset(center.dx + radius, center.dy),
      gridPaint,
    );
    canvas.drawLine(
      Offset(center.dx, center.dy - radius),
      Offset(center.dx, center.dy + radius),
      gridPaint,
    );

    // Perimeter ticks every 15 degrees
    final tickPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = baseColor.withValues(alpha: 0.15);
    for (int deg = 0; deg < 360; deg += 15) {
      final rad = deg * pi / 180.0;
      final inner = Offset(
        center.dx + (radius - 6) * cos(rad),
        center.dy + (radius - 6) * sin(rad),
      );
      final outer = Offset(
        center.dx + radius * cos(rad),
        center.dy + radius * sin(rad),
      );
      canvas.drawLine(inner, outer, tickPaint);
    }

    // Realistic sweeping sector with gradient and tip glow (seamless)
    final double sweepWidth = 0.28; // ~16 degrees, tighter beam
    final double start = sweepAngle - sweepWidth;
    final Rect circleRect = Rect.fromCircle(center: center, radius: radius);

    // Single sector path; arcTo handles wrap-around with positive sweep
    final Path sector = Path()
      ..moveTo(center.dx, center.dy)
      ..arcTo(circleRect, start, sweepWidth, false)
      ..close();

    canvas.save();
    canvas.clipPath(sector);

    // Use a sweep gradient anchored at 0..sweepWidth and rotate it
    final SweepGradient sweepGrad = SweepGradient(
      startAngle: 0.0,
      endAngle: sweepWidth,
      colors: <Color>[
        color.withValues(alpha: 0.00),
        color.withValues(alpha: 0.20),
        color.withValues(alpha: 0.50),
        Colors.white.withValues(alpha: 0.88), // leading edge
      ],
      stops: const <double>[0.0, 0.65, 0.93, 1.0],
      tileMode: TileMode.clamp,
      transform: GradientRotation(start),
    );

    final Paint sectorPaint = Paint()
      ..style = PaintingStyle.fill
      ..shader = sweepGrad.createShader(circleRect);

    canvas.drawCircle(center, radius, sectorPaint);
    canvas.restore();

    // Leading edge line with soft glow
    final Offset sweepEnd = Offset(
      center.dx + radius * cos(sweepAngle),
      center.dy + radius * sin(sweepAngle),
    );

    // Outer glow line
    final Paint glowLine = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7)
      ..color = color.withValues(alpha: 0.55)
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(center, sweepEnd, glowLine);

    // Crisp leading line
    final Paint leadLine = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..color = Colors.white.withValues(alpha: 0.92)
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(center, sweepEnd, leadLine);

    // Tip pulse removed for a cleaner sweep
  }

  @override
  bool shouldRepaint(covariant RadarSweepPainter oldDelegate) =>
      sweepAngle != oldDelegate.sweepAngle;
}
