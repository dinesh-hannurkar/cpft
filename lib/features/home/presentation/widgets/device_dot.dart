import 'dart:math';
import 'package:cpft/core/constants/app_colors.dart';
import 'package:flutter/material.dart';

class DeviceDot extends StatefulWidget {
  final String label;
  final double angle;
  final double distanceFactor; // 0..1 relative to radius
  final VoidCallback? onTap; // New: tap handler

  const DeviceDot({
    super.key,
    required this.label,
    required this.angle,
    required this.distanceFactor,
    this.onTap,
  });

  @override
  State<DeviceDot> createState() => _DeviceDotState();
}

class _DeviceDotState extends State<DeviceDot> with TickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(
      begin: 0.1,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.bounceOut,
    ));
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final radius = min(constraints.maxWidth, constraints.maxHeight) / 2;
        final r = radius * widget.distanceFactor;
        final x = radius + r * cos(widget.angle);
        final y = radius + r * sin(widget.angle);

  // Sizing
  final int hash = widget.label.hashCode & 0x7fffffff;
  // Wider variability: base 30..48 from hash + 0..6 proximity boost => ~30..54
  final double hashFactor = (hash % 1000) / 1000.0; // 0..1
  final double baseVar = 18.0 * hashFactor; // 0..18
  final double proximityBoost = (1.0 - widget.distanceFactor).clamp(0.0, 1.0) * 6.0; // 0..6
  final double dotSize = 45.0 + baseVar + proximityBoost; // ~30..54
  const double spacing = 4.0; // space between dot and label
        const double labelWidth = 60.0; // allow up to ~5–7 chars per line
        const double labelHeightEstimate = 24.0; // ~ two lines at 10px height:1.2

        // Determine label placement (prefer side if horizontal offset is larger than vertical)
        final dx = cos(widget.angle);
        final dy = sin(widget.angle);
        final bool horizontal = dx.abs() > dy.abs();

        final double leftDot = x - dotSize / 2;
        final double topDot = y - dotSize / 2;

        double labelLeft = leftDot;
        double labelTop = topDot + dotSize; // default below
        TextAlign align = TextAlign.center;

        if (horizontal) {
          // Position label to the left or right of the dot
          if (dx > 0) {
            // Right side
            labelLeft = leftDot + dotSize + spacing;
            labelTop = y - labelHeightEstimate / 2; // vertically center
            align = TextAlign.left;
          } else {
            // Left side
            labelLeft = leftDot - labelWidth - spacing;
            labelTop = y - labelHeightEstimate / 2;
            align = TextAlign.right;
          }
          // Check if label fits on preferred side, otherwise flip
          if (dx > 0 && labelLeft + labelWidth > constraints.maxWidth) {
            // Flip to left
            labelLeft = leftDot - labelWidth - spacing;
            align = TextAlign.right;
          } else if (dx < 0 && labelLeft < 0) {
            // Flip to right
            labelLeft = leftDot + dotSize + spacing;
            align = TextAlign.left;
          }
        } else {
          // Position label above or below the dot
          if (dy > 0) {
            // Below
            labelTop = y + dotSize / 2 + spacing;
            labelLeft = x - labelWidth / 2;
            align = TextAlign.center;
          } else {
            // Above
            labelTop = y - dotSize / 2 - spacing - labelHeightEstimate;
            labelLeft = x - labelWidth / 2;
            align = TextAlign.center;
          }
        }

  // Clamp label within bounds so it doesn't overflow outside the radar
  double clampedLabelLeft = labelLeft.clamp(0.0, constraints.maxWidth - labelWidth);
  double clampedLabelTop = labelTop.clamp(0.0, constraints.maxHeight - labelHeightEstimate);

  return Stack(
          children: [
              Positioned(
                left: leftDot,
                top: topDot,
                child: ScaleTransition(
                  scale: _scaleAnimation,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: widget.onTap,
                    child: Container(
                width: dotSize,
                height: dotSize,
                decoration: BoxDecoration(
                  color: AppColors.white,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppColors.secondary,
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.blackDark.withValues(alpha: 0.15),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                alignment: Alignment.center,
                child: Text(
                  widget.label.isNotEmpty ? widget.label[0].toUpperCase() : '?',
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    color: AppColors.greyDark,
        fontSize: (dotSize * 0.36).clamp(11.0, 18.0),
                  ),
                ),
              ),
                  ),
                ),
              ),
            Positioned(
              left: clampedLabelLeft,
              top: clampedLabelTop,
              width: labelWidth,
              child: IgnorePointer(
                child: Text(
                  widget.label,
                  textAlign: align,
                  maxLines: 2,
                  softWrap: true,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10,
                    height: 1.2,
                    color: AppColors.greyDark,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}