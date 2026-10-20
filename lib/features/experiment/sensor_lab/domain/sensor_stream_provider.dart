import 'dart:async';
import 'package:sensors_plus/sensors_plus.dart' as sensors_plus;

import 'sensor_sample.dart';
import 'sensor_type.dart';

/// Abstract provider interface for device sensor streams.
abstract class SensorStreamProvider {
  /// Checks whether the requested sensor hardware is supported on this platform.
  Future<bool> isSensorAvailable(SensorType type);

  /// Returns a continuous stream of sensor samples.
  Stream<SensorSample> getSensorStream(
    SensorType type, {
    Duration samplingPeriod = const Duration(milliseconds: 20),
  });
}

/// Production implementation connecting to physical hardware sensors via sensors_plus.
class DeviceSensorStreamProvider implements SensorStreamProvider {
  const DeviceSensorStreamProvider();

  @override
  Future<bool> isSensorAvailable(SensorType type) async {
    // Attempt a quick sample with a 500ms timeout to confirm hardware availability
    try {
      final stream = getSensorStream(type, samplingPeriod: const Duration(milliseconds: 100));
      await stream.first.timeout(const Duration(milliseconds: 600));
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Stream<SensorSample> getSensorStream(
    SensorType type, {
    Duration samplingPeriod = const Duration(milliseconds: 20),
  }) {
    switch (type) {
      case SensorType.accelerometer:
        return sensors_plus
            .accelerometerEventStream(samplingPeriod: samplingPeriod)
            .map((e) => SensorSample(x: e.x, y: e.y, z: e.z, timestamp: e.timestamp));
      case SensorType.userAccelerometer:
        return sensors_plus
            .userAccelerometerEventStream(samplingPeriod: samplingPeriod)
            .map((e) => SensorSample(x: e.x, y: e.y, z: e.z, timestamp: e.timestamp));
      case SensorType.gyroscope:
        return sensors_plus
            .gyroscopeEventStream(samplingPeriod: samplingPeriod)
            .map((e) => SensorSample(x: e.x, y: e.y, z: e.z, timestamp: e.timestamp));
      case SensorType.magnetometer:
        return sensors_plus
            .magnetometerEventStream(samplingPeriod: samplingPeriod)
            .map((e) => SensorSample(x: e.x, y: e.y, z: e.z, timestamp: e.timestamp));
    }
  }
}

/// Test and replay fixture implementation for deterministic signal verification.
class MockSensorStreamProvider implements SensorStreamProvider {
  MockSensorStreamProvider({
    this.availableSensors = const {SensorType.accelerometer, SensorType.userAccelerometer},
    this.streamOverride,
    this.samplesToEmit,
    this.emitInterval = const Duration(milliseconds: 20),
  });

  final Set<SensorType> availableSensors;
  final Stream<SensorSample>? streamOverride;
  final List<SensorSample>? samplesToEmit;
  final Duration emitInterval;

  @override
  Future<bool> isSensorAvailable(SensorType type) async {
    return availableSensors.contains(type);
  }

  @override
  Stream<SensorSample> getSensorStream(
    SensorType type, {
    Duration samplingPeriod = const Duration(milliseconds: 20),
  }) {
    if (!availableSensors.contains(type)) {
      return Stream.error(StateError('Sensor $type is not available on this device.'));
    }

    if (streamOverride != null) {
      return streamOverride!;
    }

    if (samplesToEmit != null) {
      return Stream.periodic(emitInterval, (count) {
        if (count < samplesToEmit!.length) {
          return samplesToEmit![count];
        }
        return samplesToEmit!.last;
      }).take(samplesToEmit!.length);
    }

    // Default static rest reading (pointing up along Z, 1G)
    return Stream.periodic(samplingPeriod, (_) => SensorSample(
          x: 0.0,
          y: 0.0,
          z: 9.8,
          timestamp: DateTime.now(),
        ));
  }
}
