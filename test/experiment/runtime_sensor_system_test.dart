import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mentora/features/experiment/runtime/graphs/line_graph_behavior.dart';
import 'package:mentora/features/experiment/runtime/runtime_loader.dart';
import 'package:mentora/features/experiment/runtime/sensors/models/runtime_sensor_type.dart';
import 'package:mentora/features/experiment/runtime/sensors/runtime_sensor_manager.dart';
import 'package:mentora/features/experiment/runtime/sensors/sensor_measurement.dart';
import 'package:mentora/features/experiment/runtime/sensors/sensor_provider.dart';
import 'package:mentora/features/experiment/runtime/sensors/sensor_registry.dart';
import 'package:mentora/features/experiment/runtime/sensors/sensor_type.dart';
import 'package:mentora/features/experiment/runtime/variable_store.dart';
import 'package:mentora/features/experiment/runtime/runtime_event_bus.dart';

void main() {
  group('runtime sensor system', () {
    test('registers sensor variables and maps providers', () {
      final eventBus = RuntimeEventBus();
      final variables = VariableStore(eventBus: eventBus)
        ..initialize([
          _variable('var_accel', 'Acceleration', 'accelerometer', const {}),
          _variable('var_temp', 'Temperature', 'numberInput', 20),
        ]);
      final registry = SensorRegistry()
        ..registerProvider(SensorType.accelerometer, _FakeSensorProvider());
      final manager = RuntimeSensorManager(
        variables: variables,
        eventBus: eventBus,
        registry: registry,
      )..initialize();

      expect(manager.registeredSensors, hasLength(1));
      expect(
        manager.registeredSensors.single.type,
        RuntimeSensorType.accelerometer,
      );
      expect(registry.hasProvider(SensorType.accelerometer), isTrue);

      manager.dispose();
      variables.dispose();
      eventBus.dispose();
    });

    test('sensor measurements update variables and analytics', () async {
      final world = RuntimeLoader.loadFromManifest(
        _manifest(
          variables: [
            _variable('var_accel', 'Acceleration', 'accelerometer', const {}),
          ],
        ),
      );
      world.sensors.registry.registerProvider(
        SensorType.accelerometer,
        _FakeSensorProvider(),
      );
      world.sensors.injectMeasurement(
        _measurement(SensorType.accelerometer, {'x': 1, 'y': 2, 'z': 2}),
      );
      await Future<void>.delayed(Duration.zero);

      expect(world.variables.getValue('var_accel'), {'x': 1, 'y': 2, 'z': 2});
      expect(world.analytics.sensorVariables, 1);
      expect(world.analytics.sensorMeasurements, 1);
      expect(world.analytics.variableUpdates, 1);

      world.dispose();
    });

    test('sensor updates are collected as measurements', () async {
      final world = RuntimeLoader.loadFromManifest(
        _manifest(
          variables: [
            _variable('var_accel', 'Acceleration', 'accelerometer', const {}),
          ],
        ),
      );
      world.sensors.injectMeasurement(
        _measurement(SensorType.accelerometer, {'x': 3, 'y': 4, 'z': 0}),
      );
      await Future<void>.delayed(Duration.zero);

      final history = world.measurementStore.getMeasurements('var_accel');
      expect(history, hasLength(1));
      expect(history.single.value, {'x': 3, 'y': 4, 'z': 0});
      expect(world.analytics.measurementsCollected, 1);

      world.dispose();
    });

    test('rules can consume a sensor component', () async {
      final events = <String>[];
      final world = RuntimeLoader.loadFromManifest(
        _manifest(
          variables: [
            _variable('var_accel', 'Acceleration', 'accelerometer', const {}),
          ],
          rules: [
            {
              'ruleId': 'rule_tilt_warning',
              'name': 'Tilt Warning',
              'trigger': 'variableChanged',
              'condition': {
                'variableId': 'var_accel',
                'field': 'x',
                'operator': '>',
                'value': 0.5,
              },
              'action': {'type': 'show_warning', 'message': 'Tilt detected'},
            },
          ],
        ),
      );
      final subscription = world.eventBus.stream.listen((event) {
        events.add(event.message);
      });

      world.sensors.injectMeasurement(
        _measurement(SensorType.accelerometer, {'x': 0.75, 'y': 0, 'z': 0}),
      );
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(events, contains('RuleFired'));
      expect(events, contains('Tilt detected'));
      expect(world.analytics.rulesFired, 1);

      await subscription.cancel();
      world.dispose();
    });

    test('line graphs can consume vector sensor measurements', () async {
      final world = RuntimeLoader.loadFromManifest(
        _manifest(
          variables: [
            _variable('var_accel', 'Acceleration', 'accelerometer', const {}),
          ],
        ),
      );
      world.sensors.injectMeasurement(
        _measurement(SensorType.accelerometer, {'x': 3, 'y': 4, 'z': 0}),
      );
      await Future<void>.delayed(Duration.zero);

      final graphState = LineGraphBehavior(
        measurementStore: world.measurementStore,
      ).buildStateForVariable('var_accel');

      expect(graphState.sampleCount, 1);
      expect(graphState.points.single.y, 5);

      world.dispose();
    });

    test('sensor lifecycle supports start pause resume and stop', () async {
      final provider = _FakeSensorProvider();
      final world = RuntimeLoader.loadFromManifest(
        _manifest(
          variables: [
            _variable('var_accel', 'Acceleration', 'accelerometer', const {}),
          ],
        ),
      );
      world.sensors.registry.registerProvider(
        SensorType.accelerometer,
        provider,
      );

      await world.sensors.start();
      await Future<void>.delayed(Duration.zero);
      expect(provider.started, isTrue);
      expect(world.sensors.activeSensorCount, 1);
      expect(world.analytics.activeSensors, 1);

      world.sensors.pause();
      provider.emit({'x': 9, 'y': 0, 'z': 0});
      await Future<void>.delayed(Duration.zero);
      expect(world.variables.getValue('var_accel'), const {});

      await world.sensors.resume();
      provider.emit({'x': 1, 'y': 0, 'z': 0});
      await Future<void>.delayed(Duration.zero);
      expect(world.variables.getValue('var_accel'), {'x': 1, 'y': 0, 'z': 0});

      await world.sensors.stop();
      await Future<void>.delayed(Duration.zero);
      expect(provider.started, isFalse);
      expect(world.sensors.activeSensorCount, 0);
      expect(world.analytics.activeSensors, 0);

      world.dispose();
    });
  });
}

