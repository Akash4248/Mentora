import 'package:flutter_test/flutter_test.dart';
import 'package:mentora/features/experiment/runtime/runtime_loader.dart';

void main() {
  group('Runtime measurement system', () {
    test('variable update creates a measurement', () async {
      final world = RuntimeLoader.loadFromManifest(
        _manifest(
          variables: [
            _variable('var_temperature', 'Temperature', 'numberInput', 20),
          ],
        ),
      );

      world.variables.updateVariable('var_temperature', 30, source: 'test');
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final history = world.measurementStore.getMeasurements('var_temperature');
      expect(history, hasLength(1));
      expect(history.single.variableName, 'Temperature');
      expect(history.single.value, 30);
      expect(world.analytics.measurementsCollected, 1);
      expect(world.analytics.measurementVariablesTracked, 1);

      world.dispose();
    });

    test('history limit is enforced', () async {
      final world = RuntimeLoader.loadFromManifest(
        _manifest(
          variables: [
            _variable('var_temperature', 'Temperature', 'numberInput', 0, {
              'measurementPolicy': 'everyUpdate',
            }),
          ],
        ),
      );

      for (var i = 1; i <= 505; i++) {
        world.variables.updateVariable('var_temperature', i, source: 'test');
      }
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final history = world.measurementStore.getMeasurements('var_temperature');
      expect(history, hasLength(500));
      expect(history.first.value, 6);
      expect(history.last.value, 505);
      expect(world.analytics.measurementsDiscarded, 5);

      world.dispose();
    });

    test('onChange policy stores only changed values', () async {
      final world = RuntimeLoader.loadFromManifest(
        _manifest(
          variables: [
            _variable('var_temperature', 'Temperature', 'numberInput', 20),
          ],
        ),
      );

      world.variables.updateVariable('var_temperature', 25, source: 'test');
      world.variables.updateVariable('var_temperature', 25, source: 'test');
      world.variables.updateVariable('var_temperature', 26, source: 'test');
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final history = world.measurementStore.getMeasurements('var_temperature');
      expect(history.map((sample) => sample.value), [25, 26]);

      world.dispose();
    });

    test(
      'clear history removes stored measurements and emits analytics-safe event',
      () async {
        final world = RuntimeLoader.loadFromManifest(
          _manifest(
            variables: [
              _variable('var_temperature', 'Temperature', 'numberInput', 20),
            ],
          ),
        );

        world.variables.updateVariable('var_temperature', 30, source: 'test');
        await Future<void>.delayed(Duration.zero);
        world.measurementCollector.clearMeasurements('var_temperature');
        await Future<void>.delayed(Duration.zero);

        expect(
          world.measurementStore.getMeasurements('var_temperature'),
          isEmpty,
        );

        world.dispose();
      },
    );

    test('computed variable measurements are collected', () async {
      final world = RuntimeLoader.loadFromManifest(
        _manifest(
          variables: [
            _variable('var_mass', 'Mass', 'numberInput', 2),
            _variable('var_accel', 'Acceleration', 'numberInput', 5),
            _variable('var_force', 'Force', 'force', 0, {
              'massVariable': 'var_mass',
              'accelerationVariable': 'var_accel',
            }),
          ],
        ),
      );

      world.variables.updateVariable('var_mass', 4, source: 'test');
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final forceHistory = world.measurementStore.getMeasurements('var_force');
      expect(forceHistory, isNotEmpty);
      expect(forceHistory.last.value, 20);

      world.dispose();
    });

    test('timer variable history grows continuously', () async {
      final world = RuntimeLoader.loadFromManifest(
        _manifest(
          variables: [_variable('var_time', 'Elapsed Time', 'elapsedTime', 0)],
        ),
      );

      world.clock.start();
      world.tick(1);
      world.tick(1);
      world.tick(1);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final history = world.measurementStore.getMeasurements('var_time');
      expect(history.map((sample) => sample.value), [1.0, 2.0, 3.0]);

      world.dispose();
    });
  });
}

Map<String, dynamic> _manifest({
  required List<Map<String, dynamic>> variables,
}) {
  return {
    'metadata': {'title': 'Measurement Runtime Test'},
    'scene': {'variables': variables, 'objects': [], 'rules': []},
  };
}

Map<String, dynamic> _variable(
  String id,
  String name,
  String type,
  dynamic value, [
  Map<String, dynamic>? metadata,
]) {
  return {
    'id': id,
    'name': name,
    'type': type,
    'value': value,
    if (metadata != null) ...metadata,
  };
}
