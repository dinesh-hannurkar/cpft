/// Simple data class to track device positions for collision detection
class DevicePosition {
  final double angle;
  final double distance;
  final double size;
  
  const DevicePosition({
    required this.angle,
    required this.distance,
    required this.size,
  });
}
