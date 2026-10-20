/// Supported physical hardware sensor types for Mentora science experiments.
enum SensorType {
  accelerometer,
  userAccelerometer,
  gyroscope,
  magnetometer;

  String get displayName {
    switch (this) {
      case SensorType.accelerometer:
        return '3-Axis Accelerometer (with Gravity)';
      case SensorType.userAccelerometer:
        return 'Linear Accelerometer (without Gravity)';
      case SensorType.gyroscope:
        return '3-Axis Gyroscope';
      case SensorType.magnetometer:
        return '3-Axis Magnetometer';
    }
  }

  String get unit {
    switch (this) {
      case SensorType.accelerometer:
      case SensorType.userAccelerometer:
        return 'm/s²';
      case SensorType.gyroscope:
        return 'rad/s';
      case SensorType.magnetometer:
        return 'µT';
    }
  }
}
