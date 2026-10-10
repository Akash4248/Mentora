// ignore_for_file: avoid_print

import 'dart:async';
import 'base_experiment_runtime.dart';
import 'runtime_event.dart';
import 'sensors/sensor_manager.dart';
import 'sensors/sensor_type.dart';

@deprecated
class SensorRuntime extends BaseExperimentRuntime {
  final SensorManager _sensorManager = SensorManager();
  StreamSubscription? _measurementSubscription;

  @deprecated
  SensorRuntime(super.plan);

  @override
  Future<void> initialize() async {
    await super.initialize();
    await _sensorManager.initialize();
    
    _measurementSubscription = _sensorManager.measurementStream.listen((measurement) {
      emitEvent(
        RuntimeEventType.measurementReceived,
        'Measurement received from ${measurement.sensorType.name}',
        metadata: {
          'sensor': measurement.sensorType.name,
          'values': measurement.values,
          'timestamp': measurement.timestamp.toIso8601String(),
        },
      );
    });
  }

  @override
  Future<void> start() async {
    await super.start();
    print('[EXPERIMENT] SENSOR_RUNTIME_STARTED');
    
    for (final sensorName in plan.requiredSensors) {
      final type = _parseSensorType(sensorName);
      if (type != null) {
        await _sensorManager.startSensor(type);
      }
    }
  }

  @override
  Future<void> stop() async {
    print('[EXPERIMENT] SENSOR_RUNTIME_STOPPED');
    for (final sensorName in plan.requiredSensors) {
      final type = _parseSensorType(sensorName);
      if (type != null) {
        await _sensorManager.stopSensor(type);
      }
    }
    await super.stop();
  }

  @override
  Future<void> dispose() async {
    await _measurementSubscription?.cancel();
    await _sensorManager.dispose();
    await super.dispose();
  }

  SensorType? _parseSensorType(String name) {
    for (final type in SensorType.values) {
      if (type.name.toLowerCase() == name.toLowerCase()) {
        return type;
      }
    }
    return null;
  }
}
