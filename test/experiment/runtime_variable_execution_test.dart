import 'package:flutter_test/flutter_test.dart';
import 'package:mentora/features/experiment/runtime/runtime_loader.dart';

void main() {
  group('Runtime variable execution system', () {
    test('elapsed timer increments during runtime ticks', () async {
      final world = RuntimeLoader.loadFromManifest(
        _manifest(
          variables: [_variable('var_time', 'Elapsed Time', 'elapsedTime', 0)],
        ),
      );

      world.clock.start();
      world.tick(1.5);
      world.tick(0.5);
      await Future<void>.delayed(Duration.zero);

      expect(world.variables.getValue('var_time'), 2.0);
      expect(world.analytics.timerTicks, 2);

      world.dispose();
    });

    test('countdown reaches zero and emits CountdownFinished', () async {
      final world = RuntimeLoader.loadFromManifest(
        _manifest(
          variables: [_variable('var_countdown', 'Countdown', 'countdown', 2)],
        ),
      );
      final messages = <String>[];
      final subscription = world.eventBus.stream.listen((event) {
        messages.add(event.message);
      });

      world.clock.start();
      world.tick(1);
      world.tick(1);
      world.tick(1);
      await Future<void>.delayed(Duration.zero);

      expect(world.variables.getValue('var_countdown'), 0);
      expect(messages, contains('CountdownFinished'));
      expect(world.analytics.countdownsFinished, 1);

      await subscription.cancel();
      world.dispose();
    });

    test('interval fires on configured cadence', () async {
      final world = RuntimeLoader.loadFromManifest(
        _manifest(
          variables: [
            _variable('var_interval', 'Sampler', 'interval', 0, {
              'interval': 2,
            }),
          ],
        ),
      );
      final messages = <String>[];
      final subscription = world.eventBus.stream.listen((event) {
        messages.add(event.message);
      });

      world.clock.start();
      world.tick(1);
      world.tick(1);
      world.tick(2);
      await Future<void>.delayed(Duration.zero);

      expect(world.variables.getValue('var_interval'), 2);
      expect(
        messages.where((message) => message == 'IntervalTriggered'),
        hasLength(2),
      );
      expect(world.analytics.intervalEvents, 2);

      await subscription.cancel();
      world.dispose();
    });

    test('average computes from dependencies', () {
      final world = RuntimeLoader.loadFromManifest(
        _manifest(
          variables: [
            _variable('var_a', 'A', 'numberInput', 10),
            _variable('var_b', 'B', 'numberInput', 20),
            _variable('var_c', 'C', 'numberInput', 40),
            _variable('var_avg', 'Average', 'average', 0, {
              'dependencies': ['var_a', 'var_b', 'var_c'],
            }),
          ],
        ),
      );

      expect(world.variables.getValue('var_avg'), closeTo(23.333, 0.001));

      world.dispose();
    });

    test('distance updates from speed and elapsed time dependencies', () async {
      final world = RuntimeLoader.loadFromManifest(
        _manifest(
          variables: [
            _variable('var_speed', 'Speed', 'numberInput', 3),
            _variable('var_time', 'Time', 'elapsedTime', 0),
            _variable('var_distance', 'Distance', 'distance', 0, {
              'speedVariable': 'var_speed',
              'timeVariable': 'var_time',
            }),
          ],
          objects: [
            _object(
              'obj_distance',
              'numericDisplay',
              {'valueVariable': 'var_distance'},
              {'value': 0, 'unit': 'm'},
            ),
          ],
        ),
      );

      world.clock.start();
      world.tick(4);
      await Future<void>.delayed(Duration.zero);

      expect(world.variables.getValue('var_distance'), 12);
      expect(world.objects.getObjectState('obj_distance')?.state['value'], 12);

      world.dispose();
    });

    test('force updates from mass and acceleration dependencies', () async {
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

      expect(world.variables.getValue('var_force'), 10);

      world.variables.updateVariable('var_mass', 4, source: 'test');
      await Future<void>.delayed(Duration.zero);

      expect(world.variables.getValue('var_force'), 20);

      world.dispose();
    });

    test('dependency graph updates only affected computed nodes', () async {
      final world = RuntimeLoader.loadFromManifest(
        _manifest(
          variables: [
            _variable('var_a', 'A', 'numberInput', 1),
            _variable('var_b', 'B', 'numberInput', 3),
            _variable('var_mass', 'Mass', 'numberInput', 2),
            _variable('var_accel', 'Acceleration', 'numberInput', 6),
            _variable('var_avg', 'Average', 'average', 0, {
              'dependencies': ['var_a', 'var_b'],
            }),
            _variable('var_force', 'Force', 'force', 0, {
              'massVariable': 'var_mass',
              'accelerationVariable': 'var_accel',
            }),
          ],
        ),
      );
      final evaluatedIds = <String>[];
      final subscription = world.eventBus.stream.listen((event) {
        if (event.message == 'ComputedVariableEvaluated') {
          evaluatedIds.add(event.metadata?['variableId']?.toString() ?? '');
        }
      });

      world.variables.updateVariable('var_a', 5, source: 'test');
      await Future<void>.delayed(Duration.zero);

      expect(world.variables.getValue('var_avg'), 4);
      expect(world.variables.getValue('var_force'), 12);
      expect(evaluatedIds, contains('var_avg'));
      expect(evaluatedIds, isNot(contains('var_force')));

      await subscription.cancel();
      world.dispose();
    });

    test('rules can consume computed variables', () async {
      final world = RuntimeLoader.loadFromManifest(
        _manifest(
          variables: [
            _variable('var_mass', 'Mass', 'numberInput', 5),
            _variable('var_accel', 'Acceleration', 'numberInput', 5),
            _variable('var_force', 'Force', 'force', 0, {
              'massVariable': 'var_mass',
              'accelerationVariable': 'var_accel',
            }),
          ],
          rules: [
            {
              'ruleId': 'rule_force_warning',
              'name': 'Force Warning',
              'trigger': 'variableChanged',
              'condition': {
                'variableId': 'var_force',
                'operator': '>',
                'value': 20,
              },
              'action': {'type': 'show_warning', 'message': 'Force is high'},
            },
          ],
        ),
      );
      final messages = <String>[];
      final subscription = world.eventBus.stream.listen((event) {
        messages.add(event.message);
      });

      world.variables.updateVariable('var_accel', 6, source: 'test');
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(world.variables.getValue('var_force'), 30);
      expect(messages, contains('RuleFired'));
      expect(messages, contains('Force is high'));

      await subscription.cancel();
      world.dispose();
    });
  });
}

Map<String, dynamic> _manifest({
  required List<Map<String, dynamic>> variables,
  List<Map<String, dynamic>> objects = const [],
  List<Map<String, dynamic>> rules = const [],
}) {
  return {
    'metadata': {'title': 'Variable Execution Test'},
    'scene': {'variables': variables, 'objects': objects, 'rules': rules},
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

Map<String, dynamic> _object(
  String id,
  String objectType,
  Map<String, dynamic> properties,
  Map<String, dynamic> state,
) {
  return {
    'objectId': id,
    'objectType': objectType,
    'properties': properties,
    'state': state,
  };
}
