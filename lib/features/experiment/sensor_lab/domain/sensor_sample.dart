import 'dart:math' as math;

/// Represents an individual 3-axis physical sensor reading with timestamp.
class SensorSample {
  const SensorSample({
    required this.x,
    required this.y,
    required this.z,
    required this.timestamp,
  });

  factory SensorSample.fromJson(Map<String, dynamic> json) {
    return SensorSample(
      x: (json['x'] as num).toDouble(),
      y: (json['y'] as num).toDouble(),
      z: (json['z'] as num).toDouble(),
      timestamp: DateTime.parse(json['timestamp'] as String),
    );
  }

  final double x;
  final double y;
  final double z;
  final DateTime timestamp;

  /// Vector magnitude: sqrt(x^2 + y^2 + z^2)
  double get magnitude => math.sqrt(x * x + y * y + z * z);

  Map<String, dynamic> toJson() => {
        'x': x,
        'y': y,
        'z': z,
        'timestamp': timestamp.toIso8601String(),
      };

  @override
  String toString() =>
      'SensorSample(x: ${x.toStringAsFixed(2)}, y: ${y.toStringAsFixed(2)}, z: ${z.toStringAsFixed(2)}, t: ${timestamp.toIso8601String()})';
}