Map<String, dynamic> _manifest({
  List<Map<String, dynamic>> variables = const [],
  List<Map<String, dynamic>> objects = const [],
  List<Map<String, dynamic>> rules = const [],
}) {
  return {
    'scene': {
      'sceneId': 'sensor_certification',
      'name': 'Sensor Certification',
      'variables': variables,
      'objects': objects,
      'rules': rules,
    },
  };
}

Map<String, dynamic> _variable(
  String id,
  String name,
  String type,
  dynamic value,
) {
  return {'id': id, 'name': name, 'type': type, 'value': value};
}

SensorMeasurement _measurement(SensorType type, Map<String, dynamic> values) {
  return SensorMeasurement(
    sensorType: type,
    timestamp: DateTime.now(),
    values: values,
  );
}

class _FakeSensorProvider implements SensorProvider {
  final StreamController<SensorMeasurement> _controller =
      StreamController<SensorMeasurement>.broadcast();
  bool started = false;

  @override
  Stream<SensorMeasurement> get measurementStream => _controller.stream;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> start() async {
    started = true;
  }

  @override
  Future<void> stop() async {
    started = false;
  }

  @override
  Future<void> dispose() async {
    await _controller.close();
  }

  @override
  Future<bool> isAvailable() async => true;

  void emit(Map<String, dynamic> values) {
    _controller.add(_measurement(SensorType.accelerometer, values));
  }
}
