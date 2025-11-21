import 'dart:math';
import 'package:cpft/features/home/helpers/device_dot_position.dart';
import 'package:cpft/features/home/helpers/device_position.dart';
import 'package:cpft/services/discovery_service.dart';

/// Helper class for calculating device dot positions on the radar
class DeviceDotLayoutHelper {
  /// Calculate position for a device dot with collision avoidance
  static DeviceDotPosition calculatePosition({
    required DeviceInfo device,
    required int index,
    required int totalDevices,
    required List<DevicePosition> usedPositions,
  }) {
    final hash = device.name.hashCode;

    // Better initial distribution: divide circle evenly, then add hash-based variation
    double baseAngle = (index * 2 * pi) / totalDevices.clamp(1, 8);
    double angleVariation =
        ((hash % 60) - 30) * pi / 180.0; // ±30 degrees variation
    double angle = baseAngle + angleVariation;

    // Keep dots outside center circle: 0.60 .. 0.85 with increased radial jitter
    double dist = 0.60 + (hash % 50) / 200.0; // 0.60..0.85 base
    final double radialJitter =
        (((hash >> 8) % 21) - 10) / 100.0; // -0.10 .. +0.10
    dist = (dist + radialJitter).clamp(0.55, 0.90);

    // Calculate actual pixel size for collision detection
    final int hashFactor = (hash.abs() % 1000);
    final double baseVar = 18.0 * hashFactor / 1000.0; // 0..18
    final double proximityBoost = (1.0 - dist).clamp(0.0, 1.0) * 6.0; // 0..6
    final double dotSize = 45.0 + baseVar + proximityBoost; // ~30..54

    // Minimum angular separation based on dot size and distance
    final double minAngularSeparation = (dotSize * 2.0) / (dist * 180);
    final double minSepRad = minAngularSeparation.clamp(
      pi / 4,
      pi / 2,
    ); // 45-90 degrees

    // Check collision against all existing positions
    bool hasCollision() {
      for (final pos in usedPositions) {
        final angleDiff = (angle - pos.angle).abs();
        final normalizedDiff = angleDiff > pi
            ? (2 * pi - angleDiff)
            : angleDiff;

        // Check if too close angularly or radially
        final radialOverlap =
            (dist - pos.distance).abs() < 0.12; // Within 12% distance
        final angularOverlap = normalizedDiff < minSepRad;

        if (radialOverlap && angularOverlap) {
          return true;
        }
      }
      return false;
    }

    // Try to find a collision-free position with smaller angle increments
    int attempts = 0;
    const int maxAttempts = 120;
    while (hasCollision() && attempts < maxAttempts) {
      angle += pi / 60; // 3 degrees - finer resolution
      if (angle > 2 * pi) angle -= 2 * pi;
      attempts++;
    }

    // If still colliding after max attempts, try radial adjustment
    if (hasCollision()) {
      // Try moving radially outward
      dist = (dist + 0.05).clamp(0.55, 0.95);
      if (!hasCollision()) {
      } else {
        // Try moving radially inward
        dist = (dist - 0.10).clamp(0.55, 0.95);
      }
    }

    return DeviceDotPosition(angle: angle, distance: dist, size: dotSize);
  }
}
