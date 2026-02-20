import 'package:flutter/material.dart';
import 'radar_sweep_painter.dart';

class RadarView extends StatefulWidget {
  final List<Widget> deviceDots;
  final Widget center;
  final bool isPaused;

  const RadarView({
    super.key,
    required this.deviceDots,
    required this.center,
    this.isPaused = false,
  });

  @override
  State<RadarView> createState() => _RadarViewState();
}

class _RadarViewState extends State<RadarView>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
  }

  @override
  void didUpdateWidget(RadarView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPaused != oldWidget.isPaused) {
      if (widget.isPaused) {
        _controller.stop();
      } else {
        _controller.repeat();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

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
              AnimatedBuilder(
                animation: _controller,
                builder: (context, child) {
                  return CustomPaint(
                    painter: RadarSweepPainter(
                      sweepAngle: _controller.value * 6.28318530718,
                      color: const Color(0xFFB8D9ED),
                    ),
                  );
                },
              ),
              // Center device
              Center(child: widget.center),
              // Device dots above center so they are not hidden
              ...widget.deviceDots,
            ],
          );
        },
      ),
    );
  }
}
