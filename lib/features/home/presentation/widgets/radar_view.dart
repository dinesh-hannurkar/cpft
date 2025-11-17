import 'package:flutter/material.dart';
import 'radar_sweep_painter.dart';

class RadarView extends StatelessWidget {
  final double sweepAngle;
  final List<Widget> deviceDots;
  final Widget center;

  const RadarView({
    super.key,
    required this.sweepAngle,
    required this.deviceDots,
    required this.center,
  });

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Stack(
            fit: StackFit.expand,
            children: [
              // Very subtle background gradient circle
              Container(
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      Color(0xFFF5FBFE),
                      Color(0xFFECF7FB),
                      Color(0xFFE6F4F9),
                    ],
                    stops: [0.2, 0.6, 1.0],
                  ),
                ),
              ),
              CustomPaint(
                painter: RadarSweepPainter(
                  sweepAngle: sweepAngle,
                  color: const Color(0xFFB8D9ED),
                ),
              ),
              // Center device
              Center(child: center),
              // Device dots above center so they are not hidden
              ...deviceDots,
            ],
          );
        },
      ),
    );
  }
}
